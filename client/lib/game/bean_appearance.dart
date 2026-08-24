import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show Color, HSLColor;
import 'package:protocol/protocol.dart';

/// Everything that makes one bean look different from another.
///
/// The cosmetic enum ([PlayerCosmetic]) comes from `protocol/` rather than
/// being redeclared here: a bean's look travels on the wire, and two copies
/// of the same enum is exactly how a client and a server drift apart.
///
/// Phase 4's lobby will build this from the player's picks; for now the
/// client hard-codes one value. Keeping the look behind a value object means
/// neither that nor the network touches the drawing code.
@immutable
class BeanAppearance {
  /// Creates an appearance.
  const BeanAppearance({
    this.bodyColor = defaultBodyColor,
    this.cosmetic = PlayerCosmetic.none,
    this.cosmeticColor = defaultCosmeticColor,
  });

  /// Creates the appearance of a player described by the server.
  ///
  /// The wire carries one colour per player, so the cosmetic is tinted from
  /// the body colour instead of costing a second field on every join.
  factory BeanAppearance.fromPlayer(PlayerState player) {
    final body = Color(player.color);
    return BeanAppearance(
      bodyColor: body,
      cosmetic: player.cosmetic,
      cosmeticColor: darken(body, 0.34),
    );
  }

  /// Body colour used when none is chosen.
  static const Color defaultBodyColor = Color(0xFF7ED9B6);

  /// Cosmetic colour used when none is chosen.
  static const Color defaultCosmeticColor = Color(0xFF2E4C5A);

  /// Fill colour of the bean's body.
  final Color bodyColor;

  /// The cosmetic worn on the head.
  final PlayerCosmetic cosmetic;

  /// Fill colour of the cosmetic.
  final Color cosmeticColor;

  /// Returns [color] with its lightness reduced by [amount].
  ///
  /// Used for the body's edge line and for tinting a remote player's
  /// cosmetic, so both stay in the same hue family as the body.
  static Color darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness - amount).clamp(0, 1)).toColor();
  }
}
