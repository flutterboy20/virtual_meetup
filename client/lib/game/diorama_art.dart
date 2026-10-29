import 'dart:ui';

/// Height for a flat world: the one helper every prop with a top, a front and
/// a shadow is painted through.
///
/// Phase 16's "paper diorama". A prop keeps the footprint it has always had —
/// the `WorldRect` or `CircleObstacle` it collides with — and gains a
/// **height that exists only in the paint**. The top face is lifted up the
/// screen, a darker front (south) face hangs from it back down to the floor,
/// and a shadow falls away from one shared light. Nothing here touches
/// collision: a bean still stops at the footprint, exactly where it stopped
/// before the prop grew, so the Phase 9 / 12 layout tests are the review that
/// no invisible wall came with the height.
///
/// **Geometry and paint are split on purpose.** [topFace], [frontFace],
/// [boxShadow] and friends are pure functions of a footprint and two numbers,
/// so they are tested as numbers rather than as pixels. The `paint*` methods
/// do nothing but hand those shapes to a [Canvas], and everything they draw is
/// recorded once into the furniture picture — see `static_art.dart` — so a
/// prop with three faces costs the same per frame as the flat rectangle it
/// replaces.
///
/// Every height here is in world units, the same units as the footprint. A
/// `base` lifts the whole prop off the floor: a stall canopy on its poles, a
/// backrest standing on a seat.
abstract final class DioramaArt {
  /// How far one unit of height lifts a face up the screen.
  ///
  /// Less than one because the camera looks steeply down, not from the side:
  /// a wall 20 units tall shows about 16 units of face. 0.82 is the number the
  /// A preview was tuned with.
  static const double lift = 0.82;

  /// Where one unit of height lands on the floor as shadow, relative to the
  /// point it is cast from.
  ///
  /// **One light for the whole world**, from the north-west, so every shadow
  /// falls south-east and the room reads as lit by one sun rather than by
  /// forty lamps. Both components are positive, and [boxShadow] relies on
  /// that to know which six corners make the outline.
  static const Offset shadowSlope = Offset(0.62, 0.30);

  /// The colour every cast shadow is filled with: a warm brown, not black, at
  /// 20 %.
  ///
  /// Soft and low-contrast on purpose. A shadow is there to say "this stands
  /// up"; a dark one starts competing with the beans walking through it.
  static const Color shadowColor = Color(0x33231808);

  /// The hairline drawn round a prop's top and front together.
  ///
  /// It is what separates a cream counter from a cream floor without a heavy
  /// outline — the paper-cut edge the diorama look is named for.
  static const Color edgeColor = Color(0x29141420);

  /// How much darker a front face is than the top it hangs from.
  ///
  /// The front faces south, away from the light, so it is the same material
  /// in shade. One number for every prop keeps the light consistent.
  static const double frontShade = -0.16;

  // ---- Box geometry -------------------------------------------------------

  /// The top face of a box standing on [footprint]: the footprint itself,
  /// lifted up the screen by its full height.
  static Rect topFace(
    Rect footprint, {
    required double height,
    double base = 0,
  }) {
    assert(height >= 0 && base >= 0, 'heights are never negative');
    return footprint.translate(0, -(base + height) * lift);
  }

  /// The front face of a box standing on [footprint]: the band between the
  /// top face's south edge and the bottom of the box.
  ///
  /// It shares its top edge with [topFace], so the two never show a crack.
  /// For a box on the floor its bottom edge is the footprint's own south edge;
  /// a raised box stops short of the floor by its [base].
  static Rect frontFace(
    Rect footprint, {
    required double height,
    double base = 0,
  }) {
    assert(height >= 0 && base >= 0, 'heights are never negative');
    return Rect.fromLTRB(
      footprint.left,
      footprint.bottom - (base + height) * lift,
      footprint.right,
      footprint.bottom - base * lift,
    );
  }

  /// The outline of the shadow a box casts on the floor, clockwise.
  ///
  /// The shadow of a block is the footprint swept from where its bottom lands
  /// to where its top lands. With the light from the north-west those two
  /// rectangles are joined by their north-east and south-west corners, which
  /// leaves six corners. A box on the floor starts its shadow at its own
  /// footprint; a raised one casts a shadow that has come loose from it,
  /// which is what makes a canopy read as overhead.
  static List<Offset> boxShadow(
    Rect footprint, {
    required double height,
    double base = 0,
  }) {
    assert(height >= 0 && base >= 0, 'heights are never negative');
    final low = shadowSlope * base;
    final high = shadowSlope * (base + height);
    return [
      footprint.topLeft + low,
      footprint.topRight + low,
      footprint.topRight + high,
      footprint.bottomRight + high,
      footprint.bottomLeft + high,
      footprint.bottomLeft + low,
    ];
  }

  // ---- Cylinder geometry --------------------------------------------------

