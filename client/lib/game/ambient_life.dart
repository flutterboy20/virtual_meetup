import 'dart:math' as math;
import 'dart:ui';

import 'package:client/game/diorama_art.dart';
import 'package:flame/components.dart';

/// The small things that make a room feel lived in: dust in the light, the
/// fountain's jet, rings floating in the pool.
///
/// Three components, one rule each: **one accumulator, a capped count, and
/// reduce-motion respected.** Nothing here allocates per frame beyond the
/// point lists it draws, nothing spawns or dies, and every position is a
/// pure function of one clock, so each is tested as maths rather than as
/// pixels. None of it is in the recorded pictures, because all of it moves.

/// A pure hash of [i] in the range 0..1, the same one the floor uses.
double _noise(int i) {
  var h = (i * 374761393 + 668265263) & 0xFFFFFFFF;
  h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;
  return ((h ^ (h >> 16)) & 0xFFFF) / 0xFFFF;
}

/// The positive remainder of [a] divided by [b].
double _wrap(double a, double b) => ((a % b) + b) % b;

/// Dust drifting through the air around the camera.
///
/// A fixed number of motes, each drifting at its own slow speed through a
/// world-anchored field that wraps around whatever the camera can see: so
/// the dust is always near you, and walking moves you through it rather than
/// carrying it along.
class DustMotes extends Component {
  /// Creates the dust around [visibleWorldRect].
  DustMotes({required this.visibleWorldRect, required this.reduceMotion})
    : super(priority: 12);

  /// The camera, as a rectangle in world units.
  final Rect Function() visibleWorldRect;

  /// Whether the player has asked for less motion.
  final bool Function() reduceMotion;

  /// How many motes there ever are.
  ///
  /// Few, and faint: they are drawn over the beans (under the names), so
  /// more than a sprinkle would start to read as snow.
  static const int count = 18;

  /// How long the clock runs before it wraps, in seconds.
  ///
  /// Long enough that nobody sees the loop, short enough that a day-long
  /// session keeps its precision.
  static const double loop = 600;

  double _t = 0;

  /// How far along the drift is, in seconds.
  double get time => _t;

  /// Where every mote is at time [t] inside [visible], and whether it is in
  /// its bright half.
  static List<({Offset at, bool bright})> motes(Rect visible, double t) {
    if (visible.isEmpty) return const [];
    return [
      for (var i = 0; i < count; i++)
        (
          at: Offset(
            visible.left +
                _wrap(
                  _noise(i) * 1000 +
                      (4 + 6 * _noise(i + 100)) * t -
                      visible.left,
                  visible.width,
                ),
            visible.top +
                _wrap(
                  _noise(i + 200) * 1000 -
                      (2 + 4 * _noise(i + 300)) * t -
                      visible.top,
                  visible.height,
                ),
          ),
          bright: math.sin(t * 0.7 + i) > 0,
        ),
    ];
  }

  static final Paint _bright = Paint()
    ..color = const Color(0x8CFFF6E0)
    ..strokeWidth = 2.6
    ..strokeCap = StrokeCap.round;

  static final Paint _dim = Paint()
    ..color = const Color(0x40FFF6E0)
    ..strokeWidth = 1.8
    ..strokeCap = StrokeCap.round;

  @override
  void update(double dt) {
    if (reduceMotion()) return;
    _t = (_t + dt) % loop;
  }

  @override
  void render(Canvas canvas) {
    if (reduceMotion()) return;
    final all = motes(visibleWorldRect(), _t);
    canvas
      ..drawPoints(PointMode.points, [
        for (final mote in all)
          if (mote.bright) mote.at,
      ], _bright)
      ..drawPoints(PointMode.points, [
        for (final mote in all)
          if (!mote.bright) mote.at,
      ], _dim);
  }
}

/// The fountain's jet: a column of water and the drops falling off it.
class FountainJet extends Component {
  /// Creates the jet rising from the middle of [surface].
  FountainJet({
    required this.surface,
    required this.visibleWorldRect,
    required this.reduceMotion,
  }) : super(priority: -17);

  /// The fountain's water, as a circle.
  final ({Offset centre, double radius}) surface;

  /// The camera, as a rectangle in world units.
  final Rect Function() visibleWorldRect;

  /// Whether the player has asked for less motion.
  final bool Function() reduceMotion;

  /// How high the jet rises over the water, in world units.
  static const double height = 22;

  /// How many drops are ever in the air.
  static const int drops = 12;

  /// How long one drop takes from the top of the jet to the water, in
  /// seconds.
  static const double fall = 1.1;

  double _t = 0;

