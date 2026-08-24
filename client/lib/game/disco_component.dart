import 'dart:math' as math;
import 'dart:ui';

import 'package:client/game/beach_layout.dart';
import 'package:client/game/beach_props.dart';
import 'package:flame/components.dart';

/// The thing that makes the pub look open: a spinning record, a mirrorball,
/// and four coloured wedges sweeping the dance floor.
///
/// A **component**, not part of the furniture picture, because every single
/// thing in it moves — and a display list is a recording, so a recorded light
/// sweep is a stripe that never moves again. The floor it sweeps and the booth
/// it stands on are both still baked in `BeachProps`, where they belong.
///
/// **No `MaskFilter`, no blur, no `saveLayer`.** A soft glow over an area this
/// size is a real raster cost on CanvasKit, and the honest alternative is what
/// `ZoneProps.paintHall` already did for the stage wash: flat gradient wedges.
/// At this camera distance nobody can tell, and the frame budget can.
class DiscoComponent extends PositionComponent {
  /// Creates the disco over `BeachLayout.danceFloor`.
  DiscoComponent()
    : // Above the floor and the furniture (-20), below the beans (0): the
      // light falls *on* the deck, and a bean dancing in it is in front of it.
      super(priority: -12);

  /// How fast the record turns, in revolutions per second.
  static const double recordRevolutions = 0.75;

  /// How fast the light sweep goes round, in revolutions per second.
  ///
  /// Slow. A strobe is a headache and, on a phone in a pocket, a battery.
  static const double sweepRevolutions = 0.16;

  /// How many wedges the mirrorball throws.
  static const int wedges = 4;

  /// The colours the wedges are thrown in.
  static const List<Color> wedgeColors = [
    Color(0xFFE2574C),
    Color(0xFF5C7FD1),
    Color(0xFF2F9E8F),
    Color(0xFFEFA92F),
  ];

  double _recordPhase = 0;
  double _sweepPhase = 0;
  double _pulse = 0;

  /// How far round the record is, in radians. Exposed so a test can say it
  /// turns without reaching into a private field.
  double get recordPhase => _recordPhase;

  /// How far round the light sweep is, in radians.
  double get sweepPhase => _sweepPhase;

  static const double _tau = 2 * math.pi;

  final Paint _wedgePaint = Paint();
  final Paint _padPaint = Paint();

  @override
  void update(double dt) {
    super.update(dt);
    _recordPhase = (_recordPhase + _tau * recordRevolutions * dt) % _tau;
    _sweepPhase = (_sweepPhase + _tau * sweepRevolutions * dt) % _tau;
    _pulse = (_pulse + dt * 2.2) % _tau;
  }

  @override
  void render(Canvas canvas) {
    final floor = BeachProps.rect(BeachLayout.danceFloor);
    _renderWedges(canvas, floor);
    _renderPads(canvas, floor);
    _renderBall(canvas);
    _renderRecord(canvas);
  }

  /// Four flat gradient wedges sweeping the floor.
  ///
  /// A gradient shader is a per-paint cost paid once per wedge per frame, not
  /// a raster filter over the whole area — which is the difference between
  /// this and the blur it is standing in for.
  void _renderWedges(Canvas canvas, Rect floor) {
    const from = Offset(BeachLayout.discoX, BeachLayout.discoY);
    final reach = floor.width * 0.9;

    canvas
      ..save()
      // Clipped to the deck: light that fell on the sand beside the floor
      // would read as a rendering bug, not as a light.
      ..clipRRect(
        RRect.fromRectAndRadius(floor, BeachProps.corner),
      );

    for (var i = 0; i < wedges; i++) {
      final angle = _sweepPhase + i * _tau / wedges;
      final color = wedgeColors[i % wedgeColors.length];
      final tip = from + Offset(math.cos(angle), math.sin(angle)) * reach;
      final spread = Offset(-math.sin(angle), math.cos(angle)) * (reach * 0.20);

      _wedgePaint.shader = Gradient.linear(
        from,
        tip,
        [
          color.withValues(alpha: 0.34),
          color.withValues(alpha: 0),
        ],
      );
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..lineTo(tip.dx + spread.dx, tip.dy + spread.dy)
          ..lineTo(tip.dx - spread.dx, tip.dy - spread.dy)
          ..close(),
        _wedgePaint,
      );
    }

    canvas.restore();
    _wedgePaint.shader = null;
  }

  /// Four pads on the deck pulsing in and out of phase.
  ///
  /// The cheapest possible "there is music playing here": four circles whose
  /// radius is a sine. They are quarter-phase apart, so the floor looks like
  /// it is keeping time rather than blinking.
  void _renderPads(Canvas canvas, Rect floor) {
    for (var i = 0; i < 4; i++) {
      final at = Offset(
        floor.left + floor.width * (0.2 + 0.2 * i),
        floor.center.dy,
      );
      final beat = 0.5 + 0.5 * math.sin(_pulse - i * math.pi / 2);
      _padPaint.color = wedgeColors[i % wedgeColors.length].withValues(
        alpha: 0.14 + 0.24 * beat,
      );
      canvas.drawCircle(at, 9 + 5 * beat, _padPaint);
    }
  }

  /// The mirrorball itself, hanging over the floor.
  void _renderBall(Canvas canvas) {
    const at = Offset(BeachLayout.discoX, BeachLayout.discoY);
    const radius = 11.0;

    canvas
      // The wire it hangs from.
      ..drawLine(
        const Offset(BeachLayout.discoX, BeachLayout.discoY - 30),
        at,
        Paint()
          ..color = const Color(0x66101820)
          ..strokeWidth = 1.4,
      )
      ..drawCircle(at, radius, Paint()..color = const Color(0xFF9FB3BE));

    // The facets: eight chords across the ball, alternating light and dark,
    // turning with the sweep so the ball reads as spinning.
    for (var i = 0; i < 8; i++) {
      final angle = _sweepPhase * 3 + i * _tau / 8;
      canvas.drawCircle(
        at + Offset(math.cos(angle), math.sin(angle) * 0.45) * (radius * 0.55),
        radius * 0.26,
        Paint()
          ..color = i.isEven
              ? const Color(0xFFF2F8FB)
              : const Color(0xFF6E838F),
      );
    }
  }

  /// The record on the left deck, as an ellipse whose x-scale oscillates.
  ///
  /// There is no z axis in this world, so a disc seen from above at an angle
  /// is an ellipse — and squeezing its width on a sine is what a spinning one
  /// looks like without a transform, a matrix or a second component.
  void _renderRecord(Canvas canvas) {
    final booth = BeachProps.rect(BeachLayout.djBooth);
    final at = booth.centerLeft.translate(24, 0);
    const radius = 11.0;
    // Never fully edge-on: a disc that vanished once a second would read as a
    // flicker rather than as a turn.
    final squeeze = 0.35 + 0.65 * math.cos(_recordPhase).abs();

    canvas
      ..drawOval(
        Rect.fromCenter(
          center: at,
          width: radius * 2 * squeeze,
          height: radius * 2,
        ),
        Paint()..color = const Color(0xFF14202A),
      )
      // The label, and the groove: two more ovals on the same squeeze, which
      // is what makes the whole thing turn as one object.
      ..drawOval(
        Rect.fromCenter(
          center: at,
          width: radius * 0.9 * squeeze,
          height: radius * 0.9,
        ),
        Paint()..color = const Color(0xFFEFA92F),
      )
      ..drawOval(
        Rect.fromCenter(
          center: at,
          width: radius * 1.5 * squeeze,
          height: radius * 1.5,
        ),
        Paint()
          ..color = const Color(0x59F2F8FB)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
  }
}
