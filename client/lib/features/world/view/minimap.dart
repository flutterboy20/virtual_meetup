import 'package:client/core/world_palette.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:client/game/world_hud.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';

/// The always-visible map in the corner.
///
/// Zones as colour blocks, a dot per nearby player, and a bigger marker for
/// you. Deliberately **dots only** — no beans, no names, no furniture. A
/// minimap that tries to be a small version of the world becomes an unreadable
/// smudge at 110 pixels wide and costs a second render of everything.
///
/// It answers exactly two questions, which are the only two a player has:
/// "which room am I in?" and "is there anybody over there?"
///
/// It repaints from a [MinimapFrame] the game samples a few times a second,
/// not from the game loop. Sixty rebuilds a second to move a dot by a third of
/// a pixel is the single easiest way to spend the frame budget on nothing.
class Minimap extends StatelessWidget {
  /// Creates a minimap of [spec] fed by [frames].
  const Minimap({
    required this.frames,
    this.spec = MapSpec.conference,
    super.key,
  });

  /// Width of the map, in logical pixels.
  static const double width = 116;

  /// Which world this is a map of.
  ///
  /// Its dimensions and its zones both come from here since Phase 10, so the
  /// chip is the right shape on a 1200x900 beach without a second widget.
  final MapSpec spec;

  /// Where the dots come from.
  final ValueListenable<MinimapFrame> frames;

  /// The chip's aspect, matching the world's bounding box.
  double get aspect => spec.width / spec.height;

  @override
  Widget build(BuildContext context) {
    return HudChip(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: width,
        height: width / aspect,
        child: ValueListenableBuilder<MinimapFrame>(
          valueListenable: frames,
          builder: (context, frame, _) =>
              CustomPaint(painter: _MinimapPainter(frame, spec)),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  const _MinimapPainter(this.frame, this.spec);

  final MinimapFrame frame;
  final MapSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / spec.width;
    final scaleY = size.height / spec.height;

    // The ground the venue sits on, so the two void corners read as outside
    // the building rather than as two holes in the map.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = WorldPalette.outside,
    );

    for (final zone in spec.zones) {
      final rect = zone.rect;
      canvas.drawRect(
        Rect.fromLTRB(
          rect.left * scaleX,
          rect.top * scaleY,
          rect.right * scaleX,
          rect.bottom * scaleY,
        ),
        // The zone's own **floor** colour, at full strength. Before the
        // daylight rebase this drew a washed-out accent, because seven dark
        // floors were seven shades of the same dark at 116 pixels wide. Light
        // floors do not have that problem, so the honest mapping — the map is
        // painted in the colours the room is painted in — is now also the
        // readable one.
        Paint()..color = WorldPalette.of(zone).floor,
      );
    }

    // Two circles per dot, not one. The hall is deliberately still a dark
    // room in a light world, so a single flat dot is invisible in exactly one
    // place — and "everyone vanishes when they walk into the auditorium" is
    // the kind of bug that only shows up on the day.
    final halo = Paint()..color = WorldPalette.othersHalo;
    final others = Paint()..color = WorldPalette.others;
    for (final dot in frame.others) {
      final at = Offset(dot.dx * scaleX, dot.dy * scaleY);
      canvas
        ..drawCircle(at, 2.7, halo)
        ..drawCircle(at, 1.7, others);
    }

    // You, last and larger, with a dark ring so you are findable even when
    // standing in the middle of a crowd of dots.
    final you = Offset(frame.you.dx * scaleX, frame.you.dy * scaleY);
    canvas
      ..drawCircle(you, 4.6, Paint()..color = const Color(0xE60B1A22))
      ..drawCircle(you, 3, Paint()..color = WorldPalette.you);
  }

  @override
  bool shouldRepaint(_MinimapPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.spec != spec;
}
