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
    this.width = deskWidth,
    super.key,
  });

  /// Width of the map on a screen with room to spare, in logical pixels.
  static const double deskWidth = 116;

  /// Width of the map on a phone.
  ///
  /// Smaller because it is sharing the top-right corner with the world: the
  /// rooms have boards and signs on their north walls, the camera holds the
  /// player in the middle, and so those boards land under exactly this chip.
  /// Two rooms and a scattering of dots survive the loss of 24 pixels.
  static const double phoneWidth = 92;

  /// How wide to draw the map, in logical pixels.

  final double width;

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

/// The minimap, hidden while you are standing in the conference hall.
///
/// **One room, not all of them.** Every room in the conference hangs its
/// signage on its north wall and the camera holds you in the middle of the
/// screen, so anything in a top corner is over *something* — but only the
/// hall's screen is the width of the room, the thing people are in there to
/// read, and the place a crowd stands still long enough to mind. Everywhere
/// else you are walking past a sign, and a map that blinked out in six rooms
/// would be a map nobody trusts to be there.
///
/// It reads the room off the minimap's own frame, which already carries where
/// you are standing, so this costs no new sampling, no new notifier and
/// nothing on the network. On a map with no hall — the beach — [MapSpec] has
/// no such zone and this is always the plain chip.
///
/// Collapsed rather than faded: an invisible widget that still holds its
/// corner would give back none of the space this exists to give back.
class HallAwareMinimap extends StatelessWidget {
  /// Creates a minimap of [spec] that steps aside inside the hall.
  const HallAwareMinimap({
    required this.frames,
    required this.spec,
    required this.width,
    super.key,
  });

  /// Where the dots come from, and where you are.
  final ValueListenable<MinimapFrame> frames;

  /// Which world this is a map of.
  final MapSpec spec;

  /// How wide to draw it when it is drawn at all.
  final double width;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MinimapFrame>(
      valueListenable: frames,
      builder: (context, frame, child) {
        final inHall =
            spec.zoneAt(frame.you.dx, frame.you.dy) == WorldZone.hall;
        // `child` is the built minimap, handed back unbuilt on every frame
        // that only moved a dot. Walking across a room must not rebuild a
        // `CustomPaint` twice.
        return inHall ? const SizedBox.shrink() : child!;
      },
      child: Minimap(frames: frames, spec: spec, width: width),
    );
  }
}
