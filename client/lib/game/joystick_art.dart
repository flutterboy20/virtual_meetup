import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// How the on-screen joystick fades itself out of the way.
///
/// Pure maths, no Flame, no `Canvas` — which is the whole reason it is its own
/// class. The rule it holds ("full while a thumb is on it, and once the thumb
/// has been off for [idleDelay] it eases down to [idleOpacity]") is a
/// behaviour with a bug in it if it is written wrong, and a behaviour with a
/// bug in it deserves a unit test that does not need a game loop to run.
class JoystickFade {
  /// Creates a fade, starting fully visible.
  JoystickFade({
    this.idleDelay = 2,
    this.idleOpacity = 0.35,
    this.responsiveness = 4,
  }) : _opacity = 1;

  /// How long the stick sits untouched before it starts fading, in seconds.
  final double idleDelay;

  /// How faint the stick goes once it has given up waiting.
  ///
  /// Not zero. A control that disappears completely is a control a first-time
  /// player thinks the app has lost, and the whole point of a *pinned* stick
  /// is that it is always in the same place — which it cannot be if it is
  /// sometimes in no place.
  final double idleOpacity;

  /// How fast the opacity eases towards its target, per second.
  final double responsiveness;

  double _opacity;
  double _idleFor = 0;

  /// The opacity to draw the control at right now, from [idleOpacity] to 1.
  double get opacity => _opacity;

  /// How long it has been since a thumb was last on the stick, in seconds.
  double get idleFor => _idleFor;

  /// Advances the fade by [dt], given whether the stick is being held.
  ///
  /// A thumb landing snaps the control back to full immediately rather than
  /// easing up to it: the fade out is politeness, the fade in would be lag.
  void update(double dt, {required bool active}) {
    if (active) {
      _idleFor = 0;
      _opacity = 1;
      return;
    }
    _idleFor += dt;
    if (_idleFor < idleDelay) {
      _opacity = 1;
      return;
    }
    _opacity += (idleOpacity - _opacity) * (1 - math.exp(-responsiveness * dt));
  }
}

/// The base of the joystick: a ring, an inner track and four direction ticks.
///
/// A drawn control rather than Flame's bare [CircleComponent], because two
/// flat grey circles read as an unfinished placeholder — which is what they
/// were. Everything here is a handful of vector shapes, like every other thing
/// in this world.
///
/// **Every [Paint] is a field.** `render` runs sixty times a second and
/// allocating paints in it is the cheapest possible way to make a HUD control
/// cost more than the world behind it. Only the alpha changes per frame, which
/// is a field write on an existing paint.
///
/// **The anchor is deliberately left at [Anchor.topLeft].** Flame's
/// `JoystickComponent` adds the background as a child at the origin and only
/// re-anchors the *knob* (to centre, at `size / 2`). A centre-anchored
/// background therefore hangs half its width up and to the left of the knob it
/// is supposed to sit under — which is exactly the misalignment this comment
/// exists to stop somebody re-introducing.
class JoystickBase extends PositionComponent {
  /// Creates the base at [radius] world units across, fading with [fade].
  JoystickBase({required double radius, required this.fade})
    : _radius = radius,
      super(size: Vector2.all(radius * 2));

  /// The idle fade this control shares with its knob.
  final JoystickFade fade;

  /// Whether a thumb is currently on the stick.
  ///
  /// Written by the game each frame. The ring thickens and the track lightens
  /// while it is true, which is the only "you are touching this" feedback a
  /// pinned control can give — there is no hover on a phone.
  bool isActive = false;

  static const Color _ringColor = Color(0xFFEAF6FB);
  static const Color _trackColor = Color(0xFF0C1A22);

  final double _radius;

  final Paint _trackPaint = Paint();
  final Paint _ringPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _tickPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void render(Canvas canvas) {
    final alpha = fade.opacity;
    final centre = Offset(_radius, _radius);

    _trackPaint.color = _trackColor.withValues(
      alpha: (isActive ? 0.42 : 0.30) * alpha,
    );
    _ringPaint
      ..color = _ringColor.withValues(alpha: (isActive ? 0.75 : 0.45) * alpha)
      ..strokeWidth = isActive ? 3.4 : 2.2;
    _tickPaint
      ..color = _ringColor.withValues(alpha: 0.34 * alpha)
      ..strokeWidth = 2.4;

    canvas
      ..drawCircle(centre, _radius, _trackPaint)
      ..drawCircle(centre, _radius, _ringPaint)
      // The inner track: the ring the knob travels around, drawn so the
      // control has a middle to aim at rather than being one flat disc.
      ..drawCircle(
        centre,
        _radius * 0.62,
        Paint()
          ..color = _ringColor.withValues(alpha: 0.16 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );

    // Four ticks at the cardinals. Faint on purpose: they say "this thing
    // points" without pretending the stick is eight-way.
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final unit = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        centre + unit * (_radius * 0.74),
        centre + unit * (_radius * 0.88),
        _tickPaint,
      );
    }
  }
}

/// The knob: a filled disc with a rim highlight, brighter while held.
class JoystickKnob extends PositionComponent {
  /// Creates the knob at [radius] world units across, fading with [fade].
  JoystickKnob({required double radius, required this.fade})
    : _radius = radius,
      super(size: Vector2.all(radius * 2));

  /// The idle fade this control shares with its base.
  final JoystickFade fade;

  /// Whether a thumb is currently on the stick.
  bool isActive = false;

  static const Color _knobColor = Color(0xFFEAF6FB);
  static const Color _rimColor = Color(0xFF0C1A22);

  final double _radius;

  final Paint _fillPaint = Paint();
  final Paint _rimPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _shinePaint = Paint();

  @override
  void render(Canvas canvas) {
    final alpha = fade.opacity;
    final centre = Offset(_radius, _radius);

    _fillPaint.color = _knobColor.withValues(
      alpha: (isActive ? 0.96 : 0.78) * alpha,
    );
    _rimPaint
      ..color = _rimColor.withValues(alpha: 0.45 * alpha)
      ..strokeWidth = 2;
    // A highlight up and left, which is where every other shadow in this
    // world says the light comes from.
    _shinePaint.color = const Color(
      0xFFFFFFFF,
    ).withValues(alpha: 0.55 * alpha);

    canvas
      ..drawCircle(centre, _radius, _fillPaint)
      ..drawCircle(centre, _radius, _rimPaint)
      ..drawCircle(
        centre.translate(-_radius * 0.26, -_radius * 0.28),
        _radius * 0.34,
        _shinePaint,
      );
  }
}