  /// The centre of a cylinder's top face: its footprint's centre, lifted.
  ///
  /// Still a circle and not an ellipse. The camera looks down, so a round
  /// table top is round; only the side shows the height.
  static Offset cylinderTop(
    Offset centre, {
    required double height,
    double base = 0,
  }) {
    assert(height >= 0 && base >= 0, 'heights are never negative');
    return centre.translate(0, -(base + height) * lift);
  }

  /// The centre of a cylinder's bottom face, which is its footprint's centre
  /// unless it is raised by [base].
  static Offset cylinderFoot(Offset centre, {double base = 0}) {
    assert(base >= 0, 'heights are never negative');
    return centre.translate(0, -base * lift);
  }

  /// The shadow a cylinder casts: a capsule of the cylinder's own radius,
  /// running from where its bottom lands to where its top lands.
  static ({Offset from, Offset to}) cylinderShadow(
    Offset centre, {
    required double height,
    double base = 0,
  }) {
    assert(height >= 0 && base >= 0, 'heights are never negative');
    return (
      from: centre + shadowSlope * base,
      to: centre + shadowSlope * (base + height),
    );
  }

  // ---- Painting -----------------------------------------------------------

  /// Paints only the shadow of a box.
  ///
  /// Public, and separate from [paintBox], because a tall prop's shadow and
  /// its body do not always go in the same picture: a canopy drawn above the
  /// beans still has to cast its shadow on the floor beneath them.
  static void paintBoxShadow(
    Canvas canvas,
    Rect footprint, {
    required double height,
    double base = 0,
  }) {
    canvas.drawPath(
      Path()
        ..addPolygon(boxShadow(footprint, height: height, base: base), true),
      Paint()..color = shadowColor,
    );
  }

  /// Paints a box standing on [footprint]: shadow, front face, top face and
  /// the hairline round them, in that order.
  ///
  /// [color] is the top. The front is [color] in shade unless [front] says
  /// otherwise — a booth's back wall is a different material from its trim.
  /// The front is painted as one shape under the whole box and the top laid
  /// over it, so a rounded [corner] shows the front at the top face's lower
  /// corners, the way a rounded block does.
  static void paintBox(
    Canvas canvas,
    Rect footprint, {
    required double height,
    required Color color,
    double base = 0,
    Color? front,
    Radius corner = Radius.zero,
    bool shadow = true,
  }) {
    if (shadow) {
      paintBoxShadow(canvas, footprint, height: height, base: base);
    }
    final top = topFace(footprint, height: height, base: base);
    final body = RRect.fromRectAndRadius(
      top.expandToInclude(frontFace(footprint, height: height, base: base)),
      corner,
    );
    canvas
      ..drawRRect(body, Paint()..color = front ?? _shade(color, frontShade))
      ..drawRRect(RRect.fromRectAndRadius(top, corner), Paint()..color = color)
      ..drawRRect(body, _edge());
  }

  /// Paints only the shadow of a cylinder. Public for the same reason as
  /// [paintBoxShadow].
  ///
  /// A capsule is a rounded rectangle turned to face along the light, which
  /// is one `drawRRect` rather than two circles and a joining quad.
  static void paintCylinderShadow(
    Canvas canvas,
    Offset centre,
    double radius, {
    required double height,
    double base = 0,
  }) {
    final (:from, :to) = cylinderShadow(centre, height: height, base: base);
    final run = to - from;
    canvas
      ..save()
      ..translate(from.dx, from.dy)
      ..rotate(run.direction)
      ..drawRRect(
        RRect.fromLTRBR(
          -radius,
          -radius,
          run.distance + radius,
          radius,
          Radius.circular(radius),
        ),
        Paint()..color = shadowColor,
      )
      ..restore();
  }

  /// Paints a cylinder standing on the circle at [centre]: shadow, side, top
  /// and the hairline round them.
  ///
  /// The side is a capsule from the top circle down to the bottom circle in
  /// [front] (or [color] in shade); the top circle is laid over its upper end,
  /// which leaves exactly the lower half-round of the side showing.
  static void paintCylinder(
    Canvas canvas,
    Offset centre,
    double radius, {
    required double height,
    required Color color,
    double base = 0,
    Color? front,
    bool shadow = true,
  }) {
    if (shadow) {
      paintCylinderShadow(canvas, centre, radius, height: height, base: base);
    }
    final top = cylinderTop(centre, height: height, base: base);
    final foot = cylinderFoot(centre, base: base);
    final side = RRect.fromLTRBR(
      centre.dx - radius,
      top.dy - radius,
      centre.dx + radius,
      foot.dy + radius,
      Radius.circular(radius),
    );
    canvas
      ..drawRRect(side, Paint()..color = front ?? _shade(color, frontShade))
      ..drawCircle(top, radius, Paint()..color = color)
      ..drawRRect(side, _edge());
  }

  static Paint _edge() => Paint()
    ..color = edgeColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  /// Returns [base] moved towards white (positive) or black (negative).
  static Color _shade(Color base, double amount) => Color.lerp(
    base,
    amount < 0 ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    amount.abs(),
  )!;
}
