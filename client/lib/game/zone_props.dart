import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/app_fonts.dart';
import 'package:client/core/sponsor.dart';
import 'package:client/core/world_palette.dart';
import 'package:client/game/diorama_art.dart';
import 'package:client/game/world_layout.dart';
import 'package:protocol/protocol.dart';

/// Everything standing on the floor of one room, drawn.
///
/// Split out of `FurnitureComponent` in Phase 9 when the world went from five
/// rooms to seven. One file per concern beats one file per layer once the file
/// stops fitting on a screen — and every one of these is recorded once into
/// the furniture picture, so the split costs nothing at runtime.
///
/// **The draw list and the collision list come from the same constants.**
/// Every rectangle and circle here is read out of [WorldLayout], which is also
/// what `WorldLayout.fixedObstacles` is built from. Furniture drawn in one
/// place and collided in another is the classic invisible wall, and it is
/// always found by a player rather than by a test.
abstract final class ZoneProps {
  /// The rounding every prop shares, so the room looks like one set.
  static const Radius corner = Radius.circular(6);

  // ---- Food Court (west arm) ----------------------------------------------
  //
  // Phase 12's rename, and new art on top of it. **Every footprint below is
  // the rectangle it always was** — the counter, the stools, the awning and
  // the cart never moved — so the Phase 9 layout tests pass unmodified, which
  // is the review of the change. Only what is painted inside them is new.

  /// Draws the food court: counter, three stall bays, menu boards, trays,
  /// stools with plates on them, the samosa cart, the awning and its bulbs.
  static void paintFoodCourt(Canvas canvas) {
    final colors = WorldPalette.of(WorldZone.foodCourt);
    final counter = rect(WorldLayout.foodCounter);

    // The shade the raised awning throws, drawn first so everything else
    // sits in it. Cast from the awning's height like every other shadow, so
    // it lands south-east of the canopy rather than straight under it.
    DioramaArt.paintBoxShadow(
      canvas,
      rect(WorldLayout.courtAwning),
      base: awningBase,
      height: awningThickness,
    );

    DioramaArt.paintBox(
      canvas,
      counter,
      height: counterHeight,
      color: _shade(colors.accent, -0.10),
      corner: corner,
    );
    // Everything on the counter stands on its top, so it is painted in a
    // canvas lifted by the counter's height: the bays, boards and trays keep
    // their own coordinates and simply ride up with the surface under them.
    canvas
      ..save()
      ..translate(0, -counterHeight * DioramaArt.lift)
      // The serving surface: a lighter inset is what turns a block into a
      // counter you can imagine putting a tray down on.
      ..drawRRect(
        RRect.fromRectAndRadius(counter.deflate(6), corner),
        Paint()..color = _shade(colors.accent, 0.24),
      );
    _paintStallBays(canvas, counter, colors);
    _paintTrays(canvas, counter, colors);
    canvas.restore();

    for (var i = 0; i < WorldLayout.courtStools.length; i++) {
      final stool = WorldLayout.courtStools[i];
      final at = Offset(stool.x, stool.y);
      DioramaArt.paintCylinder(
        canvas,
        at,
        stool.radius,
        height: stoolHeight,
        color: _shade(colors.accent, 0.10),
      );
      final seat = DioramaArt.cylinderTop(at, height: stoolHeight);
      // A plate on every other stool. Not on all four: a row of identical
      // full plates reads as a display case, and the gap is what says
      // somebody is sitting here and somebody else has not arrived yet.
      canvas.drawCircle(
        seat,
        stool.radius * 0.55,
        Paint()
          ..color = i.isEven
              ? const Color(0xFFF2ECDF)
              : _shade(colors.accent, -0.16),
      );
      if (i.isEven) {
        canvas.drawCircle(
          seat,
          stool.radius * 0.3,
          Paint()..color = const Color(0xFFD9A05B),
        );
      }
    }

    _paintSnackCart(canvas, colors);

    for (final planter in WorldLayout.planters) {
      _paintPlanter(canvas, planter.x, planter.y, planter.radius, colors);
    }
  }

  /// Draws the food court's overhead: the awning and the parasol, over the
  /// beans.
  ///
  /// Both are translucent, because both hang over places people walk. Their
  /// shadows stay in [paintFoodCourt], on the floor under the beans.
  static void paintFoodCourtOverhead(Canvas canvas) {
    final colors = WorldPalette.of(WorldZone.foodCourt);
    _paintParasol(canvas);
    _paintAwning(canvas, colors);
  }

  /// Three stall bays down the counter: a dosa tawa, a chaat counter and a
  /// samosa tray, each under its own menu board.
  ///
  /// One urn became three bays, and that is the whole of "this is a food court
  /// and not a tea stall": a court is several people selling several things,
  /// and one pot is one person selling one thing. All three sit **on** the
  /// counter, which is already solid — nothing new collides.
  static void _paintStallBays(Canvas canvas, Rect counter, ZoneColors colors) {
    const radius = WorldLayout.tawaRadius;
    for (var bay = 0; bay < 3; bay++) {
      final at = Offset(
        WorldLayout.tawaX,
        WorldLayout.tawaY + bay * WorldLayout.bayPitch,
      );
      _paintMenuBoard(canvas, counter, at.dy - radius - 21, bay, colors);

      switch (bay) {
        case 0:
          // The dosa tawa: a dark hotplate with a pale crescent on it and
          // steam coming off the top of it.
          canvas
            ..drawCircle(at, radius, Paint()..color = const Color(0xFF3A3A3A))
            ..drawCircle(
              at,
              radius * 0.86,
              Paint()..color = const Color(0xFF5C5A55),
            )
            ..drawArc(
              Rect.fromCircle(center: at, radius: radius * 0.62),
              math.pi * 0.15,
              math.pi * 1.3,
              false,
              Paint()
                ..color = const Color(0xFFE8CE9A)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 5,
            );
          _paintSteam(canvas, at.translate(0, -radius - 2));
        case 1:
          // The chaat counter: four bowls of something in a tray.
          final tray = Rect.fromCenter(
            center: at,
            width: radius * 2.2,
            height: radius * 1.5,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(tray, const Radius.circular(3)),
            Paint()..color = _shade(colors.accent, -0.30),
          );
          const fillings = [
            Color(0xFFB8452E),
            Color(0xFF5E8C3A),
            Color(0xFFE0B23C),
            Color(0xFFEDE3CF),
          ];
          for (var i = 0; i < 4; i++) {
            canvas.drawCircle(
              Offset(tray.left + tray.width * (0.2 + 0.2 * i), tray.center.dy),
              4,
              Paint()..color = fillings[i],
            );
          }
        case _:
          // The samosa tray: three triangles, which is all a samosa needs to
          // be one — the same three the cart already uses, so the court reads
          // as one set.
          final pastry = Paint()..color = const Color(0xFFD9A05B);
          for (var i = 0; i < 3; i++) {
            final tip = at.translate((i - 1) * 12, i.isEven ? -3 : 4);
            canvas.drawPath(
              Path()
                ..moveTo(tip.dx, tip.dy - 7)
                ..lineTo(tip.dx + 7, tip.dy + 5)
                ..lineTo(tip.dx - 7, tip.dy + 5)
                ..close(),
              pastry,
            );
          }
          _paintSteam(canvas, at.translate(0, -radius - 2));
      }
    }
  }

