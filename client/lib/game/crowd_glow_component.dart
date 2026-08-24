import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/world_palette.dart';
import 'package:client/game/game_map.dart';
import 'package:flame/components.dart';

/// The warm patch of floor in front of the food court counter.
///
/// A ring painted on the paving that brightens as people stand on it. That is
/// the whole feature: no rules, no timer, no score, no "order up!" moment.
///
/// That restraint is the design. The instant this thing counts down or awards
/// something, it stops being a place people wander onto and becomes a task,
/// and a task in a social toy is a thing to be finished and left. Ambient
/// feedback — it glows more when more of you are here — is enough to make a
/// group of strangers stand in a circle, which is the actual goal.
///
/// Phase 9 re-skinned this from the Phase 5 photo beacon: new place, new
/// colours, **identical smoothing**. Every number in [glowResponsiveness] and
/// the reason for it survived the move, because the failure it prevents did.
class CrowdGlowComponent extends PositionComponent {
  /// Creates the glow at [spot], fed by [crowdAt].
  CrowdGlowComponent({required this.crowdAt, required this.spot})
    : super(priority: -25);

  /// Where the glow sits, how big it is, and whose palette it borrows.
  ///
  /// A map's property since Phase 10 — the conference glows in front of the
  /// food court counter and the beach glows over the dance floor, and
  /// neither of
  /// those coordinates means anything on the other map.
  final GlowSpot spot;

  /// How many beans are standing within a radius of a point.
  ///
  /// A callback rather than a list of players, so this component never learns
  /// what a player *is* — it counts what it is told to count and draws a ring.
  final int Function(double x, double y, double radius) crowdAt;

  /// How many people it takes for the ring to reach full brightness.
  static const int fullCrowd = 6;

  /// How fast the glow eases towards the crowd it is drawing, per second.
  ///
  /// Smoothed rather than instant: one person stepping over the edge should
  /// not make the whole ring flash, and a bean whose idle bob crosses the
  /// boundary would otherwise strobe it.
  static const double glowResponsiveness = 3.2;

  static const Color _lampWarm = Color(0xFFFFC46B);

  double _glow = 0;
  double _pulse = 0;

  /// The current brightness of the ring, from 0 to 1.
  double get glow => _glow;

  @override
  void update(double dt) {
    super.update(dt);
    final crowd = crowdAt(spot.x, spot.y, spot.radius);
    final target = math.min(1, crowd / fullCrowd);
    _glow += (target - _glow) * (1 - math.exp(-glowResponsiveness * dt));
    _pulse = (_pulse + dt * 1.4) % (2 * math.pi);
  }

  @override
  void render(Canvas canvas) {
    final centre = Offset(spot.x, spot.y);
    // Lamplight rather than the zone accent: a terracotta ring on terracotta
    // paving is a ring nobody sees, and the thing this is meant to look like
    // is the pool of light a tea stall's bulbs throw on the street.
    final accent = Color.lerp(
      WorldPalette.of(spot.zone).accent,
      _lampWarm,
      0.55,
    )!;
    final breathe = 1 + 0.03 * math.sin(_pulse) * _glow;

    canvas
      ..drawCircle(
        centre,
        spot.radius * breathe,
        Paint()..color = accent.withValues(alpha: 0.12 + 0.30 * _glow),
      )
      ..drawCircle(
        centre,
        spot.radius * breathe,
        Paint()
          ..color = accent.withValues(alpha: 0.35 + 0.55 * _glow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 + 3 * _glow,
      )
      ..drawCircle(
        centre,
        spot.radius * 0.42,
        Paint()
          ..color = accent.withValues(alpha: 0.20 + 0.45 * _glow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }
}
