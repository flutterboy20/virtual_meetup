import 'dart:math' as math;
import 'dart:ui';

import 'package:client/game/game_map.dart';
import 'package:flame/components.dart';

/// The bulbs strung over the walkways.
///
/// Live rather than baked into the static picture, because a recorded display
/// list is exactly that — a recording — and a string of lights that never
/// twinkles is a string of dots.
///
/// It is cheap enough to be live: 60 bulbs off **one** accumulator, two draw
/// ops each, plus one polyline per run for the cable. There is no per-bulb
/// timer and no per-bulb state — each one's phase is a fixed offset from the
/// same number, which is the same trick the pool's crests use.
///
/// **Drawn under the beans, not over them.** Physically the lights are
/// overhead and should occlude, but the entire readability argument of this
/// world is that you can find your bean and read a name at arm's length on a
/// phone, and glowing dots drifting across faces is the fastest way to lose
/// that. Correct lighting that hides the thing the lighting is for is not
/// correct.
class StringLightsComponent extends PositionComponent {
  /// Creates the lights along [runs].
  StringLightsComponent({this.runs = const []}) : super(priority: -19);

  /// How far apart the bulbs sit along a run, in world units.
  static const double spacing = 46;

  /// How far each run sags in the middle, in world units.
  static const double sag = 22;

  static const Color _bulb = Color(0xFFFFD79A);
  static const Color _cable = Color(0x59463A28);

  /// The runs, as start and end points in world units.
  ///
  /// Comes from the map since Phase 10 — see `GameMap.lightRuns`. A run
  /// strung over the conference's atrium would be hanging in mid-air over the
  /// beach's sea, so the coordinates belong to the place, not to the lights.
  /// An empty list is a perfectly good answer, and renders nothing.
  final List<LightRun> runs;

  double _phase = 0;

  @override
  void update(double dt) {
    super.update(dt);
    _phase = (_phase + dt * 1.1) % (2 * math.pi);
  }

  @override
  void render(Canvas canvas) {
    final cable = Paint()
      ..color = _cable
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    var index = 0;
    for (final run in runs) {
      final from = Offset(run.x1, run.y1);
      final to = Offset(run.x2, run.y2);
      final mid = Offset(
        (from.dx + to.dx) / 2,
        (from.dy + to.dy) / 2 + sag,
      );
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy),
        cable,
      );

      final length = (to - from).distance;
      final steps = math.max(2, (length / spacing).round());
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        // The point on the same quadratic the cable is drawn along, so a bulb
        // is never hanging off its own wire.
        final at = _onCurve(from, mid, to, t);
        final glow = 0.55 + 0.45 * math.sin(_phase + index * 0.9);
        canvas
          ..drawCircle(
            at,
            9,
            Paint()..color = _bulb.withValues(alpha: 0.16 * glow),
          )
          ..drawCircle(
            at,
            3,
            Paint()..color = _bulb.withValues(alpha: 0.55 + 0.45 * glow),
          );
        index++;
      }
    }
  }

  static Offset _onCurve(Offset a, Offset control, Offset b, double t) {
    final u = 1 - t;
    return Offset(
      u * u * a.dx + 2 * u * t * control.dx + t * t * b.dx,
      u * u * a.dy + 2 * u * t * control.dy + t * t * b.dy,
    );
  }
}

/// A soft darkening at the edges of the screen.
///
/// Lives in the **viewport**, not the world: a vignette that scrolled with the
/// camera would be a dark patch sliding around the map, which is a bug rather
/// than an atmosphere.
///
/// Deliberately faint. The world was rebased to warm daylight in Phase 9 and
/// the point of that was readability in a bright hall — a heavy vignette would
/// undo it, and on a phone at half brightness outdoors it would just look like
/// a dirty screen.
class VignetteComponent extends PositionComponent {
  /// Creates the vignette.
  VignetteComponent() : super(priority: 100);

  /// How dark the corners get, from 0 to 1.
  static const double strength = 0.16;

  static const Color _edge = Color(0xFF2A1F10);

  Rect _area = Rect.zero;
  Paint? _paint;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _area = Offset.zero & Size(size.x, size.y);
    // Rebuilt on resize only. A radial gradient is a shader object, and
    // allocating one per frame to draw a static overlay is exactly the kind of
    // per-frame cost the whole phase was spent removing.
    _paint = Paint()
      ..shader = Gradient.radial(
        _area.center,
        _area.longestSide * 0.62,
        [
          _edge.withValues(alpha: 0),
          _edge.withValues(alpha: strength * 0.35),
          _edge.withValues(alpha: strength),
        ],
        const [0, 0.72, 1],
      );
  }

  @override
  void render(Canvas canvas) {
    final paint = _paint;
    if (paint != null) canvas.drawRect(_area, paint);
  }
}
