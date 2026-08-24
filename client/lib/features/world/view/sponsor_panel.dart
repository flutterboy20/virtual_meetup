import 'package:client/core/sponsor.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:flutter/material.dart';

/// The card that opens when you walk up to a booth.
///
/// Proximity *is* the interaction. There is no tap, no "press E", no prompt:
/// walking up to something is the one verb this world has, and using it for
/// both "read a name" and "read a booth" means there is nothing to teach.
///
/// The animation is not decoration. Which booth is nearest changes as a
/// discrete jump, and a card that hard-cuts between two sponsors reads as a
/// glitch; a fade makes the same jump read as walking past a stand.
class SponsorPanel extends StatelessWidget {
  /// Creates the panel showing [sponsor], or nothing when it is `null`.
  const SponsorPanel({required this.sponsor, super.key});

  /// The booth to show, or `null` for none.
  final Sponsor? sponsor;

  /// The widest the card is allowed to get, in logical pixels.
  static const double maxWidth = 340;

  @override
  Widget build(BuildContext context) {
    final current = sponsor;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.18),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: current == null
          ? const SizedBox.shrink(key: ValueKey('no-sponsor'))
          : _Card(key: ValueKey(current.id), sponsor: current),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.sponsor, super.key});

  final Sponsor sponsor;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: SponsorPanel.maxWidth),
      child: Material(
        color: HudChip.background,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // The brand colour, used as a swatch rather than as the
                  // card's own background: a sponsor does not get to repaint
                  // the app's UI, and some brand colours are unreadable
                  // behind white text.
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: sponsor.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      sponsor.name,
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (sponsor.tagline.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  sponsor.tagline,
                  style: const TextStyle(
                    color: AppTheme.mutedInk,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
              if (sponsor.blurb.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  sponsor.blurb,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
