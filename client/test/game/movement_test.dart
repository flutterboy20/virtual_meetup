import 'package:client/game/movement.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clampToUnitDisk', () {
    test('leaves a short vector alone', () {
      final input = Vector2(0.3, -0.4);
      final result = clampToUnitDisk(input);

      expect(result.x, closeTo(0.3, 1e-6));
      expect(result.y, closeTo(-0.4, 1e-6));
    });

    test('does not mutate its input', () {
      final input = Vector2(3, 4);
      clampToUnitDisk(input);

      expect(input.x, 3);
      expect(input.y, 4);
    });

    test('clamps a long vector onto the unit circle', () {
      final result = clampToUnitDisk(Vector2(3, 4));

      expect(result.length, closeTo(1, 1e-6));
      expect(result.x, closeTo(0.6, 1e-6));
      expect(result.y, closeTo(0.8, 1e-6));
    });

    test('makes diagonals no faster than straight lines', () {
      final diagonal = clampToUnitDisk(Vector2(1, 1));

      expect(diagonal.length, closeTo(1, 1e-6));
    });
  });

  group('steerVelocity', () {
    Vector2 steer(Vector2 velocity, Vector2 target, double dt) {
      return steerVelocity(
        velocity: velocity,
        target: target,
        responsiveness: 14,
        dt: dt,
      );
    }

    test('moves towards the target without overshooting it', () {
      final result = steer(Vector2.zero(), Vector2(140, 0), 1 / 60);

      expect(result.x, greaterThan(0));
      expect(result.x, lessThan(140));
      expect(result.y, 0);
    });

    test('is responsive: most of the gap closes within ~0.2s', () {
      var velocity = Vector2.zero();
      for (var i = 0; i < 12; i++) {
        velocity = steer(velocity, Vector2(140, 0), 1 / 60);
      }

      expect(velocity.x, greaterThan(140 * 0.9));
    });

    test('settles back to zero when the stick is released', () {
      var velocity = Vector2(140, 0);
      for (var i = 0; i < 120; i++) {
        velocity = steer(velocity, Vector2.zero(), 1 / 60);
      }

      expect(velocity.x, closeTo(0, 0.01));
    });

    test('is frame-rate independent', () {
      var at60 = Vector2.zero();
      for (var i = 0; i < 60; i++) {
        at60 = steer(at60, Vector2(140, 0), 1 / 60);
      }
      var at30 = Vector2.zero();
      for (var i = 0; i < 30; i++) {
        at30 = steer(at30, Vector2(140, 0), 1 / 30);
      }

      expect(at30.x, closeTo(at60.x, 0.5));
    });

    test('returns the current velocity for a zero time step', () {
      final result = steer(Vector2(5, 6), Vector2(140, 0), 0);

      expect(result.x, 5);
      expect(result.y, 6);
    });
  });
}