  /// The drops on a jet over [surface] at time [t].
  ///
  /// Each drop leaves the top of the jet and falls outwards on a parabola to
  /// the water: its own direction, its own point in the cycle, all from one
  /// clock. Lifted up the screen by its height the way every prop is.
  static List<Offset> dropsAt(
    ({Offset centre, double radius}) surface,
    double t,
  ) => [for (var i = 0; i < drops; i++) _dropAt(surface, t, i)];

  static Offset _dropAt(
    ({Offset centre, double radius}) surface,
    double t,
    int i,
  ) {
    // How far through its fall, 0 at the top of the jet to 1 at the water.
    final u = _wrap(t / fall + i / drops, 1);
    final angle = i * 2 * math.pi / drops + 0.3;
    final out = surface.radius * 0.6 * u;
    return surface.centre +
        Offset(
          math.cos(angle) * out,
          // Squashed north-south like everything on the floor, and lifted by
          // its height like everything standing on it.
          math.sin(angle) * out * 0.55 - height * (1 - u * u) * DioramaArt.lift,
        );
  }

  static final Paint _column = Paint()
    ..color = const Color(0xB3E6F8FF)
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round;

  static final Paint _drop = Paint()
    ..color = const Color(0xCCE6F8FF)
    ..strokeWidth = 2.4
    ..strokeCap = StrokeCap.round;

  @override
  void update(double dt) {
    if (reduceMotion()) return;
    _t = (_t + dt) % (fall * drops);
  }

  @override
  void render(Canvas canvas) {
    if (reduceMotion()) return;
    final bounds = Rect.fromCircle(
      center: surface.centre,
      radius: surface.radius + height,
    );
    if (!visibleWorldRect().overlaps(bounds)) return;
    final sway = math.sin(_t * 3) * 1.2;
    canvas
      ..drawLine(
        surface.centre,
        surface.centre.translate(sway, -height * DioramaArt.lift),
        _column,
      )
      ..drawPoints(PointMode.points, dropsAt(surface, _t), _drop);
  }
}

/// Inflatable rings drifting on the pool.
///
/// Under reduce-motion they stay where they are rather than vanish: a ring
/// on the water is a thing in the room, and only its drifting is motion.
class PoolRings extends Component {
  /// Creates the rings floating in [pool].
  PoolRings({
    required this.pool,
    required this.visibleWorldRect,
    required this.reduceMotion,
  }) : super(priority: -19);

  /// The water the rings float on.
  final Rect pool;

  /// The camera, as a rectangle in world units.
  final Rect Function() visibleWorldRect;

  /// Whether the player has asked for less motion.
  final bool Function() reduceMotion;

  /// How many rings float in the pool.
  static const int count = 2;

  /// A ring's outer radius, in world units.
  static const double radius = 12;

  /// How far a ring keeps from the pool's rim, in world units.
  static const double margin = 8;

  /// How long the clock runs before it wraps, in seconds.
  static const double loop = 600;

  static final List<Paint> _tubes = [
    for (final color in const [Color(0xFFFF6B6B), Color(0xFFFFD23F)])
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.5,
  ];

  static final Paint _shadow = Paint()
    ..color = DioramaArt.shadowColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6.5;

  static final Paint _band = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6.5;

  double _t = 0;

  /// How far along the drift is, in seconds.
  double get time => _t;

  /// Where ring [i] floats in [pool] at time [t].
  ///
  /// A slow figure-of-eight about the pool's middle, at two frequencies that
  /// never line up, so the two rings wander without ever repeating a
  /// pattern anyone would notice. Each stays [margin] clear of the rim.
  static Offset ringAt(int i, Rect pool, double t) {
    final reachX = pool.width / 2 - radius - margin;
    final reachY = pool.height / 2 - radius - margin;
    final phase = i * 2.1;
    return pool.center +
        Offset(
          reachX * math.sin(t * 0.071 + phase),
          reachY * math.sin(t * 0.053 + phase * 1.7),
        );
  }

  @override
  void update(double dt) {
    if (reduceMotion()) return;
    _t = (_t + dt) % loop;
  }

  @override
  void render(Canvas canvas) {
    if (!visibleWorldRect().overlaps(pool)) return;
    for (var i = 0; i < count; i++) {
      final at = ringAt(i, pool, _t);
      final bob = reduceMotion() ? 0.0 : math.sin(_t * 1.9 + i) * 0.6;
      final ring = at.translate(0, bob);
      canvas
        // Its shadow on the water, cast the world's way.
        ..drawCircle(at + DioramaArt.shadowSlope * 4, radius - 3, _shadow)
        ..drawCircle(ring, radius - 3, _tubes[i % _tubes.length]);
      // Four white bands round the tube.
      for (var k = 0; k < 4; k++) {
        canvas.drawArc(
          Rect.fromCircle(center: ring, radius: radius - 3),
          k * math.pi / 2 + 0.3,
          0.35,
          false,
          _band,
        );
      }
    }
  }
}
