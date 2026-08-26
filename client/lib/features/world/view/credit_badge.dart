import 'dart:async';

import 'package:client/core/credits.dart';
import 'package:client/core/open_link.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// The permanent "built by" line, and the QR behind it.
///
/// Always on screen, never in the way: a small pill in the corner, with the
/// QR one tap away rather than burnt into the HUD. A QR big enough to scan is
/// big enough to cover a bean, and this is a world people are walking around
/// in — so the badge is the affordance and the sheet is the payload.
///
/// The QR is generated locally by `qr_flutter`, not fetched as an image.
/// A remote QR is a network round trip, a third-party dependency at the exact
/// moment the wifi is worst, and a URL somebody else could change.
class CreditBadge extends StatelessWidget {
  /// Creates the badge.
  const CreditBadge({
    super.key,
    this.compact = false,
    this.githubLink = Credits.repositoryUrl,
  });

  /// Whether to drop the line and keep only the QR mark.
  ///
  /// On a phone this badge and the chips opposite it were closing over the
  /// middle of the screen, which is where the rooms keep their boards and
  /// signs. The mark alone is still a tappable target and still says "there
  /// is a code behind this"; the name it was carrying is on the sheet the tap
  /// opens, one line further in.
  final bool compact;

  /// Where the QR — and the link under it — point.
  ///
  /// Passed down from the live config rather than watched here, for the same
  /// reason the projector's line is: this widget sits inside a `Stack` over a
  /// `GameWidget`, and the screen around it already holds the config the
  /// server last pushed. Defaults to [Credits.repositoryUrl] so the badge
  /// still works on its own in a test.
  final String githubLink;

  @override
  Widget build(BuildContext context) {
    return HudChip(
      onTap: () => _showQr(context, githubLink),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Semantics(
        button: true,
        label: Credits.builtBy,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, size: 14, color: AppTheme.mutedInk),
            if (!compact) ...[
              const SizedBox(width: 6),
              const Text(
                Credits.builtBy,
                style: TextStyle(
                  color: AppTheme.mutedInk,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static void _showQr(BuildContext context, String link) {
    // The sheet's future resolves when it is dismissed, and nothing here
    // cares which way it went.
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppTheme.surface,
        showDragHandle: true,
        builder: (context) => _QrSheet(link: link),
      ),
    );
  }
}

class _QrSheet extends StatelessWidget {
  const _QrSheet({required this.link});

  /// The repository this sheet is offering, two ways.
  final String link;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Scrollable, because the sheet is capped at half the screen and this
      // column is a fixed 176-pixel QR plus four lines. On a phone held
      // sideways at a conference — which is how half of them are held — the
      // cap lands under the content, and a sheet that scrolls shows a
      // squeezed code rather than a black-and-yellow overflow bar.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              Credits.builtBy,
              style: TextStyle(
                color: AppTheme.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'This world is open source. Scan to read how it works.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.mutedInk, fontSize: 12),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                // A QR needs a light quiet zone around it or half the phones
                // in the room will not lock onto it in a dark hall.
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: link,
                size: 176,
                padding: EdgeInsets.zero,
                // Named, not "qr code". A screen reader announcing the
                // destination is the same courtesy the printed line below
                // pays to everybody else: what this leads to, before you
                // commit to following it.
                semanticsLabel: 'QR code for ${Credits.linkLabel(link)}',
              ),
            ),
            const SizedBox(height: 14),
            // The URL in text as well as in the code, and tappable: a QR
            // nobody can read with their eyes is a QR they have to trust
            // blindly, and the person holding the phone that is *showing*
            // this sheet cannot scan it with the same phone. Tapping is the
            // only way in for them.
            Semantics(
              button: true,
              link: true,
              label: 'Open the repository',
              child: InkWell(
                onTap: () => unawaited(openLink(link)),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          Credits.linkLabel(link),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.good,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: AppTheme.good,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.open_in_new,
                        size: 13,
                        color: AppTheme.good,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
