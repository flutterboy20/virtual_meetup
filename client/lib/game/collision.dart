import 'dart:math' as math;

import 'package:client/game/game_map.dart';
import 'package:flame/components.dart';

/// Decides where a bean actually ends up when it tries to move.
///
/// Three things about this are deliberate:
///
/// **It is client-side only.** The server is a relay: it never simulates
/// movement, so it never checks a wall. The worst a modified client can do is
/// walk its own bean through the stage, which is a party trick, not an
/// exploit. Paying for server-side collision to prevent that would be paying
/// the entire cost of an authoritative server for nothing.
///
/// **There is no player-player collision.** Beans pass straight through each
/// other. That is a design decision, not an omission: bodies that block each
/// other turn a crowded atrium into a traffic jam and hand every attendee a
/// way to trap somebody in a corner. In a social toy the crowd should be
/// something you walk *through*.
///
/// **The collider is a point — the bean's feet.** A top-down bean is drawn
/// standing at a spot on the floor, and the spot is what the floor plan is
/// about. A full-body box would let a bean's head refuse to pass under a
/// doorway it is standing well clear of.
class WorldCollision {
  /// Creates collision over [layout]'s obstacles.
  const WorldCollision(this.layout);

  /// The world this is collision for.
  final GameMap layout;

  /// Whether a bean's feet may stand at ([x], [y]).
  bool isFree(double x, double y) {
    if (!layout.spec.isOnFloor(x, y)) return false;
    for (final obstacle in layout.obstacles) {
      if (obstacle.contains(x, y)) return false;
    }
    return true;
  }

  /// Returns where a bean moving from [from] to [to] actually ends up.
  ///
  /// The two axes are resolved separately, which is what produces *sliding*:
  /// walking diagonally into the stage keeps the sideways half of the move
  /// and drops the half that would have gone through it. Resolved together,
  /// the same move would stop dead, and a player would have to steer around
  /// every wall by hand — which reads as the controls being broken.
  ///
  /// No sweep test and no sub-stepping: the bean covers about 2.3 world units
  /// per frame at full speed and the thinnest obstacle in the world is 18,
  /// so there is nothing to tunnel through. If either number ever changes,
  /// this is the comment that should stop you.
  Vector2 resolve({required Vector2 from, required Vector2 to}) {
    // Already somewhere illegal — a booth was moved in config on top of
    // where somebody stood, or a resume put them inside new furniture. Let
    // them walk out rather than sealing them in: a stuck player has no way
    // to report it and no way to fix it.
    if (!isFree(from.x, from.y)) return to.clone();

    final x = isFree(to.x, from.y) ? to.x : from.x;
    final y = isFree(x, to.y) ? to.y : from.y;
    return Vector2(x, y);
  }

  /// Returns the nearest free point to ([x], [y]), searching outwards.
  ///
  /// Only used to place a bean that has been dropped somewhere illegal — a
  /// returning player whose saved spot is now inside a booth. It is a
  /// fallback, so it is allowed to be the slow, obvious ring search; it runs
  /// once per session at most, never in the game loop.
  Vector2 nearestFreePoint(double x, double y, {double step = 16}) {
    if (isFree(x, y)) return Vector2(x, y);
    for (var ring = 1; ring <= 64; ring++) {
      final radius = ring * step;
      for (var i = 0; i < 16; i++) {
        final angle = i / 16 * 2 * math.pi;
        final px = x + radius * math.cos(angle);
        final py = y + radius * math.sin(angle);
        if (isFree(px, py)) return Vector2(px, py);
      }
    }
    // Spawn is always walkable, so this is the guaranteed way home.
    return Vector2(layout.spec.spawnCenterX, layout.spec.spawnCenterY);
  }
}
