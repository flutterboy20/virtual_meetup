import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/world_palette.dart';
import 'package:client/game/diorama_art.dart';
import 'package:client/game/world_layout.dart';
import 'package:protocol/protocol.dart';

/// The texture painted on each zone's floor.
///
/// All of this is drawn **once**, into the floor's `ui.Picture` — see
/// `static_art.dart`. That is the only reason it can exist at all: a plank
/// floor is fifteen rects, fifteen seams and thirty butt-joints, and a paved
/// yard is sixty-four pavers. Rebuilt every frame, that would be a slideshow
/// on the phone this is aimed at. Recorded once, it costs the same per frame
/// as the flat rectangle it replaces.
///
/// Every colour here is derived from the zone's own [ZoneColors] rather than
/// written out, so re-tuning the palette re-tunes the art with it and the
/// minimap never drifts from the world. Nothing is random at runtime: the
/// "random" plank tones come from [_noise], a pure hash of the plank index, so
/// the floor is byte-for-byte the same on every device and on every launch.
///
/// The unit everything is built from is [tile] — the same 64 units the
/// nametag fade radius is quoted in — so the textures line up with the rest of
/// the world's spacing instead of inventing a second, competing grid.
abstract final class ZoneFloorArt {
  /// The floor module every texture is a multiple or divisor of, in world
  /// units.
  static const double tile = 64;

  /// The two corners of the bounding box the building does not cover.
  ///
  /// They are **not** rooms and never will be: seven zones already give every
  /// person at the target crowd about 76x76 units of floor, and empty floor is
  /// what kills a social toy. They still need a *ground treatment* though —
  /// under a daylight palette a flat dark fill stops reading as ground and
  /// starts reading as a hole in the renderer.
  ///
  /// Written out rather than derived, and then checked by a test that they
  /// contain no floor and that together with the seven zones they tile the
  /// whole bounding box. That is what keeps two magic rectangles honest.
  static const List<Rect> voids = [
    Rect.fromLTRB(0, 0, 600, 400),
    Rect.fromLTRB(1000, 800, 1600, 1200),
  ];

