import 'package:client/core/app_fonts.dart';
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
  ///
  /// Two faces, split by job rather than by size: [AppFonts.display] on the
  /// three display and three headline slots, [AppFonts.text] on everything
  /// else. Material's own scale is what decides which is which, so a widget
  /// asking for `headlineMedium` gets the characterful face without knowing
  /// there are two of them.
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(surface: background);

    final base = Typography.whiteMountainView.apply(
      fontFamily: AppFonts.text,
      bodyColor: ink,
      displayColor: ink,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      // Also set on the theme itself, not only on the text theme: anything
      // that builds a style from scratch rather than from the scale — a
      // `TextStyle` written inline, of which this app has plenty — inherits
      // from here.
      fontFamily: AppFonts.text,
      textTheme: base.copyWith(
        displayLarge: _display(base.displayLarge),
        displayMedium: _display(base.displayMedium),
        displaySmall: _display(base.displaySmall),
        headlineLarge: _display(base.headlineLarge),
        headlineMedium: _display(base.headlineMedium),
        headlineSmall: _display(base.headlineSmall),
      ),
    );
  }

  /// Puts [style] in the display face, tightened.
  ///
  /// Negative tracking, because Bricolage at a heading size sets loose by
  /// default and a wordmark wants its letters holding on to each other.
  static TextStyle? _display(TextStyle? style) => style?.copyWith(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );
}
