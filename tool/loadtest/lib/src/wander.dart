import 'dart:math';

import 'package:protocol/protocol.dart';

/// A bot's idea of where it is and where it is going.
///
/// Pure movement maths, no socket: the wandering is the part that has to be
/// *believable*, so it is the part that gets unit-tested.
///
/// Believable matters more than it sounds. A bot that teleports to a random
/// point every tick would touch a different grid cell every time, thrash the
/// interest index, and hand back load numbers that describe a world nobody is
/// ever going to build. These bots walk: they pick a destination, head
/// towards it at a human pace, stand around for a moment when they arrive,
/// then pick another. That produces the thing a real conference produces —
/// slowly changing neighbourhoods, with clumps.
class Wanderer {
  /// Creates a wanderer somewhere random in the world.
  ///
  /// [random] is injectable so a load run can be replayed and a test can
  /// assert on exact positions.
  ///
  /// [spec] is the map to wander: it decides the bounds, the spawn point and
  /// where the floor is. Defaulted to the conference so every existing caller
  /// and every existing test means what it meant before Phase 10.
  Wanderer({
    required Random random,
    double speed = defaultSpeed,
    this.spec = MapSpec.conference,
    this.arrivalRadius = defaultArrivalRadius,
    this.maxPause = defaultMaxPause,
    this.clusterRadius,
  }) : _random = random,
       // A little spread in walking pace, so 200 bots do not move as one
       // organism — real crowds have dawdlers.
       speed = speed * (0.7 + random.nextDouble() * 0.6) {
    final start = _randomFloorPoint();
    x = start.x;
    y = start.y;
    _pickTarget();
  }

  /// The walking speed the client uses, in world units per second.
  ///
  /// Matched to the real bean so the load is the load a real crowd makes.
  static const double defaultSpeed = 140;

  /// How close counts as arrived, in world units.
  static const double defaultArrivalRadius = 8;

  /// The longest a bot stands still on arriving, in seconds.
  static const double defaultMaxPause = 3;

  /// The map this bot is walking.
  final MapSpec spec;

  /// This bot's walking speed, in world units per second.
  final double speed;

  /// How close counts as arrived, in world units.
  final double arrivalRadius;

  /// The longest this bot stands still on arriving, in seconds.
  final double maxPause;

  /// When set, the bot never leaves this radius of the map's spawn point.
  ///
  /// The crowded-world case, and the one a spread-out load test never
  /// produces: everybody piled into the atrium at once. That is what the
  /// interest grid is worst at — one hot cell with everybody in it — and it
  /// is what the nametags, the minimap and the frame rate all have to survive
  /// on a real phone. A run with bots evenly scattered over 1600×1200 tests
  /// the easy case and calls it a pass.
  final double? clusterRadius;

  final Random _random;

  /// Position along the world's x axis, in world units.
  late double x;

  /// Position along the world's y axis, in world units.
  late double y;

  late double _targetX;
  late double _targetY;
  double _pause = 0;

  /// Where this bot is currently heading.
  ({double x, double y}) get target => (x: _targetX, y: _targetY);

  /// Whether the bot is standing still at its destination.
  bool get isPaused => _pause > 0;

  /// Advances the bot by [dt] seconds.
  void update(double dt) {
    if (_pause > 0) {
      _pause -= dt;
      return;
    }

    final dx = _targetX - x;
    final dy = _targetY - y;
    final distance = sqrt(dx * dx + dy * dy);
    if (distance <= arrivalRadius) {
      // Arrived. Stand around for a bit like a person reading a schedule,
      // then head somewhere else.
      _pause = _random.nextDouble() * maxPause;
      _pickTarget();
      return;
    }

    final step = speed * dt;
    if (step >= distance) {
      x = _targetX;
      y = _targetY;
      return;
    }
    // No collision: a bot walks through the furniture. That is deliberate —
    // the load test measures the *server*, and the server has no idea where
    // the stage is. Making bots avoid it would be simulating the client's
    // physics to produce identical traffic.
    x = spec.clampX(x + dx / distance * step);
    y = spec.clampY(y + dy / distance * step);
  }

  void _pickTarget() {
    final target = _randomFloorPoint();
    _targetX = target.x;
    _targetY = target.y;
  }

  /// Picks a point a bean could actually stand on.
  ///
  /// The conference is a cross inside a rectangle, so a third of its bounding
  /// box is outside the building; the beach fills its own box entirely.
  /// Rejection sampling handles both without knowing which is which — and it
  /// is the right shape anyway, because picking a *zone* first would put the
  /// same number of bots in the atrium as in the sponsor row regardless of
  /// their size, and the point of a load test is the density, not the head
  /// count.
  ({double x, double y}) _randomFloorPoint() {
    final cluster = clusterRadius;
    for (var attempt = 0; attempt < 64; attempt++) {
      final double px;
      final double py;
      if (cluster != null) {
        final angle = _random.nextDouble() * 2 * pi;
        final radius = cluster * sqrt(_random.nextDouble());
        px = spec.spawnCenterX + cos(angle) * radius;
        py = spec.spawnCenterY + sin(angle) * radius;
      } else {
        px = _random.nextDouble() * spec.width;
        py = _random.nextDouble() * spec.height;
      }
      if (spec.isOnFloor(px, py)) return (x: px, y: py);
    }
    // Somewhere always on the floor, so a pathological cluster radius still
    // produces a walking bot rather than an exception.
    return (x: spec.spawnCenterX, y: spec.spawnCenterY);
  }
}
