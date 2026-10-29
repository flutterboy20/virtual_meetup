import 'dart:math' as math;
import 'dart:ui';

import 'package:client/game/world_layout.dart';
import 'package:client/game/zone_props.dart';
import 'package:flame/components.dart';
import 'package:protocol/protocol.dart';

/// Two stage spotlights sweeping the hall floor.
///
/// **Live, and cheap.** A beam is one cone and one pool of light, each a
/// gradient fill in [BlendMode.plus], so two beams are four fills a frame.
/// Nothing is allocated per frame: both gradients are built once in the
/// beam's own frame (source at the origin, pointing along +x), and each
/// frame only moves and turns the canvas under them.
///
/// It draws nothing at all when the hall is off camera, which is most of
/// the time for most people, and nothing under reduce-motion: a light that
/// sweeps is motion, and a light frozen mid-sweep is a stain.
///
/// Above the furniture and below the stage screen and the beans: it is light
/// falling on the floor and the seats, not something standing in the room.
class StageSpotsComponent extends Component {
  /// Creates the spots, culled against [visibleWorldRect] and switched off
  /// while [reduceMotion] says so.
  StageSpotsComponent({
    required this.visibleWorldRect,
    required this.reduceMotion,
  }) : super(priority: -15);

  /// The camera, as a rectangle in world units.
  final Rect Function() visibleWorldRect;

  /// Whether the player has asked for less motion.
  final bool Function() reduceMotion;

  /// How long one full sweep, there and back, takes, in seconds.
  ///
  /// Slow: a lighting rig drifting, not a nightclub.
  static const double period = 9;

  /// How far a beam reaches across the floor from its source, in world units.
  static const double reach = 170;

  /// The radius of the pool of light a beam makes, in world units.
  static const double poolRadius = 34;

  /// How far either side of its middle a beam swings, in radians.
  static const double swing = 0.40;

  /// How far a beam's middle leans in towards the centre aisle, in radians.
  ///
  /// Both lights are near the stage's ends, so a beam that swung around
  /// straight down would throw half its pool over the hall's side wall.
  static const double lean = 0.22;

  /// The warm stage-light colour, at the brightness of the pool's centre.
  static const Color light = Color(0x3DFFE2A8);

  /// Where beam [beam] (0 = west, 1 = east) hangs: on the stage's front
  /// edge, near its end.
  static Offset source(int beam) {
    final stage = ZoneProps.rect(WorldLayout.stage);
    return Offset(
      beam == 0 ? stage.left + 30 : stage.right - 30,
      stage.bottom,
    );
  }

  /// The direction beam [beam] points at time [t], in radians.
  ///
  /// Straight down the screen leaned in towards the aisle, swinging on a
  /// sine. The two beams swing in step, mirrored, so they cross in the
  /// middle and part at the ends.
  static double angle(int beam, double t) {
    final sweep = math.sin(2 * math.pi * t / period) * swing;
    return beam == 0 ? math.pi / 2 - lean + sweep : math.pi / 2 + lean + sweep;
  }

  /// The centre of the pool of light beam [beam] makes at time [t].
  static Offset pool(int beam, double t) =>
      source(beam) + Offset.fromDirection(angle(beam, t), reach);

  /// Whether the spots are worth drawing for a camera at [camera].
  static bool isVisible(Rect camera) =>
      camera.overlaps(ZoneProps.rect(WorldZone.hall.rect));

  double _t = 0;

  /// How far into the sweep the lights are, in seconds.
  double get time => _t;

  // Both built once, in the beam's own frame.
  static final Path _cone = Path()
    ..moveTo(0, 0)
    ..lineTo(reach, -poolRadius)
    ..lineTo(reach, poolRadius)
    ..close();

  static final Paint _conePaint = Paint()
    ..blendMode = BlendMode.plus
    // Brightest two-thirds of the way out, and gone again at the cone's flat
    // end, which would otherwise show as a straight edge across the pool.
    ..shader = Gradient.linear(
      Offset.zero,
      const Offset(reach, 0),
      [
        light.withValues(alpha: 0),
        light.withValues(alpha: light.a * 0.55),
        light.withValues(alpha: 0),
      ],
      const [0, 0.68, 1],
    );

  static final Paint _poolPaint = Paint()
    ..blendMode = BlendMode.plus
    ..shader = Gradient.radial(
      const Offset(reach, 0),
      poolRadius * 1.25,
      [light, light.withValues(alpha: 0)],
    );

  @override
  void update(double dt) {
    // Wrapped, so a session left open all day does not lose the sine's
    // precision to an ever-growing clock.
    _t = (_t + dt) % period;
  }

  @override
  void render(Canvas canvas) {
    if (reduceMotion() || !isVisible(visibleWorldRect())) return;
    for (var beam = 0; beam < 2; beam++) {
      final from = source(beam);
      canvas
        ..save()
        ..translate(from.dx, from.dy)
        ..rotate(angle(beam, _t))
        ..drawPath(_cone, _conePaint)
        ..drawCircle(const Offset(reach, 0), poolRadius * 1.25, _poolPaint)
        ..restore();
    }
  }
}
