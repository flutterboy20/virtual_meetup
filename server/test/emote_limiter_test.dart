import 'package:server/src/emote_limiter.dart';
import 'package:test/test.dart';

/// A clock the test moves by hand.
///
/// Rate limits are the classic thing to test with `sleep` and then watch flake
/// on a loaded CI box. Driving the clock instead makes the assertions exact
/// and the suite instant.
class FakeClock {
  DateTime now = DateTime.utc(2026, 2, 21, 10);

  void advance(Duration by) => now = now.add(by);
}

void main() {
  late FakeClock clock;
  late EmoteLimiter limiter;

  setUp(() {
    clock = FakeClock();
    // Explicitly the defaults, so the numbers in the assertions below are
    // readable without jumping to another file.
    limiter = EmoteLimiter(now: () => clock.now);
  });

  /// How many of [n] back-to-back attempts by [id] got through.
  int burstOf(String id, int n) {
    var allowed = 0;
    for (var i = 0; i < n; i++) {
      if (limiter.allow(id)) allowed++;
    }
    return allowed;
  }

  group('EmoteLimiter', () {
    test('rejects a nonsense configuration outright', () {
      expect(() => EmoteLimiter(burst: 0), throwsArgumentError);
      expect(
        () => EmoteLimiter(refill: Duration.zero),
        throwsArgumentError,
      );
    });

    test("a newcomer's first emote is instant", () {
      // The button has to feel connected to the tap. Starting a bucket empty
      // would put an 800ms delay on the first reaction of every session.
      expect(limiter.allow('p1'), isTrue);
    });

    test('lets a genuine burst of applause through', () {
      expect(burstOf('p1', EmoteLimiter.defaultBurst), equals(3));
    });

    test('cuts off a held-down button', () {
      expect(burstOf('p1', 20), equals(3));
    });

    test('refills one token per interval', () {
      burstOf('p1', 3);
      expect(limiter.allow('p1'), isFalse);

      clock.advance(const Duration(milliseconds: 800));
      expect(limiter.allow('p1'), isTrue);
      expect(limiter.allow('p1'), isFalse);
    });

    test('refills proportionally, not in whole steps', () {
      burstOf('p1', 3);

      clock.advance(const Duration(milliseconds: 400));
      expect(limiter.allow('p1'), isFalse, reason: 'half a token is not one');

      clock.advance(const Duration(milliseconds: 400));
      expect(limiter.allow('p1'), isTrue);
    });

    test('never banks more than the burst', () {
      // Standing quietly for a minute must not buy a 75-emote barrage.
      clock.advance(const Duration(minutes: 1));

      expect(burstOf('p1', 20), equals(3));
    });

    test('settles at the refill rate under sustained spam', () {
      // Ten seconds of holding the button: three from the burst, plus one
      // per 800ms of elapsed time.
      var allowed = 0;
      for (var i = 0; i < 100; i++) {
        if (limiter.allow('p1')) allowed++;
        clock.advance(const Duration(milliseconds: 100));
      }

      expect(allowed, equals(3 + 100 * 100 ~/ 800));
    });

    test('one spammer does not throttle anybody else', () {
      burstOf('spammer', 20);

      expect(limiter.allow('bystander'), isTrue);
    });

    test('forgets a player, so the map does not grow forever', () {
      limiter.allow('p1');
      expect(limiter.trackedPlayers, equals(1));

      limiter.forget('p1');
      expect(limiter.trackedPlayers, isZero);

      limiter
        ..allow('p2')
        ..clear();
      expect(limiter.trackedPlayers, isZero);
    });
  });
}
