import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:test/test.dart';

/// A clock the test moves by hand.
///
/// The same shape `emote_limiter_test.dart` uses, and for the same reason:
/// rate limits tested with `sleep` are rate limits that flake on a loaded CI
/// box.
class FakeClock {
  DateTime now = DateTime.utc(2026, 2, 20, 9);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// A socket that records what the relay sent it, and counts what it was told.
class CountingConnection implements PlayerConnection {
  final List<String> sent = [];
  bool closed = false;

  List<ProtocolMessage> get messages =>
      sent.map(decodeMessage).toList(growable: false);

  @override
  void send(String data) => sent.add(data);

  @override
  void close() => closed = true;
}

void main() {
  group('TokenBucket', () {
    test('starts full, so the first action is free and instant', () {
      final clock = FakeClock();
      final bucket = TokenBucket(
        burst: 3,
        refill: const Duration(milliseconds: 800),
        now: clock.call,
      );

      expect(bucket.tokens, equals(3));
      expect(bucket.allow(), isTrue);
      expect(bucket.allow(), isTrue);
      expect(bucket.allow(), isTrue);
      expect(bucket.allow(), isFalse);
    });

    test('refills over the injected clock', () {
      final clock = FakeClock();
      final bucket = TokenBucket(
        burst: 2,
        refill: const Duration(milliseconds: 100),
        now: clock.call,
      );
      expect(bucket.allow(), isTrue);
      expect(bucket.allow(), isTrue);
      expect(bucket.allow(), isFalse);

      clock.advance(const Duration(milliseconds: 100));

      expect(bucket.allow(), isTrue);
      expect(bucket.allow(), isFalse);
    });

    test('caps at its burst however long it is left alone', () {
      final clock = FakeClock();
      final bucket = TokenBucket(
        burst: 2,
        refill: const Duration(milliseconds: 100),
        now: clock.call,
      );
      // Drained, so the only tokens left are the ones the clock puts back.
      while (bucket.allow()) {}

      clock.advance(const Duration(hours: 3));

      expect(bucket.allow(), isTrue);
      expect(bucket.allow(), isTrue);
      // Three hours of refill did not bank three hours of tokens.
      expect(bucket.allow(), isFalse);
    });

    test('refills fractionally, not in whole steps', () {
      final clock = FakeClock();
      final bucket = TokenBucket(
        burst: 1,
        refill: const Duration(milliseconds: 100),
        now: clock.call,
      );
      expect(bucket.allow(), isTrue);

      clock.advance(const Duration(milliseconds: 50));
      expect(bucket.allow(), isFalse);

      clock.advance(const Duration(milliseconds: 50));
      expect(bucket.allow(), isTrue);
    });

    test('refuses a burst below one and a non-positive refill', () {
      expect(
        () => TokenBucket(burst: 0, refill: const Duration(seconds: 1)),
        throwsArgumentError,
      );
      expect(
        () => TokenBucket(burst: 1, refill: Duration.zero),
        throwsArgumentError,
      );
    });
  });

  group('the inbound guard', () {
    late FakeClock clock;
    late Relay relay;
    late CountingConnection connection;
    late RelaySession session;

    setUp(() {
      clock = FakeClock();
      relay = Relay(
        log: (_) {},
        newInboundBucket: () => TokenBucket(
          burst: Relay.defaultInboundBurst,
          refill: Relay.defaultInboundRefill,
          now: clock.call,
        ),
      );
      connection = CountingConnection();
      session = relay.open(connection);
    });

    String joinFrame(String sessionId) => encodeMessage(
      JoinMessage(
        sessionId: sessionId,
        name: 'Alice',
        color: 0xFF54C5F8,
        cosmetic: PlayerCosmetic.cap,
      ),
    );

    test('an oversized frame is dropped before it is decoded', () {
      // A frame that *is* valid JSON and *would* seat a player, made too big
      // by a padded name field. If it were decoded, the relay would answer
      // with a welcome; nothing comes back, so nothing decoded it.
      final huge =
          '{"type":"join","version":$protocolVersion,'
          '"sessionId":"a11ce000000000000000000000000001",'
          '"name":"${'x' * (Relay.maxInboundFrameBytes + 1)}",'
          '"color":1,"cosmetic":"cap"}';
      expect(huge.length, greaterThan(Relay.maxInboundFrameBytes));

      session.handleData(huge);

      expect(connection.sent, isEmpty);
      expect(relay.playerCount, equals(0));
    });

    test('an oversized frame costs no rate token either', () {
      // Size is checked first, so a frame the size guard refused never
      // reaches the bucket. Ten huge frames, then a full burst of real ones:
      // if the huge frames had each spent a token, the last real frames would
      // be dropped and the final position would not land.
      for (var i = 0; i < 10; i++) {
        session.handleData('x' * (Relay.maxInboundFrameBytes + 1));
      }

      session.handleData(joinFrame('a11ce000000000000000000000000001'));
      // The join spent one; spend the remaining 59 on moves.
      for (var i = 0; i < Relay.defaultInboundBurst - 1; i++) {
        session.handleData(
          encodeMessage(MoveMessage(x: 200 + i.toDouble(), y: 100)),
        );
      }

      expect(relay.playerCount, equals(1));
      expect(
        relay.registry[session.playerId!]!.x,
        equals(200 + Relay.defaultInboundBurst - 2),
      );
    });

    test('a frame just under the ceiling is still read', () {
      // The boundary from the allowed side, so the guard is a ceiling and not
      // an off-by-one that refuses everything large-ish. A name padded until
      // the whole frame is one unit short of the limit still seats a player.
      const base =
          '{"type":"join","version":$protocolVersion,'
          '"sessionId":"a11ce000000000000000000000000001",'
          '"name":"A","color":1,"cosmetic":"cap"}';
      final padded = base.replaceFirst(
        '"name":"A"',
        '"name":"A${'a' * (Relay.maxInboundFrameBytes - base.length)}"',
      );
      expect(padded.length, equals(Relay.maxInboundFrameBytes));

      session.handleData(padded);

      // Seated — the frame was decoded. The name itself is refused by the
      // shared name rules, which is a *different* guard and answers with a
      // rejection rather than silence, so this asserts on that answer.
      expect(
        connection.messages.whereType<JoinRejectedMessage>().single.reason,
        equals(JoinRejection.invalidName),
      );
    });

    test('a flood past the rate is dropped and the session survives', () {
      session.handleData(joinFrame('a11ce000000000000000000000000001'));
      expect(relay.playerCount, equals(1));

      // Spend the rest of the burst, then keep going.
      for (var i = 0; i < Relay.defaultInboundBurst * 4; i++) {
        session.handleData(
          encodeMessage(MoveMessage(x: 100 + i.toDouble(), y: 100)),
        );
      }

      final player = relay.registry[session.playerId!]!;
      // The burst was 60 and one went on the join, so 59 moves landed. The
      // 60th onwards were dropped — the position is the 59th move's, not the
      // 240th.
      expect(player.x, equals(100 + Relay.defaultInboundBurst - 2));
      // Dropped, not disconnected. A hostile client must not be able to take
      // its own session down in a way the relay has to clean up.
      expect(connection.closed, isFalse);
      expect(relay.playerCount, equals(1));
    });

    test('the bucket refills, so a throttled client recovers', () {
      session.handleData(joinFrame('a11ce000000000000000000000000001'));
      for (var i = 0; i < Relay.defaultInboundBurst * 2; i++) {
        session.handleData(encodeMessage(const MoveMessage(x: 100, y: 100)));
      }

      clock.advance(Relay.defaultInboundRefill);
      session.handleData(encodeMessage(const MoveMessage(x: 222, y: 222)));

      expect(relay.registry[session.playerId!]!.x, equals(222));
    });

    test(
      '10Hz of moves plus a burst of emotes passes untouched',
      () {
        // The regression test that matters. This is the client's real worst
        // case — position is throttled to exactly 10Hz and emotes are already
        // bucketed — and none of it may ever be refused.
        session.handleData(joinFrame('a11ce000000000000000000000000001'));

        var x = 100.0;
        for (var second = 0; second < 30; second++) {
          for (var frame = 0; frame < 10; frame++) {
            x += 1;
            session.handleData(encodeMessage(MoveMessage(x: x, y: 100)));
            clock.advance(const Duration(milliseconds: 100));
          }
          // Three emotes, which is the client's own emote burst, thrown at
          // the top of every second.
          for (var clap = 0; clap < 3; clap++) {
            session.handleData(
              encodeMessage(const EmoteMessage(emote: EmoteKind.clap)),
            );
          }
        }

        // Every single move landed: 300 of them, from x = 101 to x = 400.
        expect(relay.registry[session.playerId!]!.x, equals(400));
      },
    );
  });
}
