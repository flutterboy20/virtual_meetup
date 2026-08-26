import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/app_fonts.dart';
import 'package:client/game/beach_props.dart';
import 'package:client/game/bean_animation.dart';
import 'package:client/game/bean_appearance.dart';
import 'package:client/game/bean_art.dart';
import 'package:flame/components.dart';

/// The bean standing on the sand who knows something.
///
/// Purely client-side. It is not a player, it is not in any registry, it has
/// no session and it costs the server and the wire exactly nothing — every
/// client draws the same bean in the same place from the same constants,
/// which is how every other prop on this map already works.
///
/// It is a component rather than an entry in the furniture [Picture] for one
/// reason: it bobs. A display list is a recording, and a bean recorded into
/// one is a bean frozen on its first frame.
///
/// It has **no collision**. Walking through a bean is odd; a solid obstacle
/// standing in the middle of the only dry band on the map is worse, and this
/// map's rule is already that scenery is drawn and not collided.
class HintBeanComponent extends Component {
  /// Creates the hint bean standing at ([x], [y]).
  HintBeanComponent({required this.x, required this.y})
    : // Same priority as a real bean, so it sorts into the crowd rather than
      // floating over it or hiding under it.
      super(priority: 0);

  /// A look no player can pick.
  ///
  /// Drawn with the real [BeanArt] so it is unmistakably one of us, but in a
  /// fixed sand-bleached colour with no hat, so it never reads as an actual
  /// attendee who has been standing suspiciously still for two hours.
  static const BeanAppearance appearance = BeanAppearance(
    bodyColor: Color(0xFFE9C89A),
    cosmeticColor: Color(0xFF6B4A28),
  );

  /// How far above the bean's head the bubble floats, in world units.
  static const double bubbleLift = 15;

  /// How wide the bubble is, in world units.
  static const double bubbleRadius = 12;

  /// Where the bean's feet are, in world units.
  final double x;

  /// Where the bean's feet are, in world units.
  final double y;

  /// The idle bob, borrowed whole from the beans.
  ///
  /// Fed a zero velocity every frame, which is what [BeanAnimation] calls
  /// standing still: it breathes rather than walking. Reusing it rather than
  /// writing a sine here means this bean is alive in exactly the same way
  /// every other bean is.
  final BeanAnimation animation = BeanAnimation(maxSpeed: 1);

  static final Vector2 _still = Vector2.zero();
  static final BeanPaints _paints = BeanPaints(appearance);
  static Paragraph? _glyph;

  double _phase = 0;

  @override
  void update(double dt) {
    super.update(dt);
    animation.update(dt, _still);
    _phase = (_phase + dt * 2.4) % (2 * math.pi);
  }

  @override
  void render(Canvas canvas) {
    final feet = Offset(x, y);
    canvas
      ..drawOval(
        Rect.fromCenter(
          center: feet,
          width: BeanArt.bodyWidth * 0.88,
          height: BeanArt.bodyWidth * 0.32,
        ),
        Paint()..color = const Color(0x4D000000),
      )
      ..save()
      ..translate(feet.dx, feet.dy + animation.bobOffset)
      ..scale(animation.scaleX, animation.scaleY);
    BeanArt.paintBean(canvas, _paints);
    canvas.restore();

    _renderBubble(
      canvas,
      Offset(
        x,
        y -
            BeanArt.bodyHeight -
            bubbleLift +
            math.sin(_phase) * 1.8 +
            animation.bobOffset,
      ),
    );
  }

  /// The `!` over its head.
  ///
  /// The whole of the "there is something here" signal, and deliberately not
  /// a nametag or a speech bubble with words in it: a `!` is legible at a
  /// glance from across the sand and says nothing until you walk up and tap.
  void _renderBubble(Canvas canvas, Offset at) {
    canvas
      ..drawCircle(at, bubbleRadius, Paint()..color = const Color(0xFFF6F1E4))
      ..drawCircle(
        at,
        bubbleRadius,
        Paint()
          ..color = BeachProps.shade(BeachProps.boardStripe, -0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      )
      // The little tail, so it reads as a bubble and not as a badge.
      ..drawPath(
        Path()
          ..moveTo(at.dx - 4, at.dy + bubbleRadius - 1)
          ..lineTo(at.dx, at.dy + bubbleRadius + 6)
          ..lineTo(at.dx + 4, at.dy + bubbleRadius - 1)
          ..close(),
        Paint()..color = const Color(0xFFF6F1E4),
      );

    final glyph = _glyph ??= _buildGlyph();
    canvas.drawParagraph(
      glyph,
      Offset(at.dx - glyph.width / 2, at.dy - bubbleRadius + 1),
    );
  }

  /// Lays the `!` out once and keeps it.
  ///
  /// A [Paragraph] bakes its colour and its layout in, so building one per
  /// frame would be a text layout sixty times a second to draw one character
  /// that never changes. Same trick the nametags and the emote glyphs use.
  static Paragraph _buildGlyph() {
    final builder =
        ParagraphBuilder(
            ParagraphStyle(
              fontFamily: AppFonts.text,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              textAlign: TextAlign.center,
            ),
          )
          ..pushStyle(TextStyle(color: BeachProps.boardStripe))
          ..addText('!');
    return builder.build()..layout(const ParagraphConstraints(width: 24));
  }
}
