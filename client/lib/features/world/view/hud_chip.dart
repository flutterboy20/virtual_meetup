import 'package:client/core/theme.dart';
import 'package:flutter/material.dart';

/// The small translucent pill every on-screen HUD control is made of.
///
/// One widget, because the HUD floats over a moving, colourful world: a chip
/// that is a shade lighter than its neighbour reads as a different kind of
/// thing, and the player has to work out which. Consistency here is legibility,
/// not tidiness.
class HudChip extends StatelessWidget {
  /// Creates a chip.
  const HudChip({required this.child, super.key, this.onTap, this.padding});

  /// What sits inside the pill.
  final Widget child;

  /// Called when the pill is tapped, or `null` for a read-only chip.
  final VoidCallback? onTap;

  /// Overrides the default padding.
  final EdgeInsetsGeometry? padding;

  /// The pill's background, also used by panels that must match it.
  static const Color background = Color(0xB3101E26);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding:
              padding ??
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              color: AppTheme.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
