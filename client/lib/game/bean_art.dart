import 'dart:math' as math;
import 'dart:ui';

import 'package:client/game/bean_appearance.dart';
import 'package:protocol/protocol.dart';

/// How a bean is drawn, independent of what is drawing it.
///
/// Pure `dart:ui`: no Flame, no widgets. That is what lets the same shapes be
/// rendered by the bean component inside the game *and* by the live preview
/// on the setup screen, which is a Flutter `CustomPaint` and knows nothing
/// about the game loop.
///
/// The alternative — a second, hand-drawn "preview bean" in the widget layer —
/// is the kind of duplication that looks harmless for exactly as long as it
/// takes somebody to change the hat in one place and not the other. A preview
/// that lies about what you are about to become is worse than no preview.
class BeanArt {
  const BeanArt._();

  /// Width of the bean's body, in world units.
  static const double bodyWidth = 26;

  /// Height of the bean's body, in world units.
  static const double bodyHeight = 36;

  static const Color _visorColor = Color(0xFF12212B);
  static const Color _eyeColor = Color(0xFFF4FAFF);

  /// The one cosmetic colour a player cannot change.
  ///
  /// [PlayerCosmetic.malingaHair] is *hair*, and hair tinted from the body
  /// colour is a wig made out of your shirt. Every other cosmetic reads better
  /// tinted, because the tint is the second identity signal — see
  /// [BeanPaints.cosmeticFill].
  static const Color hairBlond = Color(0xFFF2C14E);

  /// The colour a [PlayerCosmetic.laserVisor]'s eyes burn in.
  ///
  /// The other cosmetic colour a player cannot change, and for the same
  /// reason [hairBlond] cannot be: a laser is a light, and a light that
  /// happens to match the shirt behind it stops reading as one. Fixed also
  /// means it is a *recognisable* thing across the room — "the one with the
  /// glowing eyes" is a description that works at any body colour.
  static const Color laserGlow = Color(0xFFFF2D55);

  static final Paint _visorPaint = Paint()..color = _visorColor;
  static final Paint _eyePaint = Paint()..color = _eyeColor;
  static final Paint _hairPaint = Paint()..color = hairBlond;
  static final Paint _hairRootPaint = Paint()..color = const Color(0xFFC9922B);

  /// Draws a whole bean in "bean space": origin between the feet, up is -y.
  ///
  /// The caller owns the transform — the game applies a bob, a lean and a
  /// squash from its animation state, the preview applies none — so this
  /// function only ever draws a bean standing straight at the origin.
  static void paintBean(Canvas canvas, BeanPaints paints) {
    _paintBody(canvas, paints);
    _paintFace(canvas);
    _paintCosmetic(canvas, paints);
  }

  /// Draws the contact shadow under a bean whose feet are at [feet].
  ///
  /// Outside [paintBean] because it does not move with the bean's bob: a
  /// shadow that hops along with the body reads as a bean on a trampoline
  /// rather than a bean walking.
  static void paintShadow(
    Canvas canvas,
    Offset feet, {
    required Paint paint,
    double scale = 1,
  }) {
    canvas.drawOval(
      Rect.fromCenter(
        center: feet,
        width: bodyWidth * 0.88 * scale,
        height: bodyWidth * 0.32 * scale,
      ),
      paint,
    );
  }

