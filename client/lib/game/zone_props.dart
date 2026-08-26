import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/app_fonts.dart';
import 'package:client/core/sponsor.dart';
import 'package:client/core/world_palette.dart';
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

    // The shade the awning throws, drawn first so everything else sits in it.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect(WorldLayout.courtAwning),
        const Radius.circular(14),
      ),
      Paint()..color = const Color(0x1A2A1206),
    );

    _shadow(canvas, counter);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(counter, corner),
        Paint()..color = _shade(colors.accent, -0.10),
      )
      // The serving surface: a lighter top edge is what turns a rectangle
      // into a counter you can imagine putting a tray down on.
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            counter.left + 6,
            counter.top + 6,
            counter.right - 6,
            counter.bottom - 6,
          ),
          corner,
        ),
        Paint()..color = _shade(colors.accent, 0.24),
      );

    _paintStallBays(canvas, counter, colors);
    _paintTrays(canvas, counter, colors);

    for (var i = 0; i < WorldLayout.courtStools.length; i++) {
      final stool = WorldLayout.courtStools[i];
      final at = Offset(stool.x, stool.y);
      canvas
        ..drawCircle(
          at.translate(2, 3),
          stool.radius,
          Paint()..color = const Color(0x33000000),
        )
        ..drawCircle(
          at,
          stool.radius,
          Paint()..color = _shade(colors.accent, 0.10),
        )
        // A plate on every other stool. Not on all four: a row of identical
        // full plates reads as a display case, and the gap is what says
        // somebody is sitting here and somebody else has not arrived yet.
        ..drawCircle(
          at,
          stool.radius * 0.55,
          Paint()
            ..color = i.isEven
                ? const Color(0xFFF2ECDF)
                : _shade(colors.accent, -0.16),
        );
      if (i.isEven) {
        canvas.drawCircle(
          at,
          stool.radius * 0.3,
          Paint()..color = const Color(0xFFD9A05B),
        );
      }
    }

    _paintSnackCart(canvas, colors);
    _paintAwning(canvas, colors);

    for (final planter in WorldLayout.planters) {
      _paintPlanter(canvas, planter.x, planter.y, planter.radius, colors);
    }
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

  static void _paintSnackCart(Canvas canvas, ZoneColors colors) {
    final cart = rect(WorldLayout.snackCart);
    _shadow(canvas, cart);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(cart, corner),
        Paint()..color = _shade(colors.accent, 0.06),
      )
      // A parasol over the cart, offset so it reads as being above it.
      ..drawCircle(
        cart.center.translate(0, -6),
        44,
        Paint()..color = const Color(0x33F4C542),
      )
      ..drawCircle(
        cart.center.translate(0, -6),
        44,
        Paint()
          ..color = const Color(0x80D89A16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    // Samosas: three triangles, which is all a samosa needs to be one.
    final pastry = Paint()..color = const Color(0xFFD9A05B);
    for (var i = 0; i < 3; i++) {
      final at = Offset(cart.left + 26 + i * 30, cart.center.dy + 4);
      canvas.drawPath(
        Path()
          ..moveTo(at.dx, at.dy - 9)
          ..lineTo(at.dx + 10, at.dy + 7)
          ..lineTo(at.dx - 10, at.dy + 7)
          ..close(),
        pastry,
      );
    }
  }

  static void _paintAwning(Canvas canvas, ZoneColors colors) {
    final awning = rect(WorldLayout.courtAwning);
    final shape = RRect.fromRectAndRadius(awning, const Radius.circular(14));
    canvas
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

    // The bulbs strung along the front edge of the awning.
    for (var y = awning.top + 22; y < awning.bottom; y += 42) {
      final at = Offset(awning.right, y);
      canvas
        ..drawCircle(at, 11, Paint()..color = const Color(0x33FFD08A))
        ..drawCircle(at, 4, Paint()..color = const Color(0xFFFFDCA0));
    }
  }

  static void _paintPlanter(
    Canvas canvas,
    double x,
    double y,
    double radius,
    ZoneColors colors,
  ) {
    final at = Offset(x, y);
    canvas
      ..drawCircle(
        at.translate(2, 3),
        radius,
        Paint()..color = const Color(0x33000000),
      )
      ..drawCircle(at, radius, Paint()..color = _shade(colors.accent, -0.06));
    // Foliage: five overlapping blobs on a fixed lattice, which reads as a
    // shrub from three metres up and costs five circles.
    final leaf = Paint()..color = const Color(0xFF4F8F45);
    for (var i = 0; i < 5; i++) {
      final angle = i * 2 * math.pi / 5;
      canvas.drawCircle(
        at.translate(
          math.cos(angle) * radius * 0.38,
          math.sin(angle) * radius * 0.38,
        ),
        radius * 0.46,
        leaf,
      );
    }
    canvas.drawCircle(
      at,
      radius * 0.40,
      Paint()..color = const Color(0xFF62A855),
    );
  }

  // ---- Conference hall (north arm) ----------------------------------------

  /// Draws the stage: light spill, apron, backdrop panels, screen, speakers.
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

    _shadow(canvas, stage);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(stage, corner),
        Paint()..color = _shade(colors.accent, -0.28),
      )
      // The backdrop: three panels behind the screen, the outer two darker,
      // which is what gives a flat rectangle a middle to look at.
      ..drawRect(
        Rect.fromLTRB(
          stage.left + 8,
          stage.top + 8,
          stage.left + 44,
          stage.bottom - 30,
        ),
        Paint()..color = _shade(colors.accent, -0.10),
      )
      ..drawRect(
        Rect.fromLTRB(
          stage.right - 44,
          stage.top + 8,
          stage.right - 8,
          stage.bottom - 30,
        ),
        Paint()..color = _shade(colors.accent, -0.10),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(rect(WorldLayout.stageScreen), corner),
        Paint()..color = const Color(0xFF0D1520),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          rect(WorldLayout.stageScreen).deflate(5),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0x38FFD9A0),
      )
      // The apron: the lip of the stage a speaker stands on, and the one edge
      // of this prop the audience actually sees.
      ..drawRect(
        Rect.fromLTRB(
          stage.left,
          stage.bottom - 22,
          stage.right,
          stage.bottom,
        ),
        Paint()..color = _shade(colors.accent, 0.16),
      )
      ..drawRect(
        Rect.fromLTRB(
          stage.left,
          stage.bottom - 22,
          stage.right,
          stage.bottom - 18,
        ),
        Paint()..color = const Color(0x66FFE9B0),
      );

    // Speaker stacks at the corners of the apron.
    for (final x in [stage.left + 6, stage.right - 34]) {
      final box = Rect.fromLTWH(x, stage.bottom - 62, 28, 40);
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(3)),
          Paint()..color = const Color(0xFF16202C),
        )
        ..drawCircle(
          box.center.translate(0, -6),
          7,
          Paint()..color = const Color(0xFF2C3A4A),
        )
        ..drawCircle(
          box.center.translate(0, 11),
          4,
          Paint()..color = const Color(0xFF2C3A4A),
        );
    }

    // The seating, unchanged in footprint, with a back rail so a row reads as
    // seats rather than as a bar of colour.
    final seat = Paint()..color = colors.accent.withValues(alpha: 0.55);
    final rail = Paint()..color = colors.accent.withValues(alpha: 0.85);
    for (final row in WorldLayout.seatRows) {
      final at = rect(row.rect);
      canvas
        ..drawRRect(RRect.fromRectAndRadius(at, corner), seat)
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(at.left, at.top, at.right, at.top + 5),
            corner,
          ),
          rail,
        );
      for (var x = at.left + 29; x < at.right - 10; x += 29) {
        canvas.drawLine(
          Offset(x, at.top + 6),
          Offset(x, at.bottom - 2),
          Paint()
            ..color = const Color(0x3D0B1420)
            ..strokeWidth = 1.6,
        );
      }
    }
  }

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
      final top = rect(desk.rect);
      _shadow(canvas, top);
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(top, corner),
          Paint()..color = _shade(colors.accent, 0.52),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(top.left, top.top, top.right, top.top + 7),
            corner,
          ),
          Paint()..color = _shade(colors.accent, 0.18),
        );
      // Monitors along the desk, each with a lit screen. Four small rects per
      // desk is what turns a table into a lab.
      for (var x = top.left + 26; x < top.right - 18; x += 48) {
        final screen = Rect.fromLTWH(x, top.top + 11, 30, 17);
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(screen, const Radius.circular(2)),
            Paint()..color = const Color(0xFF16222E),
          )
          ..drawRRect(
            RRect.fromRectAndRadius(
              screen.deflate(2.5),
              const Radius.circular(1.5),
            ),
            Paint()..color = const Color(0xFF43C8E0),
          );
      }
    }
  }

  static void _paintScreen(
    Canvas canvas,
    Rect at,
    ZoneColors colors,
    String message,
  ) {
    _shadow(canvas, at);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(at, corner),
        Paint()..color = _shade(colors.accent, -0.42),
      )
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

  static void _paintWhiteboard(Canvas canvas, Rect at, ZoneColors colors) {
    _shadow(canvas, at);
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(at, corner),
        Paint()..color = _shade(colors.accent, -0.30),
      )
      ..drawRRect(
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
      final at = rect(bench.rect);
      _shadow(canvas, at);
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(at, corner),
          Paint()..color = const Color(0xFF9C6B3C),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(at.left, at.top, at.right, at.top + 8),
            corner,
          ),
          Paint()..color = const Color(0xFFB58351),
        );
    }

    // Trees last, so their canopies fall across everything else — which is
    // the only shading cue this camera angle can give.
    for (final tree in WorldLayout.gardenTrees) {
      _paintTree(canvas, tree.x, tree.y, tree.radius, colors);
    }
  }

  /// Draws the stepped deck: **fake depth on flat, walkable ground.**
  ///
  /// Four painted treads and a shadow gradient, climbing east to a platform
  /// that looks out over the pool. Nothing here is an obstacle and nothing
  /// here has a height — see `WorldLayout.gardenDeck`. The illusion is
  /// entirely in the lighting: each tread is lighter than the one before it,
  /// with a dark riser line on its western side, which is what a flight of
  /// steps looks like from above at this angle.
  static void _paintSteppedDeck(Canvas canvas, ZoneColors colors) {
    final deck = rect(WorldLayout.gardenDeck);
    const treadWidth =
        (WorldLayout.deckPlatformX - 400) / WorldLayout.deckTreads;

    // The shadow the whole structure would cast, if it had a height.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        deck.translate(-6, 8),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0x33000000),
    );

    const timber = Color(0xFFB2854E);
    for (var i = 0; i < WorldLayout.deckTreads; i++) {
      final left = deck.left + i * treadWidth;
      canvas
        ..drawRect(
          Rect.fromLTRB(left, deck.top, left + treadWidth, deck.bottom),
          // Each tread a shade lighter than the last: the eye reads a
          // brightness ramp as a climb.
          Paint()..color = _shade(timber, -0.20 + i * 0.055),
        )
        // The riser, on the western face of each tread.
        ..drawRect(
          Rect.fromLTRB(left, deck.top, left + 5, deck.bottom),
          Paint()..color = const Color(0x59241505),
        );
    }

    // The platform itself, brightest of all because it is highest.
    final platform = Rect.fromLTRB(
      WorldLayout.deckPlatformX,
      deck.top,
      deck.right,
      deck.bottom,
    );
    canvas.drawRect(platform, Paint()..color = _shade(timber, 0.10));
    final plank = Paint()
      ..color = const Color(0x40241505)
      ..strokeWidth = 1.6;
    for (var y = platform.top + 18; y < platform.bottom; y += 18) {
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
      Offset(platform.left + 4, platform.bottom - 5),
      Offset(platform.right - 4, platform.bottom - 5),
      rail,
    );
    for (var x = platform.left + 10; x < platform.right; x += 34) {
      canvas.drawLine(
        Offset(x, platform.bottom - 5),
        Offset(x, platform.bottom - 22),
        rail,
      );
    }

    // The lip where the deck meets the ground, so it does not float.
    canvas.drawRect(
      Rect.fromLTRB(deck.left, deck.bottom - 3, deck.right, deck.bottom),
      Paint()..color = const Color(0x66241505),
    );
  }

  static void _paintFountain(Canvas canvas, ZoneColors colors) {
    final centre = Offset(WorldLayout.fountain.x, WorldLayout.fountain.y);
    final radius = WorldLayout.fountain.radius;
    canvas
      ..drawCircle(
        centre.translate(3, 5),
        radius,
        Paint()..color = const Color(0x33000000),
      )
      ..drawCircle(centre, radius, Paint()..color = _shade(colors.accent, 0.30))
      ..drawCircle(
        centre,
        radius - 7,
        Paint()..color = const Color(0xFF57BEDA),
      )
      ..drawCircle(
        centre,
        radius - 7,
        Paint()
          ..color = const Color(0x40FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      )
      // The spout, and the rings it makes. Static, because the fountain is in
      // the picture — a moving one would need its own live component, and one
      // animated water feature in this world is enough.
      ..drawCircle(centre, 8, Paint()..color = const Color(0xFFDFF6FF))
      ..drawCircle(
        centre,
        radius * 0.55,
        Paint()
          ..color = const Color(0x59DFF6FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
  }

  static void _paintTree(
    Canvas canvas,
    double x,
    double y,
    double radius,
    ZoneColors colors,
  ) {
    final at = Offset(x, y);
    final canopy = radius * 2.6;
    canvas
      // The canopy shadow, offset the way every other shadow in the world is.
      ..drawCircle(
        at.translate(7, 11),
        canopy,
        Paint()..color = const Color(0x2E000000),
      )
      ..drawCircle(at, radius, Paint()..color = const Color(0xFF7A5228))
      // Three overlapping blobs of leaf, darkest first, so the canopy has a
      // lit side without needing a gradient.
      ..drawCircle(at, canopy, Paint()..color = const Color(0xFF3C7A34))
      ..drawCircle(
        at.translate(-canopy * 0.22, -canopy * 0.24),
        canopy * 0.74,
        Paint()..color = const Color(0xFF4E9440),
      )
      ..drawCircle(
        at.translate(-canopy * 0.34, -canopy * 0.36),
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
    final solid = Paint()..color = accent;
    for (final lounger in WorldLayout.loungers) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect(lounger.rect), corner),
        solid,
      );
    }
  }

  // ---- Sponsor row (east arm) ---------------------------------------------

  /// Draws a booth for each of [sponsors].
  ///
  /// The only part of the world that comes from config. It is still static
  /// art: config is read before the game loads, so a booth is exactly as
  /// fixed as the stage is.
  static void paintBooths(Canvas canvas, List<Sponsor> sponsors) {
    for (final sponsor in sponsors) {
      final footprint = rect(sponsor.footprint);
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(footprint, corner),
          Paint()..color = _shade(sponsor.color, -0.28),
        )
        // A band of the brand colour across the front of the booth: the one
        // part of a booth a walking player actually reads.
        ..drawRRect(
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
    }
  }

  // ---- Atrium (centre) ----------------------------------------------------

  /// Draws the credit pillar in the middle of the atrium.
  static void paintPillar(Canvas canvas) {
    const centre = Offset(WorldLayout.pillarX, WorldLayout.pillarY);
    canvas
      ..drawCircle(
        centre,
        WorldLayout.pillarRadius,
        Paint()..color = WorldPalette.of(WorldZone.atrium).accent,
      )
      ..drawCircle(
        centre,
        WorldLayout.pillarRadius - 9,
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

  /// The soft contact shadow every solid prop casts.
  ///
  /// One offset blob, not a blur: a `MaskFilter` on forty props is a real
  /// per-prop cost at record time and a bigger one in the raster, and at this
  /// camera angle nobody can tell the difference.
  static void _shadow(Canvas canvas, Rect at) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(at.translate(3, 4), corner),
      Paint()..color = const Color(0x2E000000),
    );
  }

  /// Returns [base] moved towards white (positive) or black (negative).
  static Color _shade(Color base, double amount) => Color.lerp(
    base,
    amount < 0 ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    amount.abs(),
  )!;
}