  /// A little board hung over one bay.
  ///
  /// Three coloured ticks rather than words. A menu legible at this camera
  /// distance would need a `Paragraph` per bay, and three lines nobody can
  /// read is exactly what a menu board looks like from across a yard.
  static void _paintMenuBoard(
    Canvas canvas,
    Rect counter,
    double y,
    int bay,
    ZoneColors colors,
  ) {
    final board = Rect.fromLTWH(counter.left + 4, y, counter.width - 8, 15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(board, const Radius.circular(2)),
      Paint()..color = _shade(colors.accent, -0.46),
    );
    final chalk = Paint()
      ..color = const Color(0x99F6EAD8)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var line = 0; line < 3; line++) {
      final width = board.width * (0.34 + 0.16 * ((bay + line) % 3));
      canvas.drawLine(
        Offset(board.left + 5, board.top + 4 + line * 4),
        Offset(board.left + 5 + width, board.top + 4 + line * 4),
        chalk,
      );
    }
  }

  /// Trays stacked down the front edge of the counter, waiting to be taken.
  ///
  /// The food court's answer to the row of glasses that used to be here, in
  /// the same place and at the same spacing.
  static void _paintTrays(Canvas canvas, Rect counter, ZoneColors colors) {
    for (var y = counter.top + 30; y < counter.bottom - 20; y += 34) {
      final tray = Rect.fromCenter(
        center: Offset(counter.right - 18, y),
        width: 16,
        height: 12,
      );
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(tray, const Radius.circular(2)),
          Paint()..color = _shade(colors.accent, -0.34),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(tray.deflate(2), const Radius.circular(1.5)),
          Paint()..color = const Color(0xFFF2ECDF),
        );
    }
  }

  /// Two wisps off something hot.
  static void _paintSteam(Canvas canvas, Offset from) {
    final wisp = Paint()
      ..color = const Color(0x4DFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (final dx in [-5.0, 5.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(from.dx + dx, from.dy)
          ..quadraticBezierTo(
            from.dx + dx - 5,
            from.dy - 7,
            from.dx + dx,
            from.dy - 14,
          ),
        wisp,
      );
    }
  }

  /// The samosa cart: a box on wheels, the samosas on top, and a parasol on
  /// a pole above it.
  ///
  /// The parasol is drawn but not collided, like the awning: it is overhead,
  /// and the pole stands on the cart, which is already solid. Translucent,
  /// as it always was, because it is over the walk in from the atrium and
  /// nothing over a walkway may hide a bean.
  static void _paintSnackCart(Canvas canvas, ZoneColors colors) {
    final cart = rect(WorldLayout.snackCart);

    // The parasol's shadow first, on the ground: it is cast from the canopy's
    // height, so it lands well south-east of the cart it shades.
    DioramaArt.paintCylinderShadow(
      canvas,
      cart.center,
      parasolRadius,
      base: parasolHeight,
      height: 0,
    );
    DioramaArt.paintBox(
      canvas,
      cart,
      base: cartClearance,
      height: cartHeight,
      color: _shade(colors.accent, 0.06),
      corner: corner,
    );

    // Two wheels under the front edge, in the gap the clearance leaves. What
    // makes a raised box read as a cart rather than as a floating one.
    final front = DioramaArt.frontFace(
      cart,
      base: cartClearance,
      height: cartHeight,
    );
    for (final x in [front.left + 18, front.right - 18]) {
      canvas.drawCircle(
        Offset(x, front.bottom),
        5,
        Paint()..color = const Color(0xFF3A2A20),
      );
    }

    // Samosas: three triangles, which is all a samosa needs to be one.
    final top = DioramaArt.topFace(
      cart,
      base: cartClearance,
      height: cartHeight,
    );
    final pastry = Paint()..color = const Color(0xFFD9A05B);
    for (var i = 0; i < 3; i++) {
      final at = Offset(top.left + 26 + i * 30, top.center.dy + 4);
      canvas.drawPath(
        Path()
          ..moveTo(at.dx, at.dy - 9)
          ..lineTo(at.dx + 10, at.dy + 7)
          ..lineTo(at.dx - 10, at.dy + 7)
          ..close(),
        pastry,
      );
    }

    // The pole. Its top end is under the parasol, which is in the overhead
    // picture — see [_paintParasol].
    canvas.drawLine(
      top.center,
      DioramaArt.cylinderTop(cart.center, height: parasolHeight),
      Paint()
        ..color = const Color(0xFF6B4B3A)
        ..strokeWidth = 3,
    );
  }

  /// The parasol over the samosa cart, at the top of its pole.
  static void _paintParasol(Canvas canvas) {
    final canopy = DioramaArt.cylinderTop(
      rect(WorldLayout.snackCart).center,
      height: parasolHeight,
    );
    canvas
      ..drawCircle(
        canopy,
        parasolRadius,
        Paint()..color = const Color(0x33F4C542),
      )
      ..drawCircle(
        canopy,
        parasolRadius,
        Paint()
          ..color = const Color(0x80D89A16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
  }

  /// The striped awning over the stalls, up on its own height.
  ///
  /// Hung from the west wall rather than stood on poles: a pole along its
  /// east edge would be a drawn thing in the walkway past the stools that a
  /// player walks straight through, and the only thing worse than an
  /// invisible wall is a visible non-wall. Still translucent, for the same
  /// reason the parasol is.
  static void _paintAwning(Canvas canvas, ZoneColors colors) {
    final footprint = rect(WorldLayout.courtAwning);
    final awning = DioramaArt.topFace(
      footprint,
      base: awningBase,
      height: awningThickness,
    );
    final valance = DioramaArt.frontFace(
      footprint,
      base: awningBase,
      height: awningThickness,
    );
    final shape = RRect.fromRectAndRadius(awning, const Radius.circular(14));
    // The valance is only the strip under the canvas, not a body under the
    // whole of it the way `DioramaArt.paintBox` paints one: the canvas is
    // translucent, so a body under it would show through as a dark awning.
    // Pulled in from the ends, where the rounded corners curve away from it.
    canvas
      ..drawRect(
        Rect.fromLTRB(
          valance.left + 10,
          valance.top,
          valance.right - 10,
          valance.bottom,
        ),
        Paint()..color = _shade(colors.accent, -0.24).withValues(alpha: 0.7),
      )
      ..save()
      ..clipRRect(shape);
    // Striped canvas. Alternating bands are the single cheapest thing that
    // says "market stall" rather than "flat panel".
    var index = 0;
    for (var y = awning.top; y < awning.bottom; y += 26) {
      canvas.drawRect(
        Rect.fromLTWH(awning.left, y, awning.width, 26),
        Paint()
          ..color = index.isEven
              ? const Color(0x40F6EAD8)
              : _shade(colors.accent, -0.05).withValues(alpha: 0.32),
      );
      index++;
    }
    canvas
      ..restore()
      ..drawRRect(
        shape,
        Paint()
          ..color = _shade(colors.accent, -0.24).withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

    // The bulbs strung along the front edge of the awning, up with it.
    for (var y = awning.top + 22; y < awning.bottom; y += 42) {
      final at = Offset(awning.right, y);
      canvas
        ..drawCircle(at, 11, Paint()..color = const Color(0x33FFD08A))
        ..drawCircle(at, 4, Paint()..color = const Color(0xFFFFDCA0));
    }
  }

  /// How tall the food counter is, in world units.
  static const double counterHeight = 20;

  /// How tall a stool is, in world units.
  static const double stoolHeight = 12;

  /// How far the snack cart's body stands off the floor on its wheels, in
  /// world units.
  static const double cartClearance = 6;

  /// How tall the snack cart's body is, in world units.
  static const double cartHeight = 18;

  /// How high the parasol's canopy is over the floor, in world units.
  ///
  /// Kept low enough that the lifted canopy stays inside the food court
  /// rather than climbing over its north wall.
  static const double parasolHeight = 40;

  /// How wide the parasol is, in world units.
  static const double parasolRadius = 44;

  /// How high the awning hangs over the floor, in world units.
  ///
  /// Well over a bean's head, which is what makes it something you walk
  /// under rather than into.
  static const double awningBase = 44;

  /// How thick the awning's canvas is, in world units: its valance.
  static const double awningThickness = 3;

  static void _paintPlanter(
    Canvas canvas,
    double x,
    double y,
    double radius,
    ZoneColors colors,
  ) {
    final at = Offset(x, y);
    // One shadow for pot and shrub together, the full height of both: the
    // shrub is what sticks up highest, so it is what the light catches.
    DioramaArt.paintCylinderShadow(
      canvas,
      at,
      radius,
      height: planterHeight + bushHeight,
    );
    DioramaArt.paintCylinder(
      canvas,
      at,
      radius,
      height: planterHeight,
      color: _shade(colors.accent, -0.06),
      shadow: false,
    );
    // Foliage: five overlapping blobs on a fixed lattice, which reads as a
    // shrub from three metres up and costs five circles. The ring sits just
    // above the soil and the crown at the top of the shrub, so the shrub has
    // a height of its own rather than being a sticker on the pot.
    final soil = DioramaArt.cylinderTop(at, height: planterHeight + 2);
    final leaf = Paint()..color = const Color(0xFF4F8F45);
    for (var i = 0; i < 5; i++) {
      final angle = i * 2 * math.pi / 5;
      canvas.drawCircle(
        soil.translate(
          math.cos(angle) * radius * 0.38,
          math.sin(angle) * radius * 0.38,
        ),
        radius * 0.46,
        leaf,
      );
    }
    canvas.drawCircle(
      DioramaArt.cylinderTop(at, height: planterHeight + bushHeight),
      radius * 0.40,
      Paint()..color = const Color(0xFF62A855),
    );
  }

  /// How tall a planter's pot is, in world units.
  static const double planterHeight = 18;

  /// How far a planter's shrub stands above its pot, in world units.
  static const double bushHeight = 10;

  // ---- Conference hall (north arm) ----------------------------------------

  /// How tall the stage platform is, in world units.
  ///
  /// Height is paint only — see `DioramaArt`. The stage still collides as
  /// the same flat rectangle it always did; this is how far its deck is
  /// lifted up the screen and how long a shadow it throws.
  static const double stageHeight = 12;

  /// How tall a seat row's cushion is, in world units.
  static const double seatHeight = 8;

  /// How tall a seat row's backrest is, in world units.
  static const double backrestHeight = 18;

  /// How deep a backrest is, north to south, in world units.
  static const double backrestDepth = 5;

  /// How tall the shadow cast by something standing on the stage is, in
  /// world units.
  ///
  /// Not the whole height of the thing. The screen is about ninety units of
  /// upright panel, and a ninety-unit shadow off it would lie across the
  /// whole deck: the hall is the one dark room, kept dark so that the lit
  /// stage is the brightest thing in it, and a stage in shadow defeats that.
  /// The stage lights fill the long shadows in; a short contact shadow, in
  /// the same direction as every other shadow, is what stays.
  static const double stageContactShadow = 10;

  /// Where the stage screen's glass is drawn: [WorldLayout.stageScreen],
  /// standing on the stage and so lifted with its deck.
  ///
  /// Public because two things draw here and they must agree: the screen's
  /// frame in this picture, and `StageScreenComponent`, which draws the
  /// changing words live on top of it.
  static Rect get stageScreenFace =>
      DioramaArt.topFace(rect(WorldLayout.stageScreen), height: stageHeight);

  /// The backrest standing along the south edge of the seat row [seat].
  ///
  /// The audience faces north, at the stage, so the back of every seat is
  /// its south edge — and it is **inside** the row's footprint, so the taller
  /// half of the row collides exactly where the shorter half always did.
  static Rect backrest(Rect seat) => Rect.fromLTRB(
    seat.left,
    seat.bottom - backrestDepth,
    seat.right,
    seat.bottom,
  );

  /// Draws the stage: light spill, deck, apron, backdrop flats, screen,
  /// speakers, and the seat rows facing it.
  ///
  /// Every part of this sits **inside** the stage's existing footprint, which
  /// is already one solid rectangle in `WorldLayout.fixedObstacles`. Detail
  /// that stayed inside the collision box it was always in is detail that
  /// cannot possibly have introduced an invisible wall.
  static void paintHall(Canvas canvas) {
    final colors = WorldPalette.of(WorldZone.hall);
    final stage = rect(WorldLayout.stage);

    // The light the stage throws onto the floor in front of it. Two soft
    // wedges rather than a blur: a `MaskFilter` here would be a real raster
    // cost across a quarter of the room.
    for (final at in [stage.left + 70, stage.right - 70]) {
      canvas.drawPath(
        Path()
          ..moveTo(at, stage.bottom)
          ..lineTo(at - 96, stage.bottom + 190)
          ..lineTo(at + 96, stage.bottom + 190)
          ..close(),
        Paint()..color = const Color(0x1AFFE9B0),
      );
    }

    DioramaArt.paintBox(
      canvas,
      stage,
      height: stageHeight,
      color: _shade(colors.accent, -0.28),
      corner: corner,
    );
    // Everything below stands on the deck, so the deck is its floor.
    final deck = DioramaArt.topFace(stage, height: stageHeight);

    // The apron: the lip of the stage a speaker stands on, and the one edge
    // of this prop the audience actually sees.
    canvas
      ..drawRect(
        Rect.fromLTRB(deck.left, deck.bottom - 22, deck.right, deck.bottom),
        Paint()..color = _shade(colors.accent, 0.16),
      )
      ..drawRect(
        Rect.fromLTRB(
          deck.left,
          deck.bottom - 22,
          deck.right,
          deck.bottom - 18,
        ),
        Paint()..color = const Color(0x66FFE9B0),
      );

    // Upright panels, each given as the face the audience sees, back to
    // front so a nearer one is painted over a further one: the two backdrop
    // flats, then the screen in its frame, then the speakers.
    final flats = [
      _upright(
        Rect.fromLTRB(
          deck.left + 8,
          deck.top + 8,
          deck.left + 44,
          deck.bottom - 30,
        ),
      ),
      _upright(
        Rect.fromLTRB(
          deck.right - 44,
          deck.top + 8,
          deck.right - 8,
          deck.bottom - 30,
        ),
      ),
    ];
    final frame = _upright(stageScreenFace.inflate(4));
    final speakers = [
      for (final x in [deck.left + 6, deck.right - 34])
        _upright(Rect.fromLTWH(x, deck.bottom - 62, 28, 40), depth: 10),
    ];

    // Their shadows fall on the deck, so they are clipped to it: a shadow
    // hanging off the edge of a stage into thin air is the one shadow that
    // makes the whole thing read as a sticker.
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(deck, corner));
    for (final piece in [...flats, frame, ...speakers]) {
      DioramaArt.paintBoxShadow(
        canvas,
        piece.footprint,
        height: math.min(piece.height, stageContactShadow),
      );
    }
    canvas.restore();

    for (final flat in flats) {
      DioramaArt.paintBox(
        canvas,
        flat.footprint,
        height: flat.height,
        color: _shade(colors.accent, 0.04),
        front: _shade(colors.accent, -0.10),
        corner: const Radius.circular(3),
        shadow: false,
      );
    }

    DioramaArt.paintBox(
      canvas,
      frame.footprint,
      height: frame.height,
      color: _speakerFace,
      front: _speakerBody,
      corner: const Radius.circular(3),
      shadow: false,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(stageScreenFace, corner),
        Paint()..color = _boothScreen,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          stageScreenFace.deflate(5),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0x38FFD9A0),
      );

    for (final speaker in speakers) {
      DioramaArt.paintBox(
        canvas,
        speaker.footprint,
        height: speaker.height,
        color: _speakerFace,
        front: _speakerBody,
        corner: const Radius.circular(3),
        shadow: false,
      );
      final face = DioramaArt.frontFace(
        speaker.footprint,
        height: speaker.height,
      );
      canvas
        ..drawCircle(
          face.center.translate(0, -6),
          7,
          Paint()..color = _speakerFace,
        )
        ..drawCircle(
          face.center.translate(0, 11),
          4,
          Paint()..color = _speakerFace,
        );
    }

    // The seating, unchanged in footprint: a cushion, and a taller backrest
    // along its south edge so a row reads as seats rather than as a bar of
    // colour. Solid now rather than translucent — a face you can see the
    // carpet through stops reading as a face — in the colour the translucent
    // seat used to come out as on this floor.
    final cushion = Color.alphaBlend(
      colors.accent.withValues(alpha: 0.55),
      colors.floor,
    );
    final rail = Color.alphaBlend(
      colors.accent.withValues(alpha: 0.85),
      colors.floor,
    );
    for (final row in WorldLayout.seatRows) {
      final at = rect(row.rect);
      DioramaArt.paintBox(
        canvas,
        at,
        height: seatHeight,
        color: cushion,
        corner: corner,
      );
      final top = DioramaArt.topFace(at, height: seatHeight);
      for (var x = top.left + 29; x < top.right - 10; x += 29) {
        canvas.drawLine(
          Offset(x, top.top + 2),
          Offset(x, top.bottom - 2),
          Paint()
            ..color = const Color(0x3D0B1420)
            ..strokeWidth = 1.6,
        );
      }
      DioramaArt.paintBox(
        canvas,
        backrest(at),
        height: backrestHeight,
        color: rail,
        corner: const Radius.circular(2),
      );
    }
  }

  static const Color _speakerBody = Color(0xFF16202C);
  static const Color _speakerFace = Color(0xFF2C3A4A);

  /// An upright panel whose south face is [face]: its footprint, a [depth]
  /// deep strip along the face's bottom edge, and the height that makes
  /// `DioramaArt.frontFace` come out as exactly [face].
  ///
  /// Given by its face rather than by its footprint because the face is the
  /// thing with a fixed place: the live screen draws its words at
  /// [stageScreenFace], and the frame has to be where the words are.
  static ({Rect footprint, double height}) _upright(
    Rect face, {
    double depth = 6,
  }) => (
    footprint: Rect.fromLTRB(
      face.left,
      face.bottom - depth,
      face.right,
      face.bottom,
    ),
    height: face.height / DioramaArt.lift,
  );

  // ---- Hanging banners ----------------------------------------------------

  /// Hangs a banner on every outer wall of the building.
  ///
  /// Placed **inside the 24-unit outer inset**, which is the strip no bean can
  /// ever stand in. A banner hung across a walkway would be a drawn thing a
  /// player walks straight through, and the only thing worse than an invisible
  /// wall is a visible non-wall.
  static void paintBanners(Canvas canvas) {
    const banners = <({double x, double y, bool vertical, WorldZone zone})>[
      (x: 700, y: 4, vertical: false, zone: WorldZone.hall),
      (x: 1180, y: 4, vertical: false, zone: WorldZone.codeLab),
      (x: 1400, y: 4, vertical: false, zone: WorldZone.codeLab),
      (x: 1580, y: 470, vertical: true, zone: WorldZone.sponsorRow),
      (x: 1580, y: 640, vertical: true, zone: WorldZone.sponsorRow),
      (x: 4, y: 470, vertical: true, zone: WorldZone.foodCourt),
      (x: 4, y: 900, vertical: true, zone: WorldZone.garden),
      (x: 700, y: 1180, vertical: false, zone: WorldZone.lounge),
    ];

    for (final banner in banners) {
      final accent = WorldPalette.of(banner.zone).accent;
      final body = banner.vertical
          ? Rect.fromLTWH(banner.x, banner.y, 16, 190)
          : Rect.fromLTWH(banner.x, banner.y, 190, 16);
      canvas
        ..drawRect(
          body.translate(3, 3),
          Paint()..color = const Color(0x2E000000),
        )
        ..drawRect(body, Paint()..color = _shade(accent, 0.10))
        // A stripe down the middle, so a banner is a banner and not a stick.
        ..drawRect(body.deflate(4.5), Paint()..color = _shade(accent, -0.24));
    }
  }

  // ---- Code Lab (north-east) ----------------------------------------------

  /// Draws the lab: projector screen, whiteboard, desk rows, cable trays.
  ///
  /// [boardMessage] is the one sentence in this room that comes from config
  /// rather than from a constant, and it goes on the **projector**, not the
  /// whiteboard: 232x52 against 138x52, and a whiteboard is a place for
  /// doodles anyway. It is painted into the recording with everything else,
  /// because config is read before the game is built — a line that changes
  /// without a rebuild does not have to change without a *reload*.
  static void paintCodeLab(Canvas canvas, [String boardMessage = '']) {
    final colors = WorldPalette.of(WorldZone.codeLab);

    // Cable trays first: they run *under* the desks, along the floor.
    final tray = Paint()
      ..color = _shade(colors.accent, -0.10).withValues(alpha: 0.28)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    for (final row in const [179.0, 263.0, 347.0]) {
      canvas.drawLine(
        Offset(1040, row + 28),
        Offset(1544, row + 28),
        tray,
      );
    }
    canvas.drawLine(
      const Offset(WorldLayout.labAisleX, 110),
      const Offset(WorldLayout.labAisleX, 380),
      tray,
    );

    _paintScreen(canvas, rect(WorldLayout.labScreen), colors, boardMessage);
    _paintWhiteboard(canvas, rect(WorldLayout.whiteboard), colors);

    for (final desk in WorldLayout.labDesks) {
      final footprint = rect(desk.rect);
      DioramaArt.paintBox(
        canvas,
        footprint,
        height: deskHeight,
        color: _shade(colors.accent, 0.52),
        corner: corner,
      );
      final top = DioramaArt.topFace(footprint, height: deskHeight);
      // The back lip of the desk, where the cables go over.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(top.left, top.top, top.right, top.top + 7),
          corner,
        ),
        Paint()..color = _shade(colors.accent, 0.18),
      );
      // Monitors standing along the desk, each facing the person in the
      // south of it with a lit screen. Four small uprights per desk is what
      // turns a table into a lab.
      for (var x = top.left + 26; x < top.right - 18; x += 48) {
        final monitor = _upright(
          Rect.fromLTWH(x, top.top + 11, 30, 17),
          depth: 4,
        );
        DioramaArt.paintBoxShadow(
          canvas,
          monitor.footprint,
          height: deskContactShadow,
        );
        DioramaArt.paintBox(
          canvas,
          monitor.footprint,
          height: monitor.height,
          color: const Color(0xFF2B3440),
          front: const Color(0xFF16222E),
          corner: const Radius.circular(2),
          shadow: false,
        );
        final screen = DioramaArt.frontFace(
          monitor.footprint,
          height: monitor.height,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            screen.deflate(2.5),
            const Radius.circular(1.5),
          ),
          Paint()..color = const Color(0xFF43C8E0),
        );
      }
    }
  }

  /// How tall a lab desk is, in world units.
  static const double deskHeight = 16;

  /// How tall the shadow a monitor throws across its desk is, in world
  /// units: a contact shadow, for the reason the stage's are.
  static const double deskContactShadow = 6;

  static void _paintScreen(
    Canvas canvas,
    Rect at,
    ZoneColors colors,
    String message,
  ) {
    _paintWallPanel(canvas, at, _shade(colors.accent, -0.42), colors);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(at.deflate(7), const Radius.circular(3)),
        Paint()..color = const Color(0xFF0E1A24),
      )
      // The projected image: a wash the words are laid over.
      ..drawRRect(
        RRect.fromRectAndRadius(at.deflate(7), const Radius.circular(3)),
        Paint()..color = const Color(0x2E5FD8F0),
      );

    // Nothing worth projecting: keep the Phase 9 "lines of code", which is
    // what a slide looks like when nobody has written one.
    if (message.trim().isEmpty) {
      final line = Paint()
        ..color = const Color(0x8C7FE4F5)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(
          Offset(at.left + 22, at.center.dy - 6),
          Offset(at.right - 70, at.center.dy - 6),
          line,
        )
        ..drawLine(
          Offset(at.left + 22, at.center.dy + 6),
          Offset(at.right - 120, at.center.dy + 6),
          line,
        );
      return;
    }

    final slide = boardParagraph(message, at.width - _boardInset * 2);
    // Clipped to the lit part of the screen, so however long a line an
    // organiser pastes in, it cannot paint across the room. The paragraph is
    // already ellipsized at two lines; this is the belt to that's braces.
    canvas
      ..save()
      ..clipRRect(
        RRect.fromRectAndRadius(at.deflate(7), const Radius.circular(3)),
      )
      ..drawParagraph(
        slide,
        Offset(at.left + _boardInset, at.center.dy - slide.height / 2),
      )
      ..restore();
  }

  /// How far the projected line sits in from the screen's edge, in world
  /// units.
  static const double _boardInset = 16;

  /// The projector's line, laid out once and cached.
  ///
  /// A [Paragraph] bakes its text, its colour and its layout in, so building
  /// one per frame would be a text layout sixty times a second to draw a
  /// sentence that changes when somebody edits a config file. This one is
  /// built at *record* time — the furniture is a display list — so it is laid
  /// out once per session, and the cache is what makes rebuilding that list
  /// cheap if it ever happens twice.
  ///
  /// Public so a test can assert on the size it lays out to.
  static Paragraph boardParagraph(String message, double width) {
    final cached = _boardCache;
    if (cached != null && cached.message == message && cached.width == width) {
      return cached.paragraph;
    }
    final builder =
        ParagraphBuilder(
            ParagraphStyle(
              fontFamily: AppFonts.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              textAlign: TextAlign.center,
              // Two lines and then an ellipsis. A sentence that overflows is
              // a sentence painted over the desks behind the screen.
              maxLines: 2,
              ellipsis: '…',
            ),
          )
          ..pushStyle(
            TextStyle(color: const Color(0xFFCFF3FF), letterSpacing: 0.4),
          )
          ..addText(message.trim());
    final paragraph = builder.build()
      ..layout(ParagraphConstraints(width: width));
    _boardCache = (message: message, width: width, paragraph: paragraph);
    return paragraph;
  }

  static ({String message, double width, Paragraph paragraph})? _boardCache;

  /// A board standing against the lab's north wall, whose face is [face].
  ///
  /// The face is exactly the rectangle it always was, so the projected line
  /// and the scribbles land where they always did; the height shows as a
  /// thin top edge above it and a shadow on the floor in front of it. Both
  /// boards are obstacles, and the footprint `_upright` gives them is a strip
  /// inside the old one, so nothing new collides.
  static void _paintWallPanel(
    Canvas canvas,
    Rect face,
    Color frame,
    ZoneColors colors,
  ) {
    final panel = _upright(face);
    DioramaArt.paintBox(
      canvas,
      panel.footprint,
      height: panel.height,
      color: _shade(colors.accent, -0.12),
      front: frame,
      corner: corner,
    );
  }

  static void _paintWhiteboard(Canvas canvas, Rect at, ZoneColors colors) {
    _paintWallPanel(canvas, at, _shade(colors.accent, -0.30), colors);
    canvas.drawRRect(
      RRect.fromRectAndRadius(at.deflate(6), const Radius.circular(3)),
      Paint()..color = const Color(0xFFF3F7FA),
    );
    // Scribbles. Two colours and four strokes: anything more legible than
    // this would be a slide, and a slide nobody can read is a smudge.
    final ink = Paint()
      ..color = const Color(0xFF2B6EA8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final marker = Paint()
      ..color = const Color(0xFFD2603E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        Offset(at.left + 18, at.top + 20),
        Offset(at.left + 74, at.top + 20),
        ink,
      )
      ..drawLine(
        Offset(at.left + 18, at.top + 31),
        Offset(at.left + 56, at.top + 31),
        ink,
      )
      ..drawCircle(Offset(at.right - 34, at.center.dy), 11, marker)
      ..drawLine(
        Offset(at.right - 34, at.top + 34),
        Offset(at.right - 34, at.bottom - 14),
        marker,
      );
  }

  // ---- Garden Deck (south-west) -------------------------------------------

  /// Draws the garden: lawn props, trees, benches, fountain, stepped deck.
  static void paintGarden(Canvas canvas) {
    final colors = WorldPalette.of(WorldZone.garden);

    _paintSteppedDeck(canvas, colors);
    _paintFountain(canvas, colors);

    for (final bench in WorldLayout.gardenBenches) {
      _paintBench(canvas, rect(bench.rect));
    }

    // Trunks and shadows only. The canopies are overhead — see
    // [paintGardenOverhead].
    for (final tree in WorldLayout.gardenTrees) {
      _paintTrunk(canvas, tree.x, tree.y, tree.radius);
    }
  }

  /// Draws the garden's overhead: the tree canopies, over the beans.
  ///
  /// Opaque, unlike the food court's: they stand over lawn rather than over
  /// a walkway, and a bean under a tree is meant to be under it. Its name
  /// is still drawn above.
  static void paintGardenOverhead(Canvas canvas) {
    for (final tree in WorldLayout.gardenTrees) {
      _paintCanopy(canvas, tree.x, tree.y, tree.radius);
    }
  }

  /// How high the deck's platform stands, in world units — **in the paint
  /// only**, and less than that: see [_paintSteppedDeck].
  static const double deckHeight = 15;

  /// How high the tread or platform [step] stands, counting the treads from
  /// the west (0) and the platform as step [WorldLayout.deckTreads].
  ///
  /// Even steps from the lawn up to [deckHeight], so every riser is the
  /// same size.
  static double deckStepHeight(int step) =>
      deckHeight * (step + 1) / (WorldLayout.deckTreads + 1);

  /// The footprint of tread or platform [step]: a north-to-south strip of
  /// the deck, the treads west of [WorldLayout.deckPlatformX] and the
  /// platform east of it.
  static Rect deckStep(int step) {
    final deck = rect(WorldLayout.gardenDeck);
    const treads = WorldLayout.deckTreads;
    if (step == treads) {
      return Rect.fromLTRB(
        WorldLayout.deckPlatformX,
        deck.top,
        deck.right,
        deck.bottom,
      );
    }
    final width = (WorldLayout.deckPlatformX - deck.left) / treads;
    final left = deck.left + step * width;
    return Rect.fromLTRB(left, deck.top, left + width, deck.bottom);
  }

  /// Draws the stepped deck: **fake depth on flat, walkable ground.**
  ///
  /// Four painted treads climbing east to a platform that looks out over the
  /// pool. Nothing here is an obstacle — see `WorldLayout.gardenDeck`.
  ///
  /// Since Phase 16 the steps have heights, but **their tops are not
  /// lifted.** Beans are never lifted, so a bean walking up a lifted deck
  /// would be drawn inside its front face. Instead each step's south face is
  /// painted inside its own footprint, rising east like a staircase seen
  /// from the side, and the deck casts the shadow its heights would: the
  /// look of height without moving anything a bean stands on.
  static void _paintSteppedDeck(Canvas canvas, ZoneColors colors) {
    const steps = WorldLayout.deckTreads + 1;

    // One shadow for the whole flight. The steps are added to one path so
    // where their shadows overlap the floor is darkened once, not twice.
    final shadow = Path();
    for (var i = 0; i < steps; i++) {
      shadow.addPolygon(
        DioramaArt.boxShadow(deckStep(i), height: deckStepHeight(i)),
        true,
      );
    }
    canvas.drawPath(shadow, Paint()..color = DioramaArt.shadowColor);

    const timber = Color(0xFFB2854E);
    for (var i = 0; i < steps; i++) {
      final step = deckStep(i);
      // Not lifted: the face of a step on the floor already ends at the
      // footprint's south edge, so it hangs inside the footprint.
      final face = DioramaArt.frontFace(step, height: deckStepHeight(i));
      // Each step a shade lighter than the last, the platform brightest of
      // all because it is highest: the eye reads a brightness ramp as a
      // climb.
      final top = i < WorldLayout.deckTreads
          ? _shade(timber, -0.20 + i * 0.055)
          : _shade(timber, 0.10);
      canvas
        ..drawRect(step, Paint()..color = top)
        // The riser, on the western face of each step.
        ..drawRect(
          Rect.fromLTRB(step.left, step.top, step.left + 5, face.top),
          Paint()..color = const Color(0x59241505),
        )
        ..drawRect(
          face,
          Paint()..color = _shade(top, DioramaArt.frontShade),
        )
        ..drawRect(
          face,
          Paint()
            ..color = DioramaArt.edgeColor
            ..style = PaintingStyle.stroke,
        );
    }

    final platform = deckStep(WorldLayout.deckTreads);
    // Where the platform's top ends and its south face begins.
    final edge = platform.bottom - deckHeight * DioramaArt.lift;
    final plank = Paint()
      ..color = const Color(0x40241505)
      ..strokeWidth = 1.6;
    for (var y = platform.top + 18; y < edge; y += 18) {
      canvas.drawLine(
        Offset(platform.left, y),
        Offset(platform.right, y),
        plank,
      );
    }

    // A railing along the southern edge only. Not along the eastern one: that
    // side is the open walkway into the lounge, and a drawn railing a player
    // can walk straight through is worse than no railing at all.
    final rail = Paint()
      ..color = const Color(0xFF7A5228)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(platform.left + 4, edge - 3),
      Offset(platform.right - 4, edge - 3),
      rail,
    );
    for (var x = platform.left + 10; x < platform.right; x += 34) {
      canvas.drawLine(Offset(x, edge - 3), Offset(x, edge - 20), rail);
    }
  }

  /// How tall the fountain's basin wall is, in world units.
  static const double fountainBasinHeight = 10;

  /// How far the fountain's water sits below the top of its wall, in world
  /// units.
  static const double fountainWaterDrop = 3;

  /// How thick the fountain's wall is, in world units: the water's radius
  /// is the basin's minus this.
  static const double fountainWall = 7;

  /// The centre of the fountain's water surface: inside the basin, a little
  /// below its rim.
  ///
  /// Public because the water is what anything drawn on the fountain later
  /// has to land on.
  static Offset get fountainWater => DioramaArt.cylinderTop(
    Offset(WorldLayout.fountain.x, WorldLayout.fountain.y),
    height: fountainBasinHeight - fountainWaterDrop,
  );

  /// The fountain: a stone basin standing on its footprint, and water sunk
  /// inside its rim.
  ///
  /// The water is lower than the rim it sits in, so its circle is drawn
  /// slightly south of the rim's opening and clipped to it. What that
  /// leaves uncovered is a thin crescent of the inside wall along the north,
  /// in shade, the same cue that makes the pool a hole.
  static void _paintFountain(Canvas canvas, ZoneColors colors) {
    final centre = Offset(WorldLayout.fountain.x, WorldLayout.fountain.y);
    final radius = WorldLayout.fountain.radius;
    final stone = _shade(colors.accent, 0.30);
    DioramaArt.paintCylinder(
      canvas,
      centre,
      radius,
      height: fountainBasinHeight,
      color: stone,
    );

    final rim = DioramaArt.cylinderTop(centre, height: fountainBasinHeight);
    final water = fountainWater;
    final inner = radius - fountainWall;
    canvas
      ..save()
      ..clipPath(Path()..addOval(Rect.fromCircle(center: rim, radius: inner)))
      ..drawCircle(rim, inner, Paint()..color = _shade(stone, -0.30))
      ..drawCircle(water, inner, Paint()..color = const Color(0xFF57BEDA))
      ..drawCircle(
        water,
        inner,
        Paint()
          ..color = const Color(0x40FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      )
      // The spout, and the rings it makes. Static, because the fountain is in
      // the picture — a moving one would need its own live component, and one
      // animated water feature in this world is enough.
      ..drawCircle(water, 8, Paint()..color = const Color(0xFFDFF6FF))
      ..drawCircle(
        water,
        radius * 0.55,
        Paint()
          ..color = const Color(0x59DFF6FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      )
      ..restore();
  }

  /// How tall a bench's seat is, in world units.
  static const double benchSeatHeight = 8;

  /// How tall a bench's backrest is, in world units.
  static const double benchBackHeight = 18;

  /// How deep a bench's backrest is, in world units.
  static const double benchBackDepth = 5;

  /// The backrest of the bench standing on [bench]: a strip along whichever
  /// long edge is further from the fountain, so whoever sits there faces it.
  ///
  /// Inside the footprint, for the same reason as a seat row's [backrest]:
  /// the taller part collides exactly where the flat bench always did.
  static Rect benchBack(Rect bench) => bench.center.dy > WorldLayout.fountain.y
      ? Rect.fromLTRB(
          bench.left,
          bench.bottom - benchBackDepth,
          bench.right,
          bench.bottom,
        )
      : Rect.fromLTRB(
          bench.left,
          bench.top,
          bench.right,
          bench.top + benchBackDepth,
        );

  /// A bench: a slatted seat and a backrest, each standing on its own part
  /// of the footprint.
  ///
  /// The northern piece is painted first, so the southern one's top covers
  /// the foot of it the way the nearer half of a real bench would.
  static void _paintBench(Canvas canvas, Rect at) {
    final back = benchBack(at);
    final seat = back.top == at.top
        ? Rect.fromLTRB(at.left, back.bottom, at.right, at.bottom)
        : Rect.fromLTRB(at.left, at.top, at.right, back.top);

    // One shadow for both pieces, so where they overlap is darkened once.
    canvas.drawPath(
      Path()
        ..addPolygon(
          DioramaArt.boxShadow(seat, height: benchSeatHeight),
          true,
        )
        ..addPolygon(DioramaArt.boxShadow(back, height: benchBackHeight), true),
      Paint()..color = DioramaArt.shadowColor,
    );

    void paintBack() => DioramaArt.paintBox(
      canvas,
      back,
      height: benchBackHeight,
      color: const Color(0xFF9C6B3C),
      corner: const Radius.circular(2),
      shadow: false,
    );
    void paintSeat() {
      DioramaArt.paintBox(
        canvas,
        seat,
        height: benchSeatHeight,
        color: const Color(0xFFB58351),
        corner: const Radius.circular(3),
        shadow: false,
      );
      // Two gaps between the slats, along the bench.
      final top = DioramaArt.topFace(seat, height: benchSeatHeight);
      final gap = Paint()
        ..color = const Color(0x40241505)
        ..strokeWidth = 1.2;
      for (final t in const [1 / 3, 2 / 3]) {
        final y = top.top + top.height * t;
        canvas.drawLine(
          Offset(top.left + 2, y),
          Offset(top.right - 2, y),
          gap,
        );
      }
    }

    if (back.top == at.top) {
      paintBack();
      paintSeat();
    } else {
      paintSeat();
      paintBack();
    }
  }

  /// How tall a tree's trunk stands before the leaves begin, in world units.
  static const double treeCrownBase = 20;

  /// How tall a tree stands to the top of its leaves, in world units.
  static const double treeCrownTop = 32;

  /// How wide a tree's canopy is for its trunk [radius].
  static double treeCanopy(double radius) => radius * 2.6;

  /// A tree's trunk standing on its footprint, and the shadow of the canopy
  /// it holds up.
  ///
  /// The canopy's shadow is cast from up there, so it lies off to the
  /// south-east of the trunk with a gap, which is what says "overhead".
  static void _paintTrunk(Canvas canvas, double x, double y, double radius) {
    final at = Offset(x, y);
    DioramaArt.paintCylinderShadow(
      canvas,
      at,
      treeCanopy(radius) * 0.9,
      base: treeCrownBase,
      height: treeCrownTop - treeCrownBase,
    );
    DioramaArt.paintCylinder(
      canvas,
      at,
      radius,
      height: treeCrownBase,
      color: const Color(0xFF7A5228),
    );
  }

  /// A tree's canopy, held up on its trunk.
  ///
  /// Three blobs at three heights, from the dark underside at
  /// [treeCrownBase] to the lit crown at [treeCrownTop], which is what gives
  /// it volume rather than a lit side painted on a disc.
  static void _paintCanopy(Canvas canvas, double x, double y, double radius) {
    final at = Offset(x, y);
    final canopy = treeCanopy(radius);
    final low = DioramaArt.cylinderTop(at, height: treeCrownBase);
    final mid = DioramaArt.cylinderTop(
      at,
      height: (treeCrownBase + treeCrownTop) / 2,
    );
    final high = DioramaArt.cylinderTop(at, height: treeCrownTop);
    canvas
      // Three overlapping blobs of leaf, darkest and lowest first.
      ..drawCircle(low, canopy, Paint()..color = const Color(0xFF3C7A34))
      ..drawCircle(
        mid.translate(-canopy * 0.22, -canopy * 0.24),
        canopy * 0.74,
        Paint()..color = const Color(0xFF4E9440),
      )
      ..drawCircle(
        high.translate(-canopy * 0.34, -canopy * 0.36),
        canopy * 0.42,
        Paint()..color = const Color(0xFF67AE52),
      );
  }

  // ---- Lounge & pool (south arm) ------------------------------------------

  /// Draws the dry deck around the pool, and the loungers on it.
  ///
  /// The pool itself is **not** drawn here. It is live, animated water in
  /// `WaterComponent`, and a display list is a recording — putting moving
  /// water in one would freeze the first frame of it forever.
  ///
  /// Moved here from `FurnitureComponent` in Phase 10, verbatim, along with
  /// the booths and the pillar below: that component stopped knowing what a
  /// conference looks like when the world became a value.
  static void paintLounge(Canvas canvas) {
    final accent = WorldPalette.of(WorldZone.lounge).accent;
    final surround = Paint()..color = accent.withValues(alpha: 0.16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect(WorldLayout.pool).inflate(22),
        const Radius.circular(38),
      ),
      surround,
    );

    // The pool's north wall, in shade. The water sits [poolDepth] below the
    // deck, so inside the north rim a strip of wall shows, facing south and
    // away from the light — the one cue that makes the pool a hole rather
    // than a blue rug. Static, so it lives here and not in the live water;
    // it is drawn over the water (this picture is above it) but translucent,
    // and clipped to the water's own rounded shape so it follows the rim.
    final pool = rect(WorldLayout.pool);
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(pool, poolRimRadius))
      ..drawRect(
        poolInnerWall(pool),
        Paint()..color = _shade(accent, -0.30).withValues(alpha: 0.42),
      )
      ..restore();

    for (final lounger in WorldLayout.loungers) {
      _paintLounger(canvas, rect(lounger.rect), accent);
    }
  }

  /// How far the water sits below the deck, in world units.
  static const double poolDepth = 8;

  /// How round the pool's rim is: a copy of `WaterComponent.shapeRadius`.
  ///
  /// Copied rather than imported, because importing the water component
  /// would pull Flame into the static-art files; a test keeps the copy
  /// honest.
  static const Radius poolRimRadius = Radius.circular(26);

  /// The strip of wall that shows inside the north rim of [pool].
  static Rect poolInnerWall(Rect pool) => Rect.fromLTRB(
    pool.left,
    pool.top,
    pool.right,
    pool.top + poolDepth * DioramaArt.lift,
  );

  /// How tall a lounger's frame is, in world units.
  static const double loungerHeight = 5;

  /// How thick a lounger's cushion is, on top of the frame, in world units.
  static const double cushionHeight = 3;

  /// How tall a lounger's backrest stands over its frame, in world units.
  static const double loungerBackHeight = 13;

  /// A lounger: a white frame, a cushion on it, and a backrest at the north
  /// end, so whoever lies on it faces south, at the pool.
  ///
  /// The cushion and backrest stand on the frame (their `base` is its
  /// height) and inside its footprint, so the lounger collides exactly where
  /// the flat one did.
  static void _paintLounger(Canvas canvas, Rect at, Color accent) {
    DioramaArt.paintBox(
      canvas,
      at,
      height: loungerHeight,
      color: const Color(0xFFF4F1EA),
      corner: corner,
    );
    final cushion = _shade(accent, 0.30);
    DioramaArt.paintBox(
      canvas,
      Rect.fromLTRB(at.left + 3, at.top + 9, at.right - 3, at.bottom - 3),
      base: loungerHeight,
      height: cushionHeight,
      color: cushion,
      corner: const Radius.circular(3),
      shadow: false,
    );
    DioramaArt.paintBox(
      canvas,
      Rect.fromLTRB(at.left + 3, at.top + 2, at.right - 3, at.top + 9),
      base: loungerHeight,
      height: loungerBackHeight,
      color: cushion,
      corner: const Radius.circular(3),
    );
  }

  // ---- Sponsor row (east arm) ---------------------------------------------

  /// Draws a booth for each of [sponsors].
  ///
  /// The only part of the world that comes from config. It is still static
  /// art: config is read before the game loads, so a booth is exactly as
  /// fixed as the stage is.
  ///
  /// Since Phase 16 a booth is three pieces inside the same footprint: a low
  /// floor, a back wall standing across its north half with the sign on its
  /// face, and a counter along its south edge. **The sign has not moved.**
  /// The wall is built backwards from the band — see [boothWall] — so the
  /// brand band and the sponsor's name sit exactly where they always did,
  /// and only now they are painted on something standing up.
  static void paintBooths(Canvas canvas, List<Sponsor> sponsors) {
    for (final sponsor in sponsors) {
      final footprint = rect(sponsor.footprint);
      final wall = _upright(boothWall(footprint));
      final counter = boothCounter(footprint);

      DioramaArt.paintBox(
        canvas,
        footprint,
        height: boothFloorHeight,
        color: _shade(sponsor.color, -0.28),
        corner: corner,
      );
      DioramaArt.paintBoxShadow(
        canvas,
        wall.footprint,
        height: wall.height,
      );
      // The wall up to the booth's north edge. The rest of it is overhead —
      // see [boothOverhead] — and the two clips are exact complements, hard
      // edged, so the halves meet on a pixel line with no seam and no
      // doubled hairline.
      canvas
        ..save()
        ..clipRect(
          boothOverhead(footprint),
          clipOp: ClipOp.difference,
          doAntiAlias: false,
        );
      _paintBoothWall(canvas, footprint, sponsor.color);
      canvas
        ..restore()
        ..drawRRect(
          // A band of the brand colour across the face of the wall: the one
          // part of a booth a walking player actually reads.
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              footprint.left + 8,
              footprint.top + 8,
              footprint.right - 8,
              footprint.top + 34,
            ),
            corner,
          ),
          Paint()..color = sponsor.color,
        );
      final label = _boothLabel(sponsor.name);
      canvas.drawParagraph(
        label,
        Offset(footprint.center.dx - label.width / 2, footprint.top + 13),
      );

      // The counter: a white top with the brand colour down its front, the
      // trim a booth wears at the height a visitor's eye actually is.
      DioramaArt.paintBox(
        canvas,
        counter,
        height: boothCounterHeight,
        color: const Color(0xFFF7F4EE),
        front: sponsor.color,
        corner: const Radius.circular(3),
      );
    }
  }

  /// Draws the booths' overhead: the top of each back wall, over the beans.
  static void paintBoothsOverhead(Canvas canvas, List<Sponsor> sponsors) {
    for (final sponsor in sponsors) {
      final footprint = rect(sponsor.footprint);
      canvas
        ..save()
        ..clipRect(boothOverhead(footprint), doAntiAlias: false);
      _paintBoothWall(canvas, footprint, sponsor.color);
      canvas.restore();
    }
  }

  /// The part of the booth on [footprint] that is drawn over the beans:
  /// everything north of the booth's own north edge, which is the top of its
  /// back wall.
  ///
  /// **Only that much.** The collider is a point at a bean's feet, so a bean
  /// can stand right at the counter, and its head then reaches up across the
  /// wall's face. A whole wall over the beans would cut the head off the one
  /// visitor actually at the booth. North of the footprint is only ever
  /// somebody *behind* the booth, and the top of the wall is what should
  /// hide them.
  static Rect boothOverhead(Rect footprint) => Rect.fromLTRB(
    footprint.left - 4,
    footprint.top - footprint.height,
    footprint.right + 4,
    footprint.top,
  );

  /// A booth's back wall in its darker brand colour, without its shadow.
  static void _paintBoothWall(Canvas canvas, Rect footprint, Color brand) {
    final wall = _upright(boothWall(footprint));
    DioramaArt.paintBox(
      canvas,
      wall.footprint,
      height: wall.height,
      color: _shade(brand, -0.40),
      front: _shade(brand, -0.20),
      corner: corner,
      shadow: false,
    );
  }

  /// How far a booth's floor stands off the ground, in world units.
  static const double boothFloorHeight = 3;

  /// How tall a booth's counter is, in world units.
  static const double boothCounterHeight = 12;

  /// How deep a booth's counter is, north to south, in world units.
  static const double boothCounterDepth = 16;

  /// The face of the back wall of the booth on [footprint]: the sign the
  /// brand band and the name are painted on.
  ///
  /// Its bottom edge is the bottom of the band, so the band is the lower
  /// part of the wall and the wall stands up out of the footprint above it.
  /// Its top edge rises past the footprint's north edge — a wall's face
  /// shows *above* where it stands — which is art, not collision: the booth
  /// still blocks exactly its footprint.
  static Rect boothWall(Rect footprint) => Rect.fromLTRB(
    footprint.left,
    footprint.top - 18,
    footprint.right,
    footprint.top + 34,
  );

  /// The counter along the south edge of the booth on [footprint].
  ///
  /// Shallow and low on purpose: its lifted top must clear the bottom of the
  /// sign, or the counter would be painted across the sponsor's name.
  static Rect boothCounter(Rect footprint) => Rect.fromLTRB(
    footprint.left + 10,
    footprint.bottom - 4 - boothCounterDepth,
    footprint.right - 10,
    footprint.bottom - 4,
  );

  // ---- Atrium (centre) ----------------------------------------------------

  /// How tall the credit pillar is, in world units.
  ///
  /// The tallest thing in the atrium on purpose: it is the landmark every
  /// spawn faces, and the one prop you should be able to find from across
  /// the room.
  static const double pillarHeight = 84;

  /// How far up the pillar its lit band starts, in world units.
  static const double pillarBandBase = 58;

  /// How tall the pillar's lit band is, in world units.
  static const double pillarBandHeight = 6;

  /// The colour of the pillar's lit band: the sign yellow, unshaded on every
  /// face because it is a light, not a surface the sun falls on.
  static const Color pillarBand = Color(0xFFFFD23F);

  /// Draws the credit pillar in the middle of the atrium.
  ///
  /// Three stacked cylinders — shaft, lit band, shaft — rather than one with
  /// a stripe painted on, because the band stands half a unit proud of the
  /// shaft and the stack gets that for free. Painted bottom to top, so each
  /// piece covers the top face of the one under it, which is the painter's
  /// algorithm doing the only depth sort this prop needs. One shadow for the
  /// whole height.
  static void paintPillar(Canvas canvas) {
    const centre = Offset(WorldLayout.pillarX, WorldLayout.pillarY);
    const radius = WorldLayout.pillarRadius;
    final stone = WorldPalette.of(WorldZone.atrium).accent;
    const above = pillarBandBase + pillarBandHeight;

    DioramaArt.paintCylinderShadow(
      canvas,
      centre,
      radius,
      height: pillarHeight,
    );
    DioramaArt.paintCylinder(
      canvas,
      centre,
      radius,
      height: pillarBandBase,
      color: stone,
      shadow: false,
    );
    DioramaArt.paintCylinder(
      canvas,
      centre,
      radius + 1.5,
      base: pillarBandBase,
      height: pillarBandHeight,
      color: pillarBand,
      front: pillarBand,
      shadow: false,
    );
    DioramaArt.paintCylinder(
      canvas,
      centre,
      radius,
      base: above,
      height: pillarHeight - above,
      color: stone,
      shadow: false,
    );
    canvas.drawCircle(
      DioramaArt.cylinderTop(centre, height: pillarHeight),
      radius - 9,
      Paint()..color = _boothScreen,
    );
  }

  static const Color _boothScreen = Color(0xFF0D1520);
  static const Color _boothLabelInk = Color(0xFF0B1A22);

  static Paragraph _boothLabel(String name) {
    final builder =
        ParagraphBuilder(
            ParagraphStyle(
              fontFamily: AppFonts.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.center,
            ),
          )
          ..pushStyle(TextStyle(color: _boothLabelInk))
          ..addText(name);
    return builder.build()
      ..layout(const ParagraphConstraints(width: Sponsor.boothWidth - 16));
  }

  // ---- Shared prop primitives ---------------------------------------------

  /// Converts a world rectangle into a drawable one.
  static Rect rect(WorldRect r) =>
      Rect.fromLTRB(r.left, r.top, r.right, r.bottom);

  /// Returns [base] moved towards white (positive) or black (negative).
  static Color _shade(Color base, double amount) => Color.lerp(
    base,
    amount < 0 ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    amount.abs(),
  )!;
}
