import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/world_palette.dart';
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
    final light = Paint()..color = _shade(colors.floor, 0.045);
    final dark = Paint()..color = _shade(colors.floor, -0.035);
    var row = 0;
    for (var y = rect.top; y < rect.bottom; y += step) {
      var col = 0;
      for (var x = rect.left; x < rect.right; x += step) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, step, step),
          (row + col).isEven ? light : dark,
        );
        col++;
      }
      row++;
    }
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

    // Wayfinding painted on the floor, pointing at each of the four arms.
    // The atrium is the only room where somebody genuinely does not know
    // which way to go, and a legend in a HUD corner is unreadable while
    // walking on a phone.
    _chevron(canvas, Offset(centre.dx, rect.top + 74), -math.pi / 2, accent);
    _chevron(canvas, Offset(centre.dx, rect.bottom - 74), math.pi / 2, accent);
    _chevron(canvas, Offset(rect.left + 74, centre.dy), math.pi, accent);
    _chevron(canvas, Offset(rect.right - 74, centre.dy), 0, accent);
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

    // The apron in front of the stage, where a speaker actually stands.
    _rug(
      canvas,
      Rect.fromLTRB(rect.left + 58, 156, rect.right - 58, 196),
      colors,
      fill: 0.13,
      border: 0.30,
    );
  }

  // ---- Sponsor row: expo carpet, an aisle runner, bay dividers ------------

  static void _sponsorRow(Canvas canvas, Rect rect, ZoneColors colors) {
    _weave(canvas, rect, colors, spacing: 12, strength: 0.035);

    // The aisle runs the length of the arm, between the two booth rows.
    _rug(
      canvas,
      Rect.fromLTRB(
        rect.left,
        rect.center.dy - 30,
        rect.right - 30,
        rect.center.dy + 30,
      ),
      colors,
      fill: 0.09,
      border: 0.22,
    );

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

  // ---- Food court: staggered street paving --------------------------------

  static void _foodCourt(Canvas canvas, Rect rect, ZoneColors colors) {
    const paverWidth = 75.0;
    const paverHeight = 50.0;
    final joint = Paint()
      ..color = _alpha(_shade(colors.floor, -0.34), 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    var index = 0;
    var row = 0;
    for (var y = rect.top; y < rect.bottom; y += paverHeight) {
      // Every other course is offset by half a paver — a running bond, which
      // is what a street outside a tea stall is actually laid in.
      final start = rect.left - (row.isEven ? 0 : paverWidth / 2);
      for (var x = start; x < rect.right; x += paverWidth) {
        final tone = (_noise(index) - 0.5) * 0.06;
        final paver = Rect.fromLTWH(x, y, paverWidth, paverHeight).deflate(1.2);
        canvas
          ..drawRect(paver, Paint()..color = _shade(colors.floor, tone))
          ..drawRect(paver, joint);
        index++;
      }
      row++;
    }
  }

  // ---- Code lab: raised anti-static floor ---------------------------------

  static void _codeLab(Canvas canvas, Rect rect, ZoneColors colors) {
    // The fine conductive weave, then the panel joints on top of it: a raised
    // computer-room floor is two grids at two scales, and drawing only the
    // coarse one reads as graph paper.
    _weave(canvas, rect, colors, spacing: 16, strength: 0.03);
    _grout(canvas, rect, tile, colors, strength: 0.42);

    // The lifting sockets at each panel corner. Tiny, and the single detail
    // that says "this floor is panels" rather than "this floor has lines".
    final socket = Paint()..color = _alpha(colors.accent, 0.20);
    for (var y = rect.top + tile; y < rect.bottom; y += tile) {
      for (var x = rect.left + tile; x < rect.right; x += tile) {
        canvas.drawCircle(Offset(x, y), 2.2, socket);
      }
    }
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

    // The walk in from the food court. It exists so the stepped deck at the
    // far end has something leading to it — stairs you arrive at by accident
    // read as decoration.
    final path = Rect.fromLTRB(248, rect.top, 332, rect.bottom - 96);
    canvas.drawRect(path, Paint()..color = _shade(colors.floor, 0.16));
    final slab = Paint()
      ..color = _alpha(_shade(colors.floor, -0.22), 0.45)
      ..strokeWidth = 1.5;
    for (var y = rect.top + 42; y < path.bottom; y += 42) {
      canvas.drawLine(Offset(path.left, y), Offset(path.right, y), slab);
    }
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
