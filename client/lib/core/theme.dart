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
  static ThemeData get dark => _build(
    scheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(surface: background),
    typography: Typography.whiteMountainView,
    ink: ink,
  );

  /// The front door's theme: a paper ground and a badge on a lanyard.
  ///
  /// Light, because the world behind the door is a daylight venue — the old
  /// dark lobby put players through a night-to-day jump the moment they
  /// tapped Join. Same two faces and the same split between them as [dark];
  /// only the ground and the ink change.
  static ThemeData get lanyard => _build(
    scheme: ColorScheme.fromSeed(seedColor: seed).copyWith(
      primary: LanyardColors.blue,
      onPrimary: LanyardColors.badge,
      surface: LanyardColors.paper,
      onSurface: LanyardColors.ink,
    ),
    typography: Typography.blackMountainView,
    ink: LanyardColors.ink,
  );

  /// Builds a theme on [scheme], with every text slot inked in [ink].
  ///
  /// One builder for both themes, so the rule about which face goes on which
  /// slot is written once and cannot be true on one screen and not another.
  static ThemeData _build({
    required ColorScheme scheme,
    required TextTheme typography,
    required Color ink,
  }) {
    final base = typography.apply(
      fontFamily: AppFonts.text,
      bodyColor: ink,
      displayColor: ink,
    );

    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
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

/// The colours of the front door: a conference badge on a lanyard.
///
/// Printed-matter colours rather than screen colours — paper, ink, the
/// brand blue of the badge header and the yellow of venue wayfinding — so
/// the door reads as a thing you were handed at registration.
abstract final class LanyardColors {
  /// The ground behind the badge: off-white paper, not screen white, so the
  /// white badge card stands off it.
  static const Color paper = Color(0xFFEFEBE2);

  /// The badge card itself.
  static const Color badge = Color(0xFFFFFFFF);

  /// Text, outlines and the wayfinding signs.
  static const Color ink = Color(0xFF111418);

  /// Labels that are present but not the point ("HELLO, MY NAME IS").
  static const Color mutedInk = Color(0xFF5A616B);

  /// The badge header and the primary button. The same blue as
  /// [AppTheme.seed], so the brand is one colour in both themes.
  static const Color blue = AppTheme.seed;

  /// Wayfinding yellow: the arrows on the hall signs.
  static const Color signal = Color(0xFFFFD23F);

  /// "This needs your attention", on paper or on the badge.
  ///
  /// Not [AppTheme.warn]: that pale yellow was picked for a dark ground and
  /// all but vanishes on white.
  static const Color alert = Color(0xFFB3261E);
}

/// Text styles that only the front door uses.
///
/// Everything else on the door comes from [AppTheme.lanyard]'s text theme;
/// these are the two signage voices Material's scale has no slot for.
abstract final class LanyardText {
  /// Small, spaced capitals: "HELLO, MY NAME IS", "CHOOSE YOUR HALL".
  static const TextStyle eyebrow = TextStyle(
    fontFamily: AppFonts.text,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
    color: LanyardColors.mutedInk,
  );

  /// A hall sign's destination: "CONFERENCE", "BEACH".
  ///
  /// Bold, not black: 700 is the heaviest Archivo cut that is bundled, and a
  /// weight that is not bundled is one the browser fakes by smearing.
  static const TextStyle sign = TextStyle(
    fontFamily: AppFonts.text,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: LanyardColors.signal,
  );
}

/// The colours of the HUD inside the world: chunky, sticker-like cards over
/// the daylight floor.
abstract final class ToyboxColors {
  /// The warm cream behind dock buttons and other quiet surfaces.
  static const Color cream = Color(0xFFFFF4E0);

  /// Every card's fill.
  static const Color card = Color(0xFFFFFFFF);

  /// Outlines, offset shadows and the main text.
  static const Color ink = Color(0xFF1B2730);

  /// Secondary text on a card.
  static const Color mutedInk = Color(0xFF56636D);

  /// The one action colour: the joystick knob and a card's main button.
  static const Color sky = Color(0xFF54C5F8);

  /// The darker edge of [sky], for rings drawn around it.
  static const Color skyEdge = Color(0xFF1F7BA6);

  /// "This is working", on a white card: the socket, the head-count.
  ///
  /// Darker than [AppTheme.good], which was mixed to glow on a dark pill and
  /// washes out to nothing on white.
  static const Color good = Color(0xFF1B7F52);

  /// "This needs your attention", on a white card.
  static const Color warn = Color(0xFFA35400);

  /// "This is wrong" or "this cannot be undone", on a white card.
  static const Color bad = Color(0xFFC0362C);
}

/// The shape every HUD card shares.
///
/// The shadow is a solid ink slab with no blur. A blurred shadow is a soft
/// grey smear on the light floor at arm's length; a hard one reads as a
/// sticker sitting on top of the world, which is the whole look.
abstract final class ToyboxShape {
  /// Outline width.
  static const double border = 2.5;

  /// How far the hard shadow drops below a card.
  static const double shadowDrop = 4;

  /// Corner radius of a card.
  static const double radius = 18;

  /// The decoration of a HUD card with corners of [radius].
  static BoxDecoration card({double radius = ToyboxShape.radius}) =>
      BoxDecoration(
        color: ToyboxColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: ToyboxColors.ink, width: border),
        boxShadow: const [
          BoxShadow(color: ToyboxColors.ink, offset: Offset(0, shadowDrop)),
        ],
      );
}
