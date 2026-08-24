import 'package:flutter/material.dart';

/// The one place the app's colours and text styles are decided.
///
/// Kept small deliberately: this is a social toy for one weekend, not a design
/// system. What it does buy is that the lobby, the setup screen and the HUD
/// cannot drift into three different shades of "nearly the same blue".
abstract final class AppTheme {
  /// The brand blue everything else is derived from.
  static const Color seed = Color(0xFF0553B1);

  /// The page background behind every screen outside the game.
  static const Color background = Color(0xFF0B1A22);

  /// A raised surface: cards, fields, chips.
  static const Color surface = Color(0xFF13252F);

  /// The main text colour.
  static const Color ink = Color(0xFFEAF6FB);

  /// Text that is present but not the point.
  static const Color mutedInk = Color(0xFF9FB6C2);

  /// The colour of "this is working".
  static const Color good = Color(0xFF7ED9B6);

  /// The colour of "this needs your attention", used for validation messages
  /// and the reconnecting indicator alike.
  static const Color warn = Color(0xFFEAD37E);

  /// The colour of "this is wrong".
  static const Color bad = Color(0xFFE39A9A);

  /// The app's theme.
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(surface: background);

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
    );
  }
}
