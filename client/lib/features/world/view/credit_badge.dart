import 'dart:async';

import 'package:client/core/credits.dart';
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
  const CreditBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return HudChip(
      onTap: () => _showQr(context),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_2, size: 14, color: AppTheme.mutedInk),
          SizedBox(width: 6),
          Text(
            Credits.builtBy,
            style: TextStyle(
              color: AppTheme.mutedInk,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static void _showQr(BuildContext context) {
    // The sheet's future resolves when it is dismissed, and nothing here
    // cares which way it went.
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppTheme.surface,
        showDragHandle: true,
        builder: (context) => const _QrSheet(),
      ),
    );
  }
}

class _QrSheet extends StatelessWidget {
  const _QrSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
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
                data: Credits.repositoryUrl,
                size: 176,
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 14),
            // The URL in text as well as in the code: a QR nobody can read
            // with their eyes is a QR they have to trust blindly.
            const SelectableText(
              Credits.repositoryLabel,
              style: TextStyle(
                color: AppTheme.mutedInk,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
