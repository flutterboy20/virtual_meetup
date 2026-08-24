import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:test/test.dart';

/// A clock the test moves by hand.
///
/// The same shape `token_bucket_test.dart` uses, and for the same reason: a
/// rate limit tested with `sleep` is a rate limit that flakes on a loaded CI
/// box.
class FakeClock {
  DateTime now = DateTime.utc(2026, 2, 20, 9);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// A socket that throws everything away.
///
/// These tests are about what reaches the *log*, so what reaches the client
/// does not matter and is not recorded.
class _SilentConnection implements PlayerConnection {
  @override
  void send(String data) {}

  @override
  void close() {}
}

/// Matches a string shorter than [limit] characters.
Matcher _isShorterThan(int limit) =>
    predicate<String>((line) => line.length < limit, 'shorter than $limit');

/// Whether [value] holds half of an emoji with the other half missing.
///
/// A lone surrogate is what a naive `substring` leaves behind when it cuts a
/// non-Latin character down the middle.
bool _hasLoneSurrogate(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    final isHigh = unit >= 0xd800 && unit <= 0xdbff;
    final isLow = unit >= 0xdc00 && unit <= 0xdfff;
    if (isLow) return true; // A low half with nothing before it.
    if (!isHigh) continue;
    if (i + 1 == value.length) return true; // A high half with nothing after.
    final next = value.codeUnitAt(i + 1);
    if (next < 0xdc00 || next > 0xdfff) return true;
    i++; // A whole pair; step over its second half.
  }
  return false;
}

void main() {
  group('SecurityLog', () {
    late List<String> lines;
    late FakeClock clock;
    late SecurityLog security;

    setUp(() {
      lines = [];
      clock = FakeClock();
      security = SecurityLog(log: lines.add, now: clock.call);
    });

    test('lets the burst through, so a real incident is legible', () {
      for (var i = 0; i < SecurityLog.defaultBurst; i++) {
        security.write('bad frame $i');
      }

      expect(lines, hasLength(SecurityLog.defaultBurst));
      expect(security.suppressed, isZero);
    });

    test('refuses everything past the burst', () {
      for (var i = 0; i < SecurityLog.defaultBurst + 5000; i++) {
        security.write('bad frame');
      }

      // The whole point: 5,020 hostile frames cost 20 lines of disk, not
      // 5,020. Nothing about the flood's size changes what it costs us.
      expect(lines, hasLength(SecurityLog.defaultBurst));
      expect(security.suppressed, equals(5000));
    });

    test('carries the suppressed count out on the next line through', () {
      for (var i = 0; i < SecurityLog.defaultBurst + 42; i++) {
        security.write('bad frame');
      }
      clock.advance(SecurityLog.defaultRefill);

      security.write('a later frame');

      // An operator needs the fact, not 42 copies of it.
      expect(lines.last, contains('a later frame'));
      expect(lines.last, contains('+42 suppressed'));
      expect(security.suppressed, isZero);
    });

    test('reports nothing extra when nothing was suppressed', () {
      security.write('one bad frame');

      expect(lines.single, equals('one bad frame'));
      expect(lines.single, isNot(contains('suppressed')));
    });

    test('refills, so a slow trickle is never lost', () {
      for (var i = 0; i < SecurityLog.defaultBurst; i++) {
        security.write('spend the burst');
      }
      lines.clear();

      for (var i = 0; i < 5; i++) {
        clock.advance(SecurityLog.defaultRefill);
        security.write('trickle $i');
      }

      expect(lines, hasLength(5));
    });
  });

  group('the relay under a log flood', () {
    test('caps the frame-type guard, which no other limit reaches', () {
      final lines = <String>[];
      final clock = FakeClock();
      final relay = Relay(
        log: lines.add,
        securityLog: SecurityLog(log: lines.add, now: clock.call),
      );
      addTearDown(relay.stop);
      final session = relay.open(_SilentConnection());
      lines.clear();

      // Binary frames, deliberately. This guard runs *above* the per-socket
      // inbound budget — a non-text frame is not worth spending a token on —
      // so before the security sink existed nothing capped it at all.
      for (var i = 0; i < 5000; i++) {
        session.handleData(const <int>[1, 2, 3]);
      }

      expect(lines, hasLength(SecurityLog.defaultBurst));
      expect(lines.first, contains('non-text frame'));
    });

    test('caps unreadable messages and never logs a whole frame', () {
      final lines = <String>[];
      final clock = FakeClock();
      final relay = Relay(
        log: lines.add,
        securityLog: SecurityLog(log: lines.add, now: clock.call),
      );
      addTearDown(relay.stop);
      final session = relay.open(_SilentConnection());
      lines.clear();

      final frame = '{"type":"${'z' * 3000}","version":1}';
      for (var i = 0; i < 500; i++) {
        session.handleData(frame);
      }

      expect(lines.length, lessThanOrEqualTo(SecurityLog.defaultBurst));
      // Both halves of the fix in one assertion: bounded line count, and
      // every line bounded in length rather than carrying 3KiB of a
      // stranger's text.
      expect(lines, everyElement(_isShorterThan(200)));
    });
  });

  group('an unknown message in a log line', () {
    /// The longest field a client could get into a log line before it was
    /// clipped: the player frame ceiling, all of it one tag.
    String hugeTag() => 'x' * Relay.maxInboundFrameBytes;

    test('clips a rawType a client made enormous', () {
      final message = decodeMessage('{"type":"${hugeTag()}","version":1}');

      final line = message.toString();

      // Bounded, and bounded well below the frame that carried it. Without
      // this, one 4KiB frame is 4KiB of disk on a path a client can drive
      // thousands of times a second.
      expect(line.length, lessThan(200));
      expect(line, contains('…'));
      expect(message, isA<UnknownMessage>());
    });

    test('clips a reason a client sent, not only one we wrote', () {
      // `reason` is read straight off the wire when the tag says `unknown`,
      // so it is the client's string too — this is the half that is easy to
      // miss.
      final message = decodeMessage(
        '{"type":"unknown","version":1,"reason":"${'y' * 4000}"}',
      );

      expect(message.toString().length, lessThan(200));
    });

    test('keeps a short tag whole, so the log still says something', () {
      final message = decodeMessage('{"type":"teleport","version":1}');

      expect(message.toString(), contains('teleport'));
      expect(message.toString(), isNot(contains('…')));
    });

    test('strips the newlines an attacker would forge log lines with', () {
      final message = decodeMessage(
        r'{"type":"ok\n2026-01-01  an admin authenticated","version":1}',
      );

      final line = message.toString();

      // One event is one line. A value that can carry a newline is a value
      // that can write its own entries into the log.
      expect(line, isNot(contains('\n')));
      expect(line, contains('ok.2026-01-01'));
    });

    test('does not cut a surrogate pair in half', () {
      // The leading 'a' is what makes this test bite: it pushes the cut to an
      // odd offset, so the 64th code unit is the *first* half of an emoji.
      final message = decodeMessage(
        '{"type":"a${'😀' * 100}","version":1}',
      );

      final line = message.toString();

      // Clipping at a fixed offset can land between the two halves of an
      // emoji. The orphan is dropped rather than written into the log as a
      // lone surrogate.
      expect(_hasLoneSurrogate(line), isFalse);
      expect(line, contains('…'));
    });
  });
}
