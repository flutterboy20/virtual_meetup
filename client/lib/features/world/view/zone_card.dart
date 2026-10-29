import 'package:client/core/app_fonts.dart';
import 'package:client/core/theme.dart';
import 'package:client/core/world_palette.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:client/game/world_hud.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';

/// Which room you are standing in, as a card in the top-left corner.
///
/// The minimap already answers this with a dot, but a dot in a 92px square
/// is a thing you have to look for. A room's name in its own colour is a
/// thing you read without looking — the way a sign over a doorway works.
///
/// Read off the minimap's frame, which already carries where you are: no new
/// sampling, no new notifier, nothing on the network. And only the *room*
/// is held, so walking across a room rebuilds nothing; the card changes
/// exactly when the room does.
///
/// No head-count. The server culls what each client hears to the people
/// nearby, so the client does not know how many are in a room, and a number
/// it made up from the beans in view would be wrong in every busy one.
class ZoneCard extends StatefulWidget {
  /// Creates the card for the world described by [spec].
  const ZoneCard({required this.frames, required this.spec, super.key});

  /// Where you are, a few times a second.
  final ValueListenable<MinimapFrame> frames;

  /// The world the frames are positions in.
  final MapSpec spec;

  @override
  State<ZoneCard> createState() => _ZoneCardState();
}

class _ZoneCardState extends State<ZoneCard> {
  WorldZone? _zone;

  WorldZone? _zoneOf(MinimapFrame frame) =>
      widget.spec.zoneAt(frame.you.dx, frame.you.dy);

  void _onFrame() {
    final zone = _zoneOf(widget.frames.value);
    if (zone != _zone) setState(() => _zone = zone);
  }

  @override
  void initState() {
    super.initState();
    _zone = _zoneOf(widget.frames.value);
    widget.frames.addListener(_onFrame);
  }

  @override
  void didUpdateWidget(ZoneCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frames != widget.frames) {
      oldWidget.frames.removeListener(_onFrame);
      widget.frames.addListener(_onFrame);
    }
    _zone = _zoneOf(widget.frames.value);
  }

  @override
  void dispose() {
    widget.frames.removeListener(_onFrame);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zone = _zone;
    // Between rooms — on a wall line, or before the first frame — the card
    // steps aside rather than naming the wrong one. It also steps aside in
    // the hall, for the reason the minimap does: the stage screen is the
    // width of the room, and a card in its top corner sits on the slides
    // people came in to read.
    if (zone == null || zone == WorldZone.hall) {
      return const SizedBox.shrink();
    }
    final colors = WorldPalette.of(zone);

    return Semantics(
      label: 'You are in the ${zone.label}',
      excludeSemantics: true,
      child: HudChip(
        padding: const EdgeInsets.fromLTRB(8, 7, 14, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: colors.floor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.accent, width: 2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              zone.label,
              style: const TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: ToyboxColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
