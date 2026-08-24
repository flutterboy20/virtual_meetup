import 'package:client/core/theme.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How many people are in the world right now.
///
/// The one number interest management deliberately hides. A player can see
/// nine beans and has no way to tell whether the event has twelve people in it
/// or three hundred — and "three hundred people are here" is most of why
/// walking into a busy room feels good. The server says it out loud about once
/// a second, and this is where it lands.
///
/// Fed by a `ValueNotifier`, not a Provider, and rebuilt on its own: this is
/// one small pill, and it must never be a reason to rebuild the screen.
class OnlineBadge extends StatelessWidget {
  /// Creates the badge over [online].
  const OnlineBadge({required this.online, super.key});

  /// The live head count.
  final ValueListenable<int> online;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: online,
      builder: (context, count, _) => HudChip(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_alt, size: 14, color: AppTheme.good),
            const SizedBox(width: 6),
            // "—" rather than "0" before the first stats message: zero people
            // are online is never true while you are looking at it.
            Text(count == 0 ? '—' : '$count'),
          ],
        ),
      ),
    );
  }
}
