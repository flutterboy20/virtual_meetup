import 'package:client/core/theme.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:client/services/connection_supervisor.dart';
import 'package:client/services/reconnect_policy.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shows whether the client is talking to the server.
///
/// Small and calm on purpose. A dropped socket is not an error screen and not
/// a modal: the player's own bean keeps walking, because it always owned its
/// own position, and this chip is the only thing that changes. Bouncing
/// somebody to the lobby because their phone lost wifi for four seconds is
/// the failure Phase 4 exists to prevent.
class ConnectionChip extends StatelessWidget {
  /// Creates the chip.
  const ConnectionChip({super.key, this.compact = false});

  /// Whether to drop the word while the socket is healthy.
  ///
  /// "Connected" is the one state nobody needs telling about, and on a phone
  /// it was the widest thing in the top-left corner — sitting over the left
  /// end of whatever board the player had walked up to. Every other phase
  /// keeps its words: "Reconnecting…" is exactly the moment a green dot is
  /// not enough.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final phase = context.watch<ConnectionSupervisor>().phase;
    final quiet = compact && phase == ConnectionPhase.connected;

    return HudChip(
      child: Semantics(
        label: labelFor(phase),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor(phase), size: 16, color: colorFor(phase)),
            if (!quiet) ...[
              const SizedBox(width: 6),
              Text(labelFor(phase)),
            ],
          ],
        ),
      ),
    );
  }

  /// The icon this phase is drawn with, shared with the phone's menu button.
  static IconData iconFor(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.connected => Icons.cloud_done,
    ConnectionPhase.connecting => Icons.cloud_sync,
    ConnectionPhase.waiting || ConnectionPhase.reconnecting => Icons.cloud_sync,
    ConnectionPhase.idle => Icons.cloud_queue,
  };

  /// The colour this phase is drawn in.
  static Color colorFor(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.connected => AppTheme.good,
    ConnectionPhase.connecting => AppTheme.warn,
    ConnectionPhase.waiting || ConnectionPhase.reconnecting => AppTheme.warn,
    ConnectionPhase.idle => AppTheme.mutedInk,
  };

  /// What this phase is called, in words.
  static String labelFor(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.connected => 'Connected',
    ConnectionPhase.connecting => 'Connecting…',
    // One word for the whole waiting-then-retrying cycle, so it does not
    // flicker between two labels once a second while the backoff runs.
    ConnectionPhase.waiting || ConnectionPhase.reconnecting => 'Reconnecting…',
    ConnectionPhase.idle => 'Offline',
  };
}
