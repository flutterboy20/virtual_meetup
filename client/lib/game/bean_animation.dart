import 'dart:math' as math;

import 'package:flame/components.dart';

/// The procedural animation state of one bean.
///
/// There are no sprite sheets in this project: a bean is vector shapes plus
/// the numbers below, all derived from its velocity. Six touches sell "alive"
/// instead of "sliding shape":
///
/// 1. **bob** — the body rises and falls while walking,
/// 2. **shadow** — the ground shadow shrinks as the body rises,
/// 3. **squash** — a short squash-and-stretch impulse on stopping,
/// 4. **flip** — the bean faces the way it last moved horizontally,
/// 5. **lean** — a slight tilt into the direction of travel,
/// 6. **breathe** — a slow idle pulse when standing still.
///
/// This class is pure maths (no `Canvas`, no `Component`) so the feel can be
/// unit-tested and tuned without running a game loop.
class BeanAnimation {
  /// Creates an animation state; every knob has a tuned default.
  BeanAnimation({
    required this.maxSpeed,
    this.bobHeight = 3.4,
    this.bobCyclesPerSecond = 2.6,
    this.squashDuration = 0.22,
    this.squashStrength = 0.16,
    this.breatheCyclesPerSecond = 0.55,
    this.breatheStrength = 0.035,
    this.maxLean = 0.14,
    this.leanResponsiveness = 9,
    this.shadowShrink = 0.35,
  });

  /// Below this fraction of [maxSpeed] the bean counts as standing still.
  static const double _movingThreshold = 0.06;

  /// Horizontal speed under which the bean keeps its current facing.
  static const double _facingThreshold = 0.5;

  /// How much of the squash impulse goes into widening the bean.
  static const double _squashWidthRatio = 0.7;

  /// How much of the breathe pulse goes into narrowing the bean.
  static const double _breatheWidthRatio = 0.5;

  static const double _tau = 2 * math.pi;

  /// Speed (world units per second) that counts as "full pace".
  final double maxSpeed;

  /// Peak height of the walk bob, in world units.
  final double bobHeight;

  /// Bob cycles per second at full pace.
  final double bobCyclesPerSecond;

  /// Seconds the stop-squash takes to decay away.
  final double squashDuration;

  /// Peak vertical squash, as a fraction of the bean's height.
  final double squashStrength;

  /// Idle breathe cycles per second.
  final double breatheCyclesPerSecond;

  /// Peak idle breathe, as a fraction of the bean's height.
  final double breatheStrength;

  /// Peak lean, in radians.
  final double maxLean;

  /// How fast the lean eases towards its target (per second).
  final double leanResponsiveness;

  /// How much the shadow shrinks at the top of the bob (0–1).
  final double shadowShrink;

  double _bobPhase = 0;
  double _breathePhase = 0;
  double _squash = 0;
  double _lean = 0;
  double _facing = 1;
  double _speedRatio = 0;
  bool _wasMoving = false;

  /// Current speed as a fraction of [maxSpeed], clamped to 0–1.
  double get speedRatio => _speedRatio;

  /// How far the body is lifted off the ground right now, in world units.
  double get bobLift => bobHeight * _speedRatio * math.sin(_bobPhase).abs();

  /// Vertical offset to apply to the body; negative is up.
  double get bobOffset => -bobLift;

  /// Multiplier for the ground shadow: it shrinks as the bean rises.
  double get shadowScale {
    if (bobHeight <= 0) {
      return 1;
    }
    return 1 - shadowShrink * (bobLift / bobHeight);
  }

  /// Horizontal scale of the body (squash widens, breathing narrows).
  double get scaleX =>
      (1 + _squashAmount * _squashWidthRatio) *
      (1 - _breatheAmount * _breatheWidthRatio);

  /// Vertical scale of the body (squash flattens, breathing stretches).
  double get scaleY => (1 - _squashAmount) * (1 + _breatheAmount);

  /// `1` when facing right, `-1` when facing left.
  ///
  /// The renderer mirrors the whole bean by this value, so [lean] is measured
  /// in facing space: positive always means "leaning forward".
  double get facing => _facing;

  /// Current lean in radians, positive meaning into the direction of travel.
  double get lean => _lean;

  double get _squashAmount => squashStrength * _squash;

  double get _breatheAmount =>
      breatheStrength * (1 - _speedRatio) * math.sin(_breathePhase);

  /// Advances the animation by [dt] seconds for a bean moving at [velocity].
  void update(double dt, Vector2 velocity) {
    if (dt <= 0) {
      return;
    }

    _speedRatio = maxSpeed <= 0
        ? 0
        : (velocity.length / maxSpeed).clamp(0, 1).toDouble();
    final isMoving = _speedRatio > _movingThreshold;

    if (isMoving) {
      // Step a little faster the faster you walk, but never so slow that a
      // creeping bean looks like it is limping.
      final rate = bobCyclesPerSecond * (0.6 + 0.4 * _speedRatio);
      _bobPhase = (_bobPhase + _tau * rate * dt) % _tau;
    } else {
      // Land the feet on the ground rather than freezing mid-bob.
      _bobPhase = 0;
    }

    if (_wasMoving && !isMoving) {
      _squash = 1;
    }
    _wasMoving = isMoving;
    if (_squash > 0) {
      _squash = math.max(0, _squash - dt / squashDuration);
    }

    _breathePhase = (_breathePhase + _tau * breatheCyclesPerSecond * dt) % _tau;

    if (velocity.x.abs() > _facingThreshold) {
      _facing = velocity.x < 0 ? -1 : 1;
    }

    final forward = maxSpeed <= 0
        ? 0.0
        : (velocity.x * _facing / maxSpeed).clamp(-1, 1).toDouble();
    final targetLean = maxLean * forward;
    _lean += (targetLean - _lean) * (1 - math.exp(-leanResponsiveness * dt));
  }
}
