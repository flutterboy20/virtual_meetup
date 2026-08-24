import 'package:client/game/bean_appearance.dart';
import 'package:client/game/bean_art.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';

/// A still bean, drawn with the same code the game draws beans with.
///
/// A `CustomPaint` over [BeanArt] rather than an embedded `GameWidget`: the
/// preview needs no game loop, no camera and no 60fps repaint, and spinning
/// up a second Flame instance to show one motionless character would cost
/// more than the whole setup screen.
class BeanPreview extends StatelessWidget {
  /// Creates a preview of a bean with [color] and [cosmetic].
  const BeanPreview({
    required this.color,
    required this.cosmetic,
    super.key,
    this.scale = 3.0,
  });

  /// The body colour, as a 32-bit ARGB value.
  final int color;

  /// The cosmetic worn on the head.
  final PlayerCosmetic cosmetic;

  /// How much bigger than world size to draw it.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final body = Color(color);
    final appearance = BeanAppearance(
      bodyColor: body,
      cosmetic: cosmetic,
      // The same tint the game applies to a remote player's cosmetic, so the
      // preview shows the hat the world will show.
      cosmeticColor: BeanAppearance.darken(body, 0.34),
    );

    return SizedBox(
      width: BeanArt.bodyWidth * scale,
      // Headroom above the body for the cap and the headphone band, which
      // are drawn slightly past the top of the body box.
      height: BeanArt.bodyHeight * scale * 1.12,
      child: CustomPaint(
        painter: _BeanPreviewPainter(appearance: appearance, scale: scale),
      ),
    );
  }
}

class _BeanPreviewPainter extends CustomPainter {
  _BeanPreviewPainter({required this.appearance, required this.scale})
    : paints = BeanPaints(appearance);

  final BeanAppearance appearance;
  final double scale;
  final BeanPaints paints;

  static final Paint _shadowPaint = Paint()
    ..color = const Color(0xFF000000).withValues(alpha: 0.30);

  @override
  void paint(Canvas canvas, Size size) {
    final feet = Offset(size.width / 2, size.height);
    canvas
      ..save()
      ..translate(feet.dx, feet.dy)
      ..scale(scale);
    // Drawn at the origin because the canvas is already translated to the
    // bean's feet, which is the origin of "bean space".
    BeanArt.paintShadow(canvas, Offset.zero, paint: _shadowPaint);
    BeanArt.paintBean(canvas, paints);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BeanPreviewPainter oldDelegate) =>
      oldDelegate.appearance.bodyColor != appearance.bodyColor ||
      oldDelegate.appearance.cosmetic != appearance.cosmetic ||
      oldDelegate.scale != scale;
}
