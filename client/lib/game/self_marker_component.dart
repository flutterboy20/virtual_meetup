import 'dart:ui';

import 'package:client/game/bean_art.dart';
import 'package:client/game/bean_component.dart';
import 'package:flame/components.dart';

/// The ring on the floor that says which bean is yours.
///
/// The problem it solves is specific: every bean in this world is the same
/// shape, the crowd is dense at spawn, and the camera follows *a* bean rather
/// than announcing which one. Somebody who looks away for a second and looks
/// back has no way to find themselves except by pushing the stick and seeing
/// what moves. A marker under your own feet answers that in one glance.
///
/// **On the floor, not over the head.** The space above a bean is already the
/// nametag's and the emote's, and a third thing up there is a third thing to
/// read. The floor is empty, and a ring on it reads as a spotlight rather
/// than as a label.
///
/// Two rings: a steady one that is always exactly where you are, and a pulse
/// that expands out of it and fades. The steady one is the answer to "which
/// one am I"; the pulse is what makes the eye find it without being told to
/// look — a static ring in a busy room is just more furniture.
class SelfMarkerComponent extends Component {
  /// Creates the marker for [bean].
  SelfMarkerComponent({required this.bean})
    : // Above the floor, the crowd glow, the water and the furniture, and
      // below every bean — including yours. A ring drawn *over* the bean it
      // marks would be a hoop somebody is standing in.
      super(priority: -5);

  /// Whose feet to draw it under.
  final BeanComponent bean;

  /// How long one pulse takes, in seconds.
  ///
  /// Slow on purpose. This is orientation, not an alarm, and anything under
  /// about a second reads as something being wrong.
  static const double pulsePeriod = 2.2;

  /// The colour of both rings.
  ///
  /// Fixed, and deliberately not one of the eight body colours the setup
  /// screen offers: a marker painted in a colour a bean can also be is a
  /// marker that disappears against the one bean it exists to point at.
  static const Color ringColor = Color(0xFF54C5F8);

  /// Width of the steady ring, as a multiple of the bean's body width.
  static const double ringWidth = 1.24;

  /// How much taller than flat the ring is drawn.
  ///
  /// The same squash [BeanArt.paintShadow] uses for the contact shadow, so
  /// the ring lies on the same ground the shadow does rather than standing
  /// up off it.
  static const double ringSquash = 0.34;

  /// How far the pulse expands before it is gone.
  static const double pulseGrowth = 0.7;

  final Paint _steadyPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _pulsePaint = Paint()..style = PaintingStyle.stroke;

  double _phase = 0;

  /// Where in its cycle the pulse is, from 0 (just born) to 1 (just gone).
  ///
  /// Public because it is the only moving part here, and a value that can
  /// only be checked by watching the screen is a value nobody checks.
  double get pulse => _phase;

  @override
  void update(double dt) {
    _phase += dt / pulsePeriod;
    // A modulo rather than a subtraction, so a frame long enough to skip a
    // whole cycle — a tab coming back from the background — lands somewhere
    // sane instead of leaving the phase above 1 forever.
    if (_phase >= 1) _phase %= 1;
  }

  @override
  void render(Canvas canvas) {
    // Under water the ring would be a bright hoop floating on the surface
    // over a bean that is not there any more. It goes with the bean.
    final visible = 1 - bean.swim.submersion;
    if (visible <= 0.01) return;

    final centre = Offset(bean.position.x, bean.position.y);
    const width = BeanArt.bodyWidth * ringWidth;
    const height = width * ringSquash;

    _steadyPaint
      ..color = ringColor.withValues(alpha: 0.55 * visible)
      ..strokeWidth = 2;
    canvas.drawOval(
      Rect.fromCenter(center: centre, width: width, height: height),
      _steadyPaint,
    );

    // The pulse: bigger and fainter the further through its cycle it is, so
    // it reads as one ring travelling outwards rather than as two rings.
    final scale = 1 + _phase * pulseGrowth;
    _pulsePaint
      ..color = ringColor.withValues(alpha: (1 - _phase) * 0.45 * visible)
      ..strokeWidth = 2.4 * (1 - _phase * 0.6);
    canvas.drawOval(
      Rect.fromCenter(
        center: centre,
        width: width * scale,
        height: height * scale,
      ),
      _pulsePaint,
    );
  }
}