  static void _paintBody(Canvas canvas, BeanPaints paints) {
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTRB(-bodyWidth / 2, -bodyHeight, bodyWidth / 2, 0),
      const Radius.circular(bodyWidth / 2),
    );
    canvas
      ..drawRRect(body, paints.body)
      ..drawRRect(body, paints.bodyEdge);
  }

  static void _paintFace(Canvas canvas) {
    final visor = RRect.fromRectAndRadius(
      const Rect.fromLTRB(
        -bodyWidth * 0.30,
        -bodyHeight * 0.80,
        bodyWidth * 0.30,
        -bodyHeight * 0.58,
      ),
      const Radius.circular(bodyWidth * 0.14),
    );
    canvas
      ..drawRRect(visor, _visorPaint)
      ..drawCircle(
        const Offset(-bodyWidth * 0.11, -bodyHeight * 0.70),
        bodyWidth * 0.055,
        _eyePaint,
      )
      ..drawCircle(
        const Offset(bodyWidth * 0.11, -bodyHeight * 0.70),
        bodyWidth * 0.055,
        _eyePaint,
      );
  }

  static void _paintCosmetic(Canvas canvas, BeanPaints paints) {
    switch (paints.cosmetic) {
      case PlayerCosmetic.none:
        return;
      case PlayerCosmetic.cap:
        final dome = RRect.fromRectAndCorners(
          const Rect.fromLTRB(
            -bodyWidth * 0.34,
            -bodyHeight,
            bodyWidth * 0.34,
            -bodyHeight * 0.87,
          ),
          topLeft: const Radius.circular(bodyWidth * 0.30),
          topRight: const Radius.circular(bodyWidth * 0.30),
        );
        final brim = RRect.fromRectAndRadius(
          const Rect.fromLTRB(
            bodyWidth * 0.05,
            -bodyHeight * 0.90,
            bodyWidth * 0.62,
            -bodyHeight * 0.865,
          ),
          const Radius.circular(bodyWidth * 0.03),
        );
        canvas
          ..drawRRect(dome, paints.cosmeticFill)
          ..drawRRect(brim, paints.cosmeticFill);
      case PlayerCosmetic.headphones:
        canvas
          ..drawArc(
            const Rect.fromLTRB(
              -bodyWidth * 0.48,
              -bodyHeight * 1.02,
              bodyWidth * 0.48,
              -bodyHeight * 0.58,
            ),
            math.pi,
            math.pi,
            false,
            paints.cosmeticStroke,
          )
          ..drawCircle(
            const Offset(-bodyWidth * 0.48, -bodyHeight * 0.74),
            bodyWidth * 0.14,
            paints.cosmeticFill,
          )
          ..drawCircle(
            const Offset(bodyWidth * 0.48, -bodyHeight * 0.74),
            bodyWidth * 0.14,
            paints.cosmeticFill,
          );
      case PlayerCosmetic.malingaHair:
        _paintHair(canvas);
      case PlayerCosmetic.laserVisor:
        _paintLaserVisor(canvas, paints);
      case PlayerCosmetic.propellerBeanie:
        _paintBeanie(canvas, paints);
    }
  }

  /// Spiky blond curls, in a fixed colour that ignores the player's tint.
  ///
  /// Seven circles on an arc over the crown, each one nudged outwards and up,
  /// plus a darker band where it meets the head so the curls sit *on* the
  /// bean rather than floating over it. Same trick as the garden's foliage:
  /// overlapping blobs read as a mass, and a mass of blobs at this camera
  /// distance reads as hair.
  static void _paintHair(Canvas canvas) {
    // The roots, drawn first so the curls overlap them.
    canvas.drawArc(
      const Rect.fromLTRB(
        -bodyWidth * 0.40,
        -bodyHeight * 1.02,
        bodyWidth * 0.40,
        -bodyHeight * 0.74,
      ),
      math.pi,
      math.pi,
      true,
      _hairRootPaint,
    );

    const curls = 7;
    for (var i = 0; i < curls; i++) {
      // Spread over the top half of the head: pi (left) to 2*pi (right).
      final angle = math.pi + (i + 0.5) / curls * math.pi;
      canvas.drawCircle(
        Offset(
          math.cos(angle) * bodyWidth * 0.40,
          -bodyHeight * 0.90 + math.sin(angle) * bodyHeight * 0.13,
        ),
        // The middle curls are the tallest, which is what stops the mane
        // reading as a row of identical bubbles.
        bodyWidth * (0.13 + 0.05 * math.sin((i + 0.5) / curls * math.pi)),
        _hairPaint,
      );
    }
  }

  /// A laser visor: a dark band across the face with two eyes burning
  /// through it.
  ///
  /// Drawn over the visor the face already has rather than instead of it, so
  /// a bean wearing one is still unmistakably the same bean — the light is
  /// what changed, not the head.
  ///
  /// **The glow is four flat circles, not a blur.** A `MaskFilter` is a real
  /// per-draw cost and this runs per bean per frame, up to a screenful of
  /// them; concentric discs of falling alpha are free and, at this camera
  /// distance, indistinguishable. Same trade every prop's shadow makes.
  ///
  /// The band's arms take the player's tint. The light does not — see
  /// [laserGlow].
  static void _paintLaserVisor(Canvas canvas, BeanPaints paints) {
    const band = Rect.fromLTRB(
      -bodyWidth * 0.40,
      -bodyHeight * 0.78,
      bodyWidth * 0.40,
      -bodyHeight * 0.62,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(band, const Radius.circular(bodyWidth * 0.07)),
        _laserBandPaint,
      )
      // The two arms disappearing round the head, tinted like every other
      // cosmetic: the prop is the identity signal, the light is not.
      ..drawRect(
        const Rect.fromLTRB(
          -bodyWidth * 0.47,
          -bodyHeight * 0.74,
          -bodyWidth * 0.38,
          -bodyHeight * 0.69,
        ),
        paints.cosmeticFill,
      )
      ..drawRect(
        const Rect.fromLTRB(
          bodyWidth * 0.38,
          -bodyHeight * 0.74,
          bodyWidth * 0.47,
          -bodyHeight * 0.69,
        ),
        paints.cosmeticFill,
      );

    // Two eyes, each one four discs: halo, glow, beam, white-hot core. The
    // haloes overlap in the middle on purpose — that brighter bar between
    // them is what makes the whole band read as lit from behind.
    for (var side = -1; side <= 1; side += 2) {
      final eye = Offset(side * bodyWidth * 0.15, -bodyHeight * 0.70);
      canvas
        ..drawCircle(eye, bodyWidth * 0.21, _laserHaloPaint)
        ..drawCircle(eye, bodyWidth * 0.13, _laserGlowPaint)
        ..drawCircle(eye, bodyWidth * 0.07, _laserBeamPaint)
        ..drawCircle(eye, bodyWidth * 0.032, _laserCorePaint);
    }
  }

  /// A snug beanie with a two-blade propeller spinning nowhere on top.
  ///
  /// The propeller does **not** turn. Every cosmetic is drawn by the same
  /// static [paintBean] the setup screen's preview calls, and an animated one
  /// would need a clock this function does not have and the preview could not
  /// share — one bean, two renderers, no chance of the preview lying.
  static void _paintBeanie(Canvas canvas, BeanPaints paints) {
    final dome = RRect.fromRectAndCorners(
      const Rect.fromLTRB(
        -bodyWidth * 0.36,
        -bodyHeight * 1.01,
        bodyWidth * 0.36,
        -bodyHeight * 0.86,
      ),
      topLeft: const Radius.circular(bodyWidth * 0.34),
      topRight: const Radius.circular(bodyWidth * 0.34),
    );
    canvas
      ..drawRRect(dome, paints.cosmeticFill)
      // The turned-up brim, a shade lighter so the hat has two parts.
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(
            -bodyWidth * 0.38,
            -bodyHeight * 0.89,
            bodyWidth * 0.38,
            -bodyHeight * 0.84,
          ),
          const Radius.circular(bodyWidth * 0.03),
        ),
        paints.cosmeticBrim,
      )
      // The spindle.
      ..drawRect(
        const Rect.fromLTRB(
          -bodyWidth * 0.03,
          -bodyHeight * 1.06,
          bodyWidth * 0.03,
          -bodyHeight * 0.99,
        ),
        paints.cosmeticBrim,
      )
      // Two blades, offset in opposite directions so it reads as a propeller
      // caught mid-turn rather than as a cross.
      ..drawOval(
        const Rect.fromLTRB(
          -bodyWidth * 0.34,
          -bodyHeight * 1.09,
          -bodyWidth * 0.02,
          -bodyHeight * 1.04,
        ),
        paints.cosmeticBrim,
      )
      ..drawOval(
        const Rect.fromLTRB(
          bodyWidth * 0.02,
          -bodyHeight * 1.10,
          bodyWidth * 0.34,
          -bodyHeight * 1.05,
        ),
        paints.cosmeticBrim,
      )
      ..drawCircle(
        const Offset(0, -bodyHeight * 1.07),
        bodyWidth * 0.05,
        paints.cosmeticFill,
      );
  }

  static final Paint _laserBandPaint = Paint()..color = const Color(0xFF0A1017);
  static final Paint _laserHaloPaint = Paint()
    ..color = laserGlow.withValues(alpha: 0.20);
  static final Paint _laserGlowPaint = Paint()
    ..color = laserGlow.withValues(alpha: 0.55);
  static final Paint _laserBeamPaint = Paint()..color = laserGlow;
  static final Paint _laserCorePaint = Paint()..color = const Color(0xFFFFF2F5);
}

