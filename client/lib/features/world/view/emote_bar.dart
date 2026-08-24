import 'package:client/core/theme.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';

/// The reaction button and its picker.
///
/// Closed, it is one button. Open, it is a short row of reactions that fold
/// away again the moment one is picked. That shape is chosen because this is a
/// **phone held in one hand while walking** — a grid of twenty reactions is a
/// thing you stop to read, and stopping is the opposite of what an emote is
/// for.
///
/// The list of reactions comes from [EmoteKind] in `protocol/`, so the picker
/// cannot offer a reaction the server would refuse.
class EmoteBar extends StatefulWidget {
  /// Creates the bar.
  const EmoteBar({required this.onEmote, super.key});

  /// Called with the reaction the player picked.
  final void Function(EmoteKind emote) onEmote;

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.bottomLeft,
          child: _open
              ? HudChip(
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
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        HudChip(
          onTap: () => setState(() => _open = !_open),
          padding: const EdgeInsets.all(12),
          child: Icon(
            _open ? Icons.close : Icons.emoji_emotions_outlined,
            size: 22,
            color: _open ? AppTheme.mutedInk : AppTheme.ink,
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
