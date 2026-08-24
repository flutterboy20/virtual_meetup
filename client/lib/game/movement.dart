import 'dart:math' as math;

import 'package:flame/components.dart';

// Pure movement math for the local bean. Kept free of Flame components so it
// can be unit-tested without a game loop. The local player owns its own
// position (the server is a relay), so this is where movement is decided.

/// Clamps [input] into the unit disk.
///
/// A joystick's relative delta can exceed length 1 in the corners; clamping
/// keeps diagonal movement from being faster than straight movement.
Vector2 clampToUnitDisk(Vector2 input) {
  final length = input.length;
  if (length <= 1) {
    return input.clone();
  }
  return input / length;
}

/// Eases [velocity] towards [target] and returns the new velocity.
///
/// Uses exponential smoothing: the fraction of the remaining gap closed in
/// one step is `1 - e^(-responsiveness * dt)`. That form is frame-rate
/// independent — a 30fps and a 60fps client reach the same velocity after the
/// same wall-clock time — which a naive `v += (target - v) * k` does not give.
///
/// A high [responsiveness] (~14) still feels instant to the thumb while
/// removing the visual "snap" of setting velocity directly.
Vector2 steerVelocity({
  required Vector2 velocity,
  required Vector2 target,
  required double responsiveness,
  required double dt,
}) {
  if (dt <= 0) {
    return velocity.clone();
  }
  final t = 1 - math.exp(-responsiveness * dt);
  return velocity + (target - velocity) * t;
}