  /// Paints the ground outside the building, inside [area].
  ///
  /// Restrained on purpose: big dry paving slabs and nothing else. **No
  /// props.** Anything that looks like furniture out here implies you can walk
  /// out here, and you cannot — this is outside `isOnFloor`.
  static void paintOutside(Canvas canvas, Rect area) {
    const slab = 120.0;
    canvas
      ..save()
      ..clipRect(area);
    var index = 0;
    for (var y = area.top; y < area.bottom; y += slab) {
      for (var x = area.left; x < area.right; x += slab) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, slab, slab).deflate(1.5),
          Paint()
            ..color = _shade(
              WorldPalette.outside,
              (_noise(index) - 0.5) * 0.055,
            ),
        );
        index++;
      }
    }
    // One drainage channel per void, running to the building. Enough to say
    // "somebody laid this ground" and nothing like an invitation.
    canvas
      ..drawLine(
        Offset(area.left, area.center.dy),
        Offset(area.right, area.center.dy),
        Paint()
          ..color = _shade(WorldPalette.outside, -0.16)
          ..strokeWidth = 3,
      )
      ..restore();
  }

  /// Paints a **conference** zone's texture inside [rect]. The caller owns the
  /// clip, and a zone from another map draws nothing.
  static void paint(Canvas canvas, WorldZone zone, Rect rect) {
    final colors = WorldPalette.of(zone);
    switch (zone) {
      case WorldZone.atrium:
        _atrium(canvas, rect, colors);
      case WorldZone.hall:
        _hall(canvas, rect, colors);
      case WorldZone.sponsorRow:
        _sponsorRow(canvas, rect, colors);
      case WorldZone.lounge:
        _lounge(canvas, rect, colors);
      case WorldZone.foodCourt:
        _foodCourt(canvas, rect, colors);
      case WorldZone.codeLab:
        _codeLab(canvas, rect, colors);
      case WorldZone.garden:
        _garden(canvas, rect, colors);
      case _:
        // The beach's bands are `BeachFloorArt`'s business. This file is the
        // conference's floor and deliberately does not grow a second venue's
        // textures — see `GameMap.paintZoneFloor`, which is what decides
        // which of the two a zone goes to.
        break;
    }
  }

  // ---- Atrium: polished tile checker, a medallion, and wayfinding ---------

  static void _atrium(Canvas canvas, Rect rect, ZoneColors colors) {
    const step = tile * 1.25; // 80: exactly five tiles across the atrium.
    _checker(canvas, rect, step, colors, light: 0.045, dark: -0.035);
    _grout(canvas, rect, step, colors);

    // A medallion under the credit pillar. The pillar itself is furniture and
    // is drawn over this, so what a player sees is a plinth standing on an
    // inlay rather than a post dropped on a tiled floor.
    final centre = rect.center;
    final accent = colors.accent;
    canvas
      ..drawCircle(centre, 148, Paint()..color = _alpha(accent, 0.07))
      ..drawCircle(
        centre,
        148,
        Paint()
          ..color = _alpha(accent, 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      )
      ..drawCircle(
        centre,
        112,
        Paint()
          ..color = _alpha(accent, 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    _compass(canvas, centre, accent);

    // Wayfinding painted on the floor, pointing at each of the four arms.
    // The atrium is the only room where somebody genuinely does not know
    // which way to go, and a legend in a HUD corner is unreadable while
    // walking on a phone.
    _chevron(canvas, Offset(centre.dx, rect.top + 74), -math.pi / 2, accent);
    _chevron(canvas, Offset(centre.dx, rect.bottom - 74), math.pi / 2, accent);
    _chevron(canvas, Offset(rect.left + 74, centre.dy), math.pi, accent);
    _chevron(canvas, Offset(rect.right - 74, centre.dy), 0, accent);
  }

  /// How far the compass rose's long points reach from the centre.
  ///
  /// Inside the medallion's inner ring (112), so the rose sits in the inlay
  /// rather than across its border.
  static const double compassPoint = 100;

  /// The radius of the compass ring, outside the medallion.
  static const double compassRing = 176;

  /// A compass rose under the pillar, and a ring of ticks around the inlay.
  ///
  /// Each point is two triangles, the north-west half lighter than the
  /// other: lit from the same corner every shadow in the world is cast
  /// from, which is what makes a flat inlay read as a carved one.
  static void _compass(Canvas canvas, Offset centre, Color accent) {
    final lit = Path();
    final shaded = Path();
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final length = i.isEven ? compassPoint : compassPoint * 0.62;
      final half = i.isEven ? 20.0 : 13.0;
      final tip = centre + Offset.fromDirection(angle, length);
      final left = centre + Offset.fromDirection(angle - math.pi / 2, half);
      final right = centre + Offset.fromDirection(angle + math.pi / 2, half);
      // Which side faces the north-west light: the side whose outward
      // direction points against the light's travel (+x, +y).
      final leftFacesLight = (left - centre).dx + (left - centre).dy < 0;
      (leftFacesLight ? lit : shaded).addPolygon([centre, left, tip], true);
      (leftFacesLight ? shaded : lit).addPolygon([centre, right, tip], true);
    }
    canvas
      ..drawPath(shaded, Paint()..color = _alpha(accent, 0.28))
      ..drawPath(lit, Paint()..color = _alpha(accent, 0.11))
      ..drawCircle(
        centre,
        compassRing,
        Paint()
          ..color = _alpha(accent, 0.20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );

    // Ticks inside the ring: long at the eight points of the rose, short
    // between. One path, one draw call.
    final ticks = Path();
    for (var i = 0; i < 32; i++) {
      final angle = i * math.pi / 16 - math.pi / 2;
      final inner = compassRing - (i.isEven ? 14 : 7);
      ticks
        ..moveTo(
          centre.dx + math.cos(angle) * inner,
          centre.dy + math.sin(angle) * inner,
        )
        ..lineTo(
          centre.dx + math.cos(angle) * (compassRing - 3),
          centre.dy + math.sin(angle) * (compassRing - 3),
        );
    }
    canvas.drawPath(
      ticks,
      Paint()
        ..color = _alpha(accent, 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  // ---- Hall: carpet weave, a centre runner, and a stage apron rug ---------

  static void _hall(Canvas canvas, Rect rect, ZoneColors colors) {
    _weave(canvas, rect, colors, spacing: 10, strength: 0.05);

    // The aisle the seat rows already leave. Painting it makes the gap read
    // as somewhere to walk rather than as a mistake in the seating plan.
    final runner = Rect.fromLTRB(
      rect.center.dx - 26,
      168,
      rect.center.dx + 26,
      rect.bottom,
    );
    _rug(canvas, runner, colors, fill: 0.10, border: 0.26);
    // A row of diamonds down the middle of it, the pattern a conference
    // runner is woven with. One path, so a hundred diamonds are one draw.
    final diamonds = Path();
    for (var y = runner.top + 24; y < runner.bottom - 12; y += 32) {
      diamonds.addPolygon([
        Offset(runner.center.dx, y - 9),
        Offset(runner.center.dx + 8, y),
        Offset(runner.center.dx, y + 9),
        Offset(runner.center.dx - 8, y),
      ], true);
    }
    canvas.drawPath(
      diamonds,
      Paint()..color = _alpha(colors.accent, 0.20),
    );

    // The apron in front of the stage, where a speaker actually stands.
    _rug(
      canvas,
      Rect.fromLTRB(rect.left + 58, 156, rect.right - 58, 196),
      colors,
      fill: 0.13,
      border: 0.30,
    );
  }

  // ---- Sponsor row: expo checker, an aisle runner, bay dividers -----------

  /// The side of one square of the sponsor row's checker, in world units.
  ///
  /// Divides the arm both ways, so no square is cut at a wall.
  static const double expoSquare = 50;

  static void _sponsorRow(Canvas canvas, Rect rect, ZoneColors colors) {
    _checker(canvas, rect, expoSquare, colors, light: 0.03, dark: -0.025);
    _grout(canvas, rect, expoSquare, colors, strength: 0.7);

    // The aisle runs the length of the arm, between the two booth rows.
    final aisle = Rect.fromLTRB(
      rect.left,
      rect.center.dy - 30,
      rect.right - 30,
      rect.center.dy + 30,
    );
    _rug(canvas, aisle, colors, fill: 0.09, border: 0.22);
    // A dashed centre line, the way an expo floor marks its walkway.
    final dashes = Path();
    for (var x = aisle.left + 10; x < aisle.right - 30; x += 40) {
      dashes.addRect(
        Rect.fromLTWH(x, aisle.center.dy - 2, 20, 4),
      );
    }
    canvas.drawPath(dashes, Paint()..color = const Color(0x59FFFFFF));

    // Bay dividers: a stand's worth of floor, marked out the way an expo hall
    // marks it out with tape.
    final divider = Paint()
      ..color = _alpha(colors.accent, 0.16)
      ..strokeWidth = 2;
    for (var x = rect.left + 200; x < rect.right - 40; x += 200) {
      canvas
        ..drawLine(Offset(x, rect.top + 16), Offset(x, rect.top + 96), divider)
        ..drawLine(
          Offset(x, rect.bottom - 96),
          Offset(x, rect.bottom - 16),
          divider,
        );
    }
  }

  // ---- Lounge: sun-bleached deck planks -----------------------------------

  static void _lounge(Canvas canvas, Rect rect, ZoneColors colors) {
    const plank = tile / 2; // 32 units: about a real decking board.
    var index = 0;
    final seam = Paint()
      ..color = _alpha(_shade(colors.floor, -0.30), 0.55)
      ..strokeWidth = 1.4;
    for (var y = rect.top; y < rect.bottom; y += plank) {
      // Deterministic per-plank tone. A real deck is never one colour, and a
      // uniform one reads as a painted rectangle rather than as timber.
      final tone = (_noise(index) - 0.5) * 0.075;
      canvas
        ..drawRect(
          Rect.fromLTWH(rect.left, y, rect.width, plank),
          Paint()..color = _shade(colors.floor, tone),
        )
        ..drawLine(Offset(rect.left, y), Offset(rect.right, y), seam);
      // Butt-joints, staggered so the boards do not all end in one line.
      final offset = _noise(index + 97) * 260;
      for (var x = rect.left + offset; x < rect.right; x += 300) {
        canvas.drawLine(Offset(x, y), Offset(x, y + plank), seam);
      }
      index++;
    }
  }

  // ---- Food court: terracotta tiles ---------------------------------------

  /// The side of one terracotta tile, in world units.
  ///
  /// Divides the court both ways, so no tile is cut at a wall.
  static const double terracottaTile = 50;

  /// Square fired-clay tiles, every one a slightly different tone, each with
  /// a lit north-west edge.
  ///
  /// The lit edge is the paper diorama's light again: a tile laid a little
  /// proud of its grout catches the sun on the two edges facing it. All the
  /// edges are one path and all the joints are one grid, so ninety-six tiles
  /// cost ninety-six fills and three more draws, not three hundred.
  static void _foodCourt(Canvas canvas, Rect rect, ZoneColors colors) {
    const size = terracottaTile;
    final edges = Path();
    var index = 0;
    for (var y = rect.top; y < rect.bottom; y += size) {
      for (var x = rect.left; x < rect.right; x += size) {
        // Deterministic per-tile tone: fired clay is never one colour.
        final tone = (_noise(index) - 0.5) * 0.07;
        canvas.drawRect(
          Rect.fromLTWH(x, y, size, size),
          Paint()..color = _shade(colors.floor, tone),
        );
        edges
          ..moveTo(x + 2, y + size - 3)
          ..lineTo(x + 2, y + 2)
          ..lineTo(x + size - 3, y + 2);
        index++;
      }
    }
    canvas.drawPath(
      edges,
      Paint()
        ..color = _alpha(_shade(colors.floor, 0.45), 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    final joint = Paint()
      ..color = _alpha(_shade(colors.floor, -0.34), 0.5)
      ..strokeWidth = 2;
    for (var x = rect.left + size; x < rect.right; x += size) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), joint);
    }
    for (var y = rect.top + size; y < rect.bottom; y += size) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), joint);
    }
  }

  // ---- Code lab: carpet tiles ---------------------------------------------

  /// Whether the carpet tile in [column], [row] has its pile running north
  /// to south (the other way is east to west).
  ///
  /// Alternating, like a checker: carpet tiles laid "quarter-turned", which
  /// is how an office floor is actually fitted, and the one thing that makes
  /// tiles read as tiles rather than as one carpet with lines on it.
  static bool carpetRunsVertically(int column, int row) =>
      (column + row).isEven;

  static void _codeLab(Canvas canvas, Rect rect, ZoneColors colors) {
    // Every stripe of every tile in two paths, one per direction: two draw
    // calls for the whole room, whatever its size.
    final vertical = Path();
    final horizontal = Path();
    var row = 0;
    for (var y = rect.top; y < rect.bottom; y += tile) {
      var column = 0;
      for (var x = rect.left; x < rect.right; x += tile) {
        for (var i = 6.0; i < tile; i += 8) {
          if (carpetRunsVertically(column, row)) {
            vertical
              ..moveTo(x + i, y + 2)
              ..lineTo(x + i, y + tile - 2);
          } else {
            horizontal
              ..moveTo(x + 2, y + i)
              ..lineTo(x + tile - 2, y + i);
          }
        }
        column++;
      }
      row++;
    }
    final pile = Paint()
      ..color = _shade(colors.floor, -0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas
      ..drawPath(vertical, pile)
      ..drawPath(horizontal, pile);
    _grout(canvas, rect, tile, colors, strength: 0.5);
  }

  // ---- Garden: mown stripes, tufts, and a paved walk ----------------------

  static void _garden(Canvas canvas, Rect rect, ZoneColors colors) {
    const band = tile * 0.75; // 48: a mower's width.
    var index = 0;
    for (var y = rect.top; y < rect.bottom; y += band) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, y, rect.width, band),
        Paint()..color = _shade(colors.floor, index.isEven ? 0.035 : -0.03),
      );
      index++;
    }

    // Tufts on a jittered lattice. Sparse on purpose: this is texture at
    // walking speed, not a botanical drawing, and every tuft is two lines
    // that have to be rasterised whenever the camera is over them.
    final blade = Paint()
      ..color = _alpha(_shade(colors.floor, -0.28), 0.42)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    var seed = 0;
    for (var y = rect.top + 28; y < rect.bottom; y += 56) {
      for (var x = rect.left + 28; x < rect.right; x += 56) {
        final jx = x + (_noise(seed) - 0.5) * 34;
        final jy = y + (_noise(seed + 501) - 0.5) * 34;
        canvas
          ..drawLine(Offset(jx, jy), Offset(jx - 3, jy - 7), blade)
          ..drawLine(Offset(jx + 2, jy), Offset(jx + 4, jy - 8), blade);
        seed++;
      }
    }

    // Clover and daisies: specks of two tones on a jittered lattice, as two
    // `drawPoints` calls. What turns mown stripes into a lawn.
    final dark = <Offset>[];
    final pale = <Offset>[];
    for (var i = 0; i < 360; i++) {
      final at = Offset(
        rect.left + _noise(i + 2000) * rect.width,
        rect.top + _noise(i + 3000) * rect.height,
      );
      (i.isEven ? dark : pale).add(at);
    }
    canvas
      ..drawPoints(
        PointMode.points,
        dark,
        Paint()
          ..color = _alpha(_shade(colors.floor, -0.30), 0.35)
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      )
      ..drawPoints(
        PointMode.points,
        pale,
        Paint()
          ..color = const Color(0x47FFFFE6)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );

    // The walk in from the food court. It exists so the stepped deck at the
    // far end has something leading to it — stairs you arrive at by accident
    // read as decoration.
    final path = gardenWalk(rect);
    canvas.drawRect(path, Paint()..color = _shade(colors.floor, 0.16));
    final slab = Paint()
      ..color = _alpha(_shade(colors.floor, -0.22), 0.45)
      ..strokeWidth = 1.5;
    for (var y = rect.top + 42; y < path.bottom; y += 42) {
      canvas.drawLine(Offset(path.left, y), Offset(path.right, y), slab);
    }

    _gravel(canvas);

    // Stepping stones across the lawn: fountain to walk, walk to deck. Each
    // sits a little proud of the grass, so it casts the world's shadow.
    for (final stone in steppingStones(rect)) {
      final oval = Rect.fromCenter(
        center: stone,
        width: stoneRadius * 2,
        height: stoneRadius * 1.5,
      );
      canvas
        ..drawOval(
          oval.shift(DioramaArt.shadowSlope * 2.5),
          Paint()..color = DioramaArt.shadowColor,
        )
        ..drawOval(oval, Paint()..color = const Color(0xFFDCD2BC));
    }
  }

  /// The paved walk in from the food court, inside the garden's [rect].
  static Rect gardenWalk(Rect rect) =>
      Rect.fromLTRB(248, rect.top, 332, rect.bottom - 96);

  /// How far the gravel round the fountain reaches from its centre.
  ///
  /// Wider than the basin, which stands on it, and short of the walk.
  static const double gravelRadius = 72;

  /// How wide a stepping stone is from its centre, east to west.
  static const double stoneRadius = 10;

  /// How far apart stepping stones are, centre to centre.
  static const double stonePitch = 22;

  /// Where the stepping stones lie in the garden at [rect], west to east.
  ///
  /// One line at the fountain's height, in the two stretches of lawn it
  /// crosses: between the gravel and the walk, and between the walk and the
  /// deck. As many stones as fit each stretch, centred in it, so none sits
  /// half on the paving or half under a step.
  static List<Offset> steppingStones(Rect rect) {
    final walk = gardenWalk(rect);
    final y = WorldLayout.fountain.y;
    final stretches = [
      (WorldLayout.fountain.x + gravelRadius, walk.left),
      (walk.right, WorldLayout.gardenDeck.left),
    ];
    final stones = <Offset>[];
    for (final (from, to) in stretches) {
      final count = ((to - from) / stonePitch).floor();
      final start = from + ((to - from) - count * stonePitch) / 2;
      for (var i = 0; i < count; i++) {
        stones.add(Offset(start + stonePitch * (i + 0.5), y));
      }
    }
    return stones;
  }

  /// A disc of pale gravel the fountain stands in, with its pebbles.
  static void _gravel(Canvas canvas) {
    final centre = Offset(WorldLayout.fountain.x, WorldLayout.fountain.y);
    canvas.drawCircle(
      centre,
      gravelRadius,
      Paint()..color = const Color(0xFFE3D9C2),
    );
    // Only the ring outside the basin: the basin covers the rest.
    final pebbles = <Offset>[
      for (var i = 0; i < 160; i++)
        centre +
            Offset.fromDirection(
              _noise(i + 4000) * 2 * math.pi,
              WorldLayout.fountain.radius +
                  _noise(i + 5000) *
                      (gravelRadius - WorldLayout.fountain.radius - 2),
            ),
    ];
    canvas
      ..drawPoints(
        PointMode.points,
        pebbles,
        Paint()
          ..color = const Color(0x408C7A57)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(
        centre,
        gravelRadius,
        Paint()
          ..color = const Color(0x338C7A57)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  // ---- Shared texture primitives -----------------------------------------

  /// A two-direction fabric hatch: what makes a carpet not a flat rectangle.
  static void _weave(
    Canvas canvas,
    Rect rect,
    ZoneColors colors, {
    required double spacing,
    required double strength,
  }) {
    final warp = Paint()
      ..color = _shade(colors.floor, strength)
      ..strokeWidth = 1;
    final weft = Paint()
      ..color = _shade(colors.floor, -strength)
      ..strokeWidth = 1;
    for (var x = rect.left; x < rect.right; x += spacing) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), warp);
    }
    for (var y = rect.top; y < rect.bottom; y += spacing) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), weft);
    }
  }

  /// A two-tone checker of [step] squares, each [light] or [dark] off the
  /// zone's floor.
  static void _checker(
    Canvas canvas,
    Rect rect,
    double step,
    ZoneColors colors, {
    required double light,
    required double dark,
  }) {
    final on = Paint()..color = _shade(colors.floor, light);
    final off = Paint()..color = _shade(colors.floor, dark);
    var row = 0;
    for (var y = rect.top; y < rect.bottom; y += step) {
      var col = 0;
      for (var x = rect.left; x < rect.right; x += step) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, step, step),
          (row + col).isEven ? on : off,
        );
        col++;
      }
      row++;
    }
  }

  /// Tile joints at [step], in the zone's own grid colour.
  static void _grout(
    Canvas canvas,
    Rect rect,
    double step,
    ZoneColors colors, {
    double strength = 1,
  }) {
    final paint = Paint()
      ..color = _alpha(colors.grid, strength)
      ..strokeWidth = 1;
    for (var x = rect.left + step; x < rect.right; x += step) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
    for (var y = rect.top + step; y < rect.bottom; y += step) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }

  /// A bordered rug or runner: a fill, an inset border, and a hairline edge.
  static void _rug(
    Canvas canvas,
    Rect rect,
    ZoneColors colors, {
    required double fill,
    required double border,
  }) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas
      ..drawRRect(rrect, Paint()..color = _alpha(colors.accent, fill))
      ..drawRRect(
        RRect.fromRectAndRadius(rect.deflate(7), const Radius.circular(4)),
        Paint()
          ..color = _alpha(colors.accent, border)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  /// One painted direction marker, pointing along [angle].
  static void _chevron(
    Canvas canvas,
    Offset at,
    double angle,
    Color accent,
  ) {
    final paint = Paint()
      ..color = _alpha(accent, 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..save()
      ..translate(at.dx, at.dy)
      ..rotate(angle);
    for (var i = 0; i < 2; i++) {
      final x = i * 15.0;
      canvas.drawPath(
        Path()
          ..moveTo(x - 9, -11)
          ..lineTo(x + 2, 0)
          ..lineTo(x - 9, 11),
        paint,
      );
    }
    canvas.restore();
  }

  /// Returns [base] moved towards white (positive) or black (negative).
  static Color _shade(Color base, double amount) => Color.lerp(
    base,
    amount < 0 ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    amount.abs(),
  )!;

  /// Returns [color] with its alpha scaled by [factor].
  static Color _alpha(Color color, double factor) =>
      color.withValues(alpha: (color.a * factor).clamp(0, 1));

  /// A pure hash of [i] in the range 0..1.
  ///
  /// Not `Random`: the floor must be identical on every device and every
  /// launch. A texture that reshuffles itself is a texture nobody can
  /// screenshot, diff, or reason about.
  static double _noise(int i) {
    var h = (i * 374761393 + 668265263) & 0xFFFFFFFF;
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;
    return ((h ^ (h >> 16)) & 0xFFFF) / 0xFFFF;
  }
}
