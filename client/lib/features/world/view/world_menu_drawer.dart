import 'package:client/core/app_version.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/world/view/connection_chip.dart';
import 'package:client/features/world/view/credit_badge.dart';
import 'package:client/features/world/view/online_badge.dart';
import 'package:client/game/joystick_side.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';

/// Everything the HUD says but does not need to say *while you are walking*.
///
/// On a laptop the whole HUD fits in two columns with the world still visible
/// between them. On a phone in portrait it does not: the same eight controls
/// close over the middle of the screen, which is where the boards, the stage
/// and the other beans are. So the phone keeps only what a thumb uses in the
/// moment — the minimap, the emotes, the joystick and the door to the other
/// world — and everything else moves in here, one tap away.
///
/// The other world is deliberately in **both** places. It is the one control
/// that is both a thing you reach for mid-walk and a thing you look for in a
/// menu, and a duplicated door costs one chip.
class WorldMenuDrawer extends StatelessWidget {
  /// Creates the drawer.
  const WorldMenuDrawer({
    required this.playerName,
    required this.online,
    required this.githubLink,
    required this.joystickSide,
    required this.onToggleJoystick,
    required this.onShare,
    super.key,
    this.otherMap,
    this.onSwitchMap,
    this.onEditIdentity,
    this.onLogout,
    this.boothsFailed = false,
  });

  /// The name this device is walking around under.
  final String playerName;

  /// The live head count, straight from the HUD notifier.
  final ValueListenable<int> online;

  /// Where the credit badge's QR points.
  final String githubLink;

  /// Which side the joystick is on right now.
  final JoystickSide joystickSide;

  /// Called to move the joystick to the other thumb.
  final VoidCallback onToggleJoystick;

  /// Called when the player asks to pass this world's link on.
  final VoidCallback onShare;

  /// The world this drawer offers to walk into, or `null` if there is none.
  final MapId? otherMap;

  /// Called with [otherMap] when the player takes that offer.
  final void Function(MapId map)? onSwitchMap;

  /// Called when the player asks to change their name or bean.
  final VoidCallback? onEditIdentity;

  /// Called when the player asks to be forgotten by this device.
  final VoidCallback? onLogout;

  /// Whether the booth config failed to load.
  final bool boothsFailed;

  /// Closes the drawer, then runs [action].
  ///
  /// Closing first, always: half of these tear this screen down — a switch
  /// rebuilds the world under a new key, a log out walks back to the welcome
  /// screen — and a route that is popped after its own subtree has gone is a
  /// crash rather than an animation.
  void _close(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final map = otherMap;
    final switchMap = onSwitchMap;

    return Drawer(
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const ConnectionChip(),
                        OnlineBadge(online: online),
                      ],
                    ),
                  ),
                  if (boothsFailed)
                    const ListTile(
                      leading: Icon(
                        Icons.storefront_outlined,
                        color: AppTheme.warn,
                      ),
                      title: Text(
                        'Booths unavailable',
                        style: TextStyle(color: AppTheme.ink, fontSize: 14),
                      ),
                      subtitle: Text(
                        'The world opened without them.',
                        style: TextStyle(
                          color: AppTheme.mutedInk,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const Divider(color: AppTheme.mutedInk, height: 1),
                  _MenuTile(
                    icon: Icons.ios_share,
                    label: 'Share this world',
                    detail: 'Send the link to somebody at the event.',
                    onTap: () => _close(context, onShare),
                  ),
                  _MenuTile(
                    icon: Icons.swap_horiz,
                    label: 'Joystick: ${joystickSide.label}',
                    detail: 'Tap to move it to your other thumb.',
                    onTap: () => _close(context, onToggleJoystick),
                  ),
                  if (map != null && switchMap != null)
                    _MenuTile(
                      icon: Icons.explore_outlined,
                      label: 'Go to ${map.label}',
                      onTap: () => _close(context, () => switchMap(map)),
                    ),
                  if (onEditIdentity != null)
                    _MenuTile(
                      icon: Icons.face_retouching_natural,
                      label: playerName,
                      detail: 'Change your name or your bean.',
                      onTap: () => _close(context, onEditIdentity!),
                    ),
                  if (onLogout != null)
                    _MenuTile(
                      icon: Icons.logout,
                      label: 'Log out',
                      color: AppTheme.bad,
                      onTap: () => _close(context, onLogout!),
                    ),
                ],
              ),
            ),
            // The credit is the only thing in here that is not a control, so
            // it sits under a rule at the foot of the drawer rather than in
            // among the taps — where a colophon goes on a page.
            const Divider(color: AppTheme.mutedInk, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  CreditBadge(githubLink: githubLink),
                  const SizedBox(height: 8),
                  // Which build this phone is actually running. The drawer is
                  // the only screen a player can reach at any moment without
                  // leaving the world, which makes it the one place a version
                  // is worth asking somebody to read out over a noisy room.
                  Text(
                    appVersionLabel(),
                    style: const TextStyle(
                      color: AppTheme.mutedInk,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of the drawer: an icon, a line, and an optional line under it.
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.color = AppTheme.ink,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: detail == null
          ? null
          : Text(
              detail,
              style: const TextStyle(color: AppTheme.mutedInk, fontSize: 12),
            ),
    );
  }
}
