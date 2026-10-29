import 'package:client/core/theme.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';

/// The reaction button and its picker, as the bottom dock.
///
/// Closed, it is a button in a card. Open, a short row of reactions rises
/// above it and folds away again the moment one is picked. That shape is
/// chosen because this is a **phone held in one hand while walking** — a
/// grid of twenty reactions is a thing you stop to read, and stopping is the
/// opposite of what an emote is for.
///
/// Since Phase 15 the card is also the dock: on a phone, [leading] and
/// [trailing] put the menu and Share in the same card, beside the reactions,
/// so the bottom corner opposite the joystick holds every control a thumb
/// reaches for and the top corners are left to the world.
///
/// The list of reactions comes from [EmoteKind] in `protocol/`, so the picker
/// cannot offer a reaction the server would refuse.
class EmoteBar extends StatefulWidget {
  /// Creates the bar.
  const EmoteBar({
    required this.onEmote,
    super.key,
    this.leading = const [],
    this.trailing = const [],
  });

  /// Called with the reaction the player picked.
  final void Function(EmoteKind emote) onEmote;

  /// Dock buttons before the reactions button.
  final List<Widget> leading;

  /// Dock buttons after the reactions button.
  final List<Widget> trailing;

  @override
  State<EmoteBar> createState() => _EmoteBarState();
}

class _EmoteBarState extends State<EmoteBar> {
  bool _open = false;

  void _pick(EmoteKind emote) {
    widget.onEmote(emote);
    // Closes on pick: one tap to open, one to react, and you are walking
    // again. Leaving it open turns a passing reaction into a mode.
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final buttons = [
      ...widget.leading,
      DockButton(
        icon: _open ? Icons.close : Icons.emoji_emotions_outlined,
        semanticLabel: _open ? 'Close reactions' : 'Reactions',
        // Lit while open, so the button reads as the thing the row above
        // belongs to.
        fill: _open ? ToyboxColors.sky : ToyboxColors.cream,
        onTap: () => setState(() => _open = !_open),
      ),
      ...widget.trailing,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.bottomLeft,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: HudChip(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final emote in EmoteKind.values)
                          _EmoteButton(
                            emote: emote,
                            onTap: () => _pick(emote),
                          ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        DecoratedBox(
          decoration: ToyboxShape.card(radius: 22),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, button) in buttons.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  button,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One reaction in the picker.
class _EmoteButton extends StatelessWidget {
  const _EmoteButton({required this.emote, required this.onTap});

  final EmoteKind emote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Padding(
        // Generous around a small glyph: the touch target has to survive a
        // thumb on a moving train, which is roughly the conference hallway.
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(emote.glyph, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}
