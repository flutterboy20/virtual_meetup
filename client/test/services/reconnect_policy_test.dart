import 'dart:math';

import 'package:client/services/reconnect_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReconnectPolicy backoff', () {
    // A fixed jitter of 1.0 makes every delay its own ceiling, which is what
    // lets the *growth* be asserted without the randomness in the way.
    ReconnectPolicy noJitter() => ReconnectPolicy(random: _FixedRandom(1));

    test('the first retry waits the initial delay', () {
      final policy = noJitter();

      expect(policy.delayFor(1), equals(policy.initialDelay));
    });

    test('the delay doubles per consecutive failure', () {
      final policy = noJitter();

      expect(policy.delayFor(1), const Duration(milliseconds: 500));
      expect(policy.delayFor(2), const Duration(seconds: 1));
      expect(policy.delayFor(3), const Duration(seconds: 2));
      expect(policy.delayFor(4), const Duration(seconds: 4));
      expect(policy.delayFor(5), const Duration(seconds: 8));
      expect(policy.delayFor(6), const Duration(seconds: 16));
    });

    test('the delay stops growing at the cap', () {
      final policy = noJitter();

      // Without a cap this would be over four hours by attempt 25.
      expect(policy.delayFor(7), policy.maxDelay);
      expect(policy.delayFor(25), policy.maxDelay);
      expect(policy.delayFor(1000), policy.maxDelay);
    });

    test('an attempt number below one is treated as the first', () {
      final policy = noJitter();

      expect(policy.delayFor(0), equals(policy.delayFor(1)));
      expect(policy.delayFor(-5), equals(policy.delayFor(1)));
    });

    test(
      'jitter keeps every delay inside half the ceiling and the ceiling',
      () {
        // The bound that matters. The lower half is what stops a retry storm
        // collapsing to zero delay; the upper is the cap still holding.
        final policy = ReconnectPolicy(random: Random(7));

        for (var attempt = 1; attempt <= 12; attempt++) {
          final ceiling = policy.ceilingFor(attempt);
          for (var i = 0; i < 200; i++) {
            final delay = policy.delayFor(attempt);
            expect(
              delay.inMicroseconds,
              greaterThanOrEqualTo(ceiling.inMicroseconds ~/ 2),
              reason: 'attempt $attempt',
            );
            expect(
              delay.inMicroseconds,
              lessThanOrEqualTo(ceiling.inMicroseconds),
              reason: 'attempt $attempt',
            );
          }
        }
      },
    );

    test('jitter actually varies, or it is not jitter', () {
      // Two hundred clients that dropped together must not all come back at
      // the same instant — that is the thundering herd this exists to break.
      final policy = ReconnectPolicy(random: Random(3));
      final delays = <int>{
        for (var i = 0; i < 200; i++) policy.delayFor(4).inMicroseconds,
      };

      expect(delays.length, greaterThan(100));
    });

    test('never returns a negative or zero delay', () {
      final policy = ReconnectPolicy(random: _FixedRandom(0));

      for (var attempt = 1; attempt <= 10; attempt++) {
        expect(policy.delayFor(attempt).inMicroseconds, greaterThan(0));
      }
    });
  });

  group('ReconnectionMachine', () {
    ReconnectionMachine machine() => ReconnectionMachine(
      policy: ReconnectPolicy(random: _FixedRandom(1)),
    );

    test('starts idle, having never connected', () {
      final subject = machine();

      expect(subject.phase, ConnectionPhase.idle);
      expect(subject.attempt, isZero);
      expect(subject.hasConnected, isFalse);
    });

    test('the first attempt is connecting, not reconnecting', () {
      final subject = machine();

      expect(subject.beginAttempt(), ConnectionPhase.connecting);
    });

    test('a successful connection clears the attempt count', () {
      final subject = machine()
        ..beginAttempt()
        ..onConnected();

      expect(subject.phase, ConnectionPhase.connected);
      expect(subject.attempt, isZero);
      expect(subject.hasConnected, isTrue);
      expect(subject.phase.isConnected, isTrue);
      expect(subject.phase.isRecovering, isFalse);
    });

    test('a drop moves to waiting and asks for the first delay', () {
      final subject = machine()
        ..beginAttempt()
        ..onConnected();

      final delay = subject.onDropped();

      expect(subject.phase, ConnectionPhase.waiting);
      expect(subject.phase.isRecovering, isTrue);
      expect(subject.attempt, 1);
      expect(delay, const Duration(milliseconds: 500));
    });

    test('an attempt after a drop is a reconnect', () {
      final subject = machine()
        ..beginAttempt()
        ..onConnected()
        ..onDropped();

      expect(subject.beginAttempt(), ConnectionPhase.reconnecting);
      expect(subject.phase.isRecovering, isTrue);
    });

    test('repeated failures grow the delay', () {
      final subject = machine()
        ..beginAttempt()
        ..onConnected();

      final delays = <Duration>[];
      for (var i = 0; i < 3; i++) {
        delays.add(subject.onDropped());
        subject.beginAttempt();
      }

      expect(delays, [
        const Duration(milliseconds: 500),
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      expect(subject.attempt, 3);
    });

    test('getting back in resets the backoff for the next outage', () {
      // A long session with occasional blips must recover quickly every
      // time, not inherit the previous outage's twenty-second delay.
      final subject = machine()
        ..beginAttempt()
        ..onConnected()
        ..onDropped()
        ..onDropped()
        ..onDropped()
        ..onDropped()
        ..beginAttempt()
        ..onConnected();

      expect(subject.attempt, isZero);
      expect(subject.onDropped(), const Duration(milliseconds: 500));
    });

    test('a full drop, fail, fail, succeed sequence ends connected', () {
      final subject = machine()
        ..beginAttempt()
        ..onConnected()
        ..onDropped()
        ..beginAttempt()
        ..onDropped()
        ..beginAttempt()
        ..onDropped();
      expect(subject.attempt, 3);

      subject
        ..beginAttempt()
        ..onConnected();

      expect(subject.phase, ConnectionPhase.connected);
      expect(subject.attempt, isZero);
    });

    test('reset disarms the retry without forgetting it once worked', () {
      final subject = machine()
        ..beginAttempt()
        ..onConnected()
        ..onDropped()
        ..reset();

      expect(subject.phase, ConnectionPhase.idle);
      expect(subject.attempt, isZero);
      // Still true: this is "we stopped", not "we were never here".
      expect(subject.hasConnected, isTrue);
    });
  });
}

/// A [Random] whose `nextDouble` always answers the same thing.
///
/// Used to take the randomness out of the *growth* tests; the jitter tests
/// use a real seeded [Random] instead.
class _FixedRandom implements Random {
  _FixedRandom(this._value);

  final double _value;

  @override
  double nextDouble() => _value;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}
