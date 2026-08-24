import 'package:client/game/bean_animation.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [steps] frames of [dt] seconds at a constant [velocity].
void _run(
  BeanAnimation animation, {
  required Vector2 velocity,
  int steps = 10,
  double dt = 1 / 60,
}) {
  for (var i = 0; i < steps; i++) {
    animation.update(dt, velocity);
  }
}

void main() {
  const maxSpeed = 140.0;
  BeanAnimation build() => BeanAnimation(maxSpeed: maxSpeed);

  group('speed ratio', () {
    test('is 0 when standing still and 1 at full pace', () {
      final animation = build()..update(1 / 60, Vector2.zero());
      expect(animation.speedRatio, 0);

      animation.update(1 / 60, Vector2(maxSpeed, 0));
      expect(animation.speedRatio, 1);
    });

    test('never exceeds 1, even above the top speed', () {
      final animation = build()..update(1 / 60, Vector2(maxSpeed * 5, 0));
      expect(animation.speedRatio, 1);
    });
  });

  group('bob', () {
    test('is flat while standing still', () {
      final animation = build();
      _run(animation, velocity: Vector2.zero(), steps: 60);
      expect(animation.bobLift, 0);
      expect(animation.bobOffset, 0);
    });

    test('lifts the body while walking, never above the bob height', () {
      final animation = build();
      var maxLift = 0.0;
      for (var i = 0; i < 240; i++) {
        animation.update(1 / 60, Vector2(maxSpeed, 0));
        maxLift = maxLift > animation.bobLift ? maxLift : animation.bobLift;
      }
      expect(maxLift, greaterThan(0));
      expect(maxLift, lessThanOrEqualTo(animation.bobHeight));
    });

    test('lifts up, meaning a negative y offset', () {
      final animation = build();
      _run(animation, velocity: Vector2(maxSpeed, 0), steps: 8);
      expect(animation.bobOffset, lessThan(0));
      expect(animation.bobOffset, -animation.bobLift);
    });
  });

  group('shadow', () {
    test('is full size on the ground and smaller at the top of the bob', () {
      final animation = build();
      _run(animation, velocity: Vector2.zero(), steps: 5);
      expect(animation.shadowScale, 1);

      _run(animation, velocity: Vector2(maxSpeed, 0), steps: 8);
      expect(animation.shadowScale, lessThan(1));
      expect(animation.shadowScale, greaterThan(1 - animation.shadowShrink));
    });
  });

  group('squash', () {
    test('fires when the bean stops and decays back to neutral', () {
      final animation = build();
      _run(animation, velocity: Vector2(maxSpeed, 0), steps: 30);

      // First idle frame: the impulse fires.
      animation.update(1 / 60, Vector2.zero());
      expect(animation.scaleY, lessThan(1));
      expect(animation.scaleX, greaterThan(1));

      // Well past the squash duration it is gone again (idle breathing is
      // the only thing left, so allow a small tolerance).
      _run(animation, velocity: Vector2.zero(), steps: 60);
      expect(animation.scaleY, closeTo(1, animation.breatheStrength * 1.01));
    });

    test('does not fire while walking', () {
      final animation = build();
      _run(animation, velocity: Vector2(maxSpeed, 0), steps: 60);
      expect(animation.scaleY, closeTo(1, 0.001));
    });
  });

  group('facing', () {
    test('starts facing right and flips with horizontal velocity', () {
      final animation = build();
      expect(animation.facing, 1);

      _run(animation, velocity: Vector2(-maxSpeed, 0), steps: 2);
      expect(animation.facing, -1);

      _run(animation, velocity: Vector2(maxSpeed, 0), steps: 2);
      expect(animation.facing, 1);
    });

    test('is kept while moving straight up or down', () {
      final animation = build();
      _run(animation, velocity: Vector2(-maxSpeed, 0), steps: 2);
      _run(animation, velocity: Vector2(0, maxSpeed), steps: 30);
      expect(animation.facing, -1);
    });
  });

  group('lean', () {
    test('eases into the direction of travel and back to upright', () {
      final animation = build();
      expect(animation.lean, 0);

      _run(animation, velocity: Vector2(maxSpeed, 0), steps: 60);
      expect(animation.lean, greaterThan(0));
      expect(animation.lean, lessThanOrEqualTo(animation.maxLean));

      _run(animation, velocity: Vector2.zero(), steps: 120);
      expect(animation.lean, closeTo(0, 0.001));
    });

    test('is measured in facing space, so it stays positive going left', () {
      final animation = build();
      _run(animation, velocity: Vector2(-maxSpeed, 0), steps: 60);
      expect(animation.facing, -1);
      expect(animation.lean, greaterThan(0));
    });
  });

  group('idle breathe', () {
    test('pulses while still and is silent while walking', () {
      final animation = build();
      final idleSamples = <double>[];
      for (var i = 0; i < 120; i++) {
        animation.update(1 / 60, Vector2.zero());
        idleSamples.add(animation.scaleY);
      }
      expect(idleSamples.reduce((a, b) => a > b ? a : b), greaterThan(1));
      expect(idleSamples.reduce((a, b) => a < b ? a : b), lessThan(1));

      _run(animation, velocity: Vector2(maxSpeed, 0), steps: 120);
      expect(animation.scaleY, closeTo(1, 0.001));
    });
  });

  test('ignores non-positive time steps', () {
    final animation = build();
    _run(animation, velocity: Vector2(maxSpeed, 0), steps: 12);
    final lean = animation.lean;

    animation.update(0, Vector2(-maxSpeed, 0));
    expect(animation.lean, lean);
    expect(animation.facing, 1);
  });
}