/// The paints one bean is drawn with, built once per appearance change.
///
/// Cached rather than rebuilt per frame: a `Paint` allocation is cheap and
/// sixty of them per bean per second across every bean on screen is not.
class BeanPaints {
  /// Builds the paints for [appearance].
  BeanPaints(BeanAppearance appearance)
    : cosmetic = appearance.cosmetic,
      body = Paint()..color = appearance.bodyColor,
      // Phase 9 deepened this from 0.18 and thickened it from 1.6. The world
      // used to be dark rooms, where a bright body was its own silhouette;
      // under the daylight rebase every bean's *fill* sits between 1.1:1 and
      // 1.5:1 against the light floors, which is a washed-out bean. Darkening
      // the edge instead of the eight player-facing colours keeps everybody's
      // pick — and it works out per room: on the six light floors the dark
      // edge draws the silhouette (3.4:1 to 9.5:1), and in the deliberately
      // dark conference hall the edge disappears but the bright body is doing
      // the separating (5.5:1 to 6.4:1), which is the original design.
      bodyEdge = Paint()
        ..color = BeanAppearance.darken(appearance.bodyColor, 0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
      cosmeticFill = Paint()..color = appearance.cosmeticColor,
      // A lighter second tone, so a cosmetic can have two parts without
      // needing a second colour in `BeanAppearance` — which would be a second
      // thing on the wire for a hat brim.
      cosmeticBrim = Paint()
        ..color = Color.lerp(
          appearance.cosmeticColor,
          const Color(0xFFFFFFFF),
          0.34,
        )!,
      cosmeticStroke = Paint()
        ..color = appearance.cosmeticColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = BeanArt.bodyWidth * 0.09;

  /// Which cosmetic these paints are for.
  final PlayerCosmetic cosmetic;

  /// Fill of the body.
  final Paint body;

  /// Outline of the body.
  final Paint bodyEdge;

  /// Fill of the cosmetic.
  final Paint cosmeticFill;

  /// A lighter tone of the cosmetic, for a brim, a spindle or a blade.
  final Paint cosmeticBrim;

  /// Stroke of the cosmetic, for the headphone band.
  final Paint cosmeticStroke;
}
