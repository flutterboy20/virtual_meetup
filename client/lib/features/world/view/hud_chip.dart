import 'package:client/core/theme.dart';
import 'package:flutter/material.dart';

/// The card every on-screen HUD control is made of.
///
/// One widget, because the HUD floats over a moving, colourful world: a chip
/// that is a shade different from its neighbour reads as a different kind of
/// thing, and the player has to work out which. Consistency here is legibility,
/// not tidiness.
///
/// Phase 15 made it a toybox card: white, an ink outline and a hard ink
/// shadow with no blur. The old translucent dark pill was a grey smear over
/// the daylight floor at arm's length; a solid sticker on top of the world is
/// readable over any room in it, including the dark hall.
class HudChip extends StatelessWidget {
  /// Creates a chip.
  const HudChip({required this.child, super.key, this.onTap, this.padding});

  /// What sits inside the card.
  final Widget child;

  /// Called when the card is tapped, or `null` for a read-only chip.
  final VoidCallback? onTap;

  /// Overrides the default padding.
  final EdgeInsetsGeometry? padding;

  /// The card's corner radius.
  static const double radius = 16;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ToyboxShape.card(radius: radius),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Padding(
            padding:
                padding ??
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: IconTheme.merge(
              data: const IconThemeData(color: ToyboxColors.ink),
              child: DefaultTextStyle.merge(
                style: const TextStyle(
                  color: ToyboxColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One button inside the bottom dock: a cream square with an icon, and
/// optionally a word beside it.
///
/// No card of its own — the dock is the card — so a row of these reads as
/// one control with several buttons rather than as several stickers.
class DockButton extends StatelessWidget {
  /// Creates a dock button.
  const DockButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    super.key,
    this.label,
    this.iconColor = ToyboxColors.ink,
    this.fill = ToyboxColors.cream,
    this.badge,
  });

  /// The button's icon.
  final IconData icon;

  /// A word shown beside the icon, or `null` for an icon-only button.
  final String? label;

  /// What a screen reader calls the button.
  final String semanticLabel;

  /// Called when tapped.
  final VoidCallback? onTap;

  /// The icon's colour.
  final Color iconColor;

  /// The button's fill.
  final Color fill;

  /// A small second icon beside the first, for state worth showing.
  final Widget? badge;

  /// Height of every button in the dock. 46, over the 44 a thumb needs.
  static const double size = 46;

  @override
  Widget build(BuildContext context) {
    final word = label;
    final extra = badge;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: word == null,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: size,
              minHeight: size,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: word == null ? 0 : 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: iconColor),
                  if (extra != null) ...[const SizedBox(width: 4), extra],
                  if (word != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      word,
                      style: const TextStyle(
                        color: ToyboxColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
