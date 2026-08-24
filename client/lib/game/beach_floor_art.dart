import 'dart:ui';

import 'package:client/core/world_palette.dart';
import 'package:protocol/protocol.dart';

/// The beach's floor textures: deck planks, sand, and the sea bed.
///
/// The beach's answer to `ZoneFloorArt`, and deliberately a separate file
/// rather than three more cases in that one. Both are recorded once into the
/// floor's `Picture`, so the split costs nothing at runtime, and neither venue
/// has to be read past to understand the other.
///
/// Every texture here is a value ladder before it is a hue: dark planks,
/// bright sand, deep water. That is what makes the three bands readable on a
/// phone held at arm's length in the sun, where hue is the first thing to go.
abstract final class BeachFloorArt {
  /// How wide one deck plank is, in world units.
  static const double plankWidth = 46;

  /// How far apart the sand's ripples run, in world units.
  static const double rippleSpacing = 34;

  /// Paints a **beach** zone's texture inside [rect]. The caller owns the
  /// clip, and a zone from another map draws nothing.
  static void paint(Canvas canvas, WorldZone zone, Rect rect) {
    final colors = WorldPalette.of(zone);
    switch (zone) {
      case WorldZone.beachBoardwalk:
        _boardwalk(canvas, rect, colors);
      case WorldZone.beachSand:
        _sand(canvas, rect, colors);
      case WorldZone.beachSea:
        _seaBed(canvas, rect, colors);
      case _:
        break;
    }
  }

  /// Deck planks running **across** the boardwalk, with a nosing at the front.
  ///
  /// Across rather than along, so the grain runs the way you walk and the eye
  /// has something to measure movement against. Every third plank is shaded a
  /// little differently off a pure hash, which is what stops 26 identical
  /// rectangles reading as a barcode.
  static void _boardwalk(Canvas canvas, Rect rect, ZoneColors colors) {
    var index = 0;
    for (var x = rect.left; x < rect.right; x += plankWidth) {
      canvas
        ..drawRect(
          Rect.fromLTRB(x, rect.top, x + plankWidth - 2, rect.bottom),
          Paint()..color = _shade(colors.floor, (_noise(index) - 0.5) * 0.13),
        )
        // The gap between two planks, which is what makes them planks.
        ..drawRect(
          Rect.fromLTRB(
            x + plankWidth - 2,
            rect.top,
            x + plankWidth,
            rect.bottom,
          ),
          Paint()..color = _shade(colors.floor, -0.30),
        );
      index++;
    }

    // The nosing: the lip of the deck where it meets the sand. One stroke,
    // and it is the single cue that says the boardwalk is *raised*.
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.bottom - 7, rect.right, rect.bottom),
      Paint()..color = _shade(colors.floor, -0.22),
    );
  }

  /// Dry sand: a warm wash, wind ripples, and a scatter of shell flecks.
  ///
  /// The ripples are shallow arcs rather than straight lines, because sand
  /// that ripples in straight lines reads as corduroy.
  static void _sand(Canvas canvas, Rect rect, ZoneColors colors) {
    final ripple = Paint()
      ..color = _shade(colors.floor, -0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    var index = 0;
    for (var y = rect.top + 12; y < rect.bottom; y += rippleSpacing) {
      final path = Path()..moveTo(rect.left, y);
      final wobble = 5 + _noise(index) * 5;
      for (var x = rect.left; x < rect.right; x += 90) {
        path
          ..quadraticBezierTo(
            x + 22,
            y + (index.isEven ? wobble : -wobble),
            x + 45,
            y,
          )
          ..quadraticBezierTo(
            x + 67,
            y + (index.isEven ? -wobble : wobble),
            x + 90,
            y,
          );
      }
      canvas.drawPath(path, ripple);
      index++;
    }

    // Shells and dry weed. Fifty specks, on a pure hash so the beach is
    // identical on every device and every launch — a texture that reshuffles
    // itself is one nobody can screenshot, diff, or reason about.
    final fleck = Paint()..color = _shade(colors.floor, 0.22);
    for (var i = 0; i < 50; i++) {
      final x = rect.left + _noise(i * 3) * rect.width;
      final y = rect.top + _noise(i * 3 + 1) * rect.height;
      canvas.drawCircle(Offset(x, y), 1.4 + _noise(i * 3 + 2) * 1.6, fleck);
    }

    // The tideline: where the last wave reached, just above the water.
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.bottom - 16, rect.right, rect.bottom),
      Paint()..color = _shade(colors.floor, -0.12),
    );
  }

  /// The sea bed, which is almost entirely hidden under live water.
  ///
  /// Almost, not entirely: the rim shows through where `WaterComponent`'s
  /// rounded corners do not cover the rect, and the deep end shows through the
  /// gradient. So it is a darkening towards the bottom of the map and nothing
  /// else — detail here would be work nobody ever sees.
  static void _seaBed(Canvas canvas, Rect rect, ZoneColors colors) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [_shade(colors.floor, 0.10), _shade(colors.floor, -0.22)],
        ),
    );
  }

  /// Returns [base] moved towards white (positive) or black (negative).
  static Color _shade(Color base, double amount) => Color.lerp(
    base,
    amount < 0 ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    amount.abs(),
  )!;

  /// A pure hash of [i] in the range 0..1.
  ///
  /// The same function `ZoneFloorArt` uses, and here for the same reason: the
  /// floor must be identical on every device and every launch.
  static double _noise(int i) {
    var h = (i * 374761393 + 668265263) & 0xFFFFFFFF;
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;
    return ((h ^ (h >> 16)) & 0xFFFF) / 0xFFFF;
  }
}
