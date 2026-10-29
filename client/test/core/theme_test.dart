import 'package:client/core/app_fonts.dart';
import 'package:client/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the type system', () {
    test('body copy is set in the text face', () {
      final theme = AppTheme.dark;

      expect(theme.textTheme.bodyMedium?.fontFamily, equals(AppFonts.text));
      expect(theme.textTheme.labelSmall?.fontFamily, equals(AppFonts.text));
    });

    test('headings are set in the display face', () {
      // The split is by Material's own slot, not by size, so a widget asking
      // for `headlineMedium` gets the characterful face without knowing there
      // are two of them.
      final theme = AppTheme.dark;

      expect(
        theme.textTheme.displayLarge?.fontFamily,
        equals(AppFonts.display),
      );
      expect(
        theme.textTheme.headlineSmall?.fontFamily,
        equals(AppFonts.display),
      );
    });

    test('a style written from scratch still lands in the text face', () {
      // The app writes plenty of inline `TextStyle`s that name no family.
      // Without the family on the theme itself they would fall back to the
      // platform default and quietly reintroduce a third font.
      expect(
        AppTheme.dark.textTheme.titleMedium?.fontFamily,
        equals(AppFonts.text),
      );
    });

    test('the two faces are not the same one', () {
      expect(AppFonts.display, isNot(equals(AppFonts.text)));
    });

    test('every colour the app names is opaque', () {
      // Nothing here is meant to be a tint over something else; a colour that
      // lost its alpha would show up as a washed-out screen, not an error.
      for (final color in [
        AppTheme.background,
        AppTheme.surface,
        AppTheme.ink,
        AppTheme.mutedInk,
        AppTheme.good,
        AppTheme.warn,
        AppTheme.bad,
      ]) {
        expect(color.a, equals(1.0), reason: '$color');
      }
    });
  });

  group('the lanyard theme', () {
    test('is light, on paper', () {
      final theme = AppTheme.lanyard;

      expect(theme.brightness, equals(Brightness.light));
      expect(theme.scaffoldBackgroundColor, equals(LanyardColors.paper));
    });

    test('splits the two faces the same way the dark theme does', () {
      final theme = AppTheme.lanyard;

      expect(theme.textTheme.bodyMedium?.fontFamily, equals(AppFonts.text));
      expect(
        theme.textTheme.headlineSmall?.fontFamily,
        equals(AppFonts.display),
      );
    });

    test('inks its text in the lanyard ink, not the dark theme ink', () {
      // A light theme that kept the dark theme's pale ink would be white text
      // on paper: present, and unreadable.
      expect(
        AppTheme.lanyard.textTheme.bodyMedium?.color,
        equals(LanyardColors.ink),
      );
    });

    test('keeps the brand blue the same in both themes', () {
      expect(LanyardColors.blue, equals(AppTheme.seed));
      expect(AppTheme.lanyard.colorScheme.primary, equals(AppTheme.seed));
    });

    test('signage styles stay within the bundled weights', () {
      // Archivo is bundled at 400, 500 and 700 only.
      for (final style in [LanyardText.eyebrow, LanyardText.sign]) {
        expect(style.fontFamily, equals(AppFonts.text));
        expect(
          style.fontWeight!.value,
          lessThanOrEqualTo(FontWeight.w700.value),
        );
      }
    });
  });

  group('the toybox card', () {
    test('has an ink outline and a hard, unblurred shadow', () {
      final card = ToyboxShape.card();
      final border = card.border! as Border;

      expect(card.color, equals(ToyboxColors.card));
      expect(border.top.color, equals(ToyboxColors.ink));
      expect(border.top.width, equals(ToyboxShape.border));
      expect(card.boxShadow, hasLength(1));
      expect(card.boxShadow!.single.blurRadius, equals(0));
      expect(
        card.boxShadow!.single.offset,
        equals(const Offset(0, ToyboxShape.shadowDrop)),
      );
    });

    test('takes a corner radius', () {
      expect(
        ToyboxShape.card(radius: 26).borderRadius,
        equals(BorderRadius.circular(26)),
      );
    });
  });

  group('contrast', () {
    // WCAG AA for body text. These are the pairs the two new looks actually
    // put text on, read off the mockups; a shade nudged later that drops a
    // pair below the line fails here, not at arm's length in a bright hall.
    const pairs = <(String, Color, Color)>[
      ('lanyard ink on paper', LanyardColors.ink, LanyardColors.paper),
      ('lanyard muted on paper', LanyardColors.mutedInk, LanyardColors.paper),
      ('lanyard muted on badge', LanyardColors.mutedInk, LanyardColors.badge),
      ('badge white on blue', LanyardColors.badge, LanyardColors.blue),
      ('sign yellow on ink', LanyardColors.signal, LanyardColors.ink),
      ('ink on yellow stripe', LanyardColors.ink, LanyardColors.signal),
      ('alert on badge', LanyardColors.alert, LanyardColors.badge),
      ('alert on paper', LanyardColors.alert, LanyardColors.paper),
      ('blue link on paper', LanyardColors.blue, LanyardColors.paper),
      ('toybox ink on card', ToyboxColors.ink, ToyboxColors.card),
      ('toybox ink on cream', ToyboxColors.ink, ToyboxColors.cream),
      ('toybox muted on card', ToyboxColors.mutedInk, ToyboxColors.card),
      ('toybox muted on cream', ToyboxColors.mutedInk, ToyboxColors.cream),
      ('toybox ink on sky', ToyboxColors.ink, ToyboxColors.sky),
      ('toybox good on card', ToyboxColors.good, ToyboxColors.card),
      ('toybox warn on card', ToyboxColors.warn, ToyboxColors.card),
      ('toybox bad on card', ToyboxColors.bad, ToyboxColors.card),
    ];

    for (final (name, text, ground) in pairs) {
      test('$name is at least 4.5:1', () {
        expect(contrast(text, ground), greaterThanOrEqualTo(4.5));
      });
    }

    test('every new colour is opaque', () {
      for (final color in [
        LanyardColors.paper,
        LanyardColors.badge,
        LanyardColors.ink,
        LanyardColors.mutedInk,
        LanyardColors.signal,
        LanyardColors.alert,
        ToyboxColors.cream,
        ToyboxColors.card,
        ToyboxColors.ink,
        ToyboxColors.mutedInk,
        ToyboxColors.sky,
        ToyboxColors.skyEdge,
        ToyboxColors.good,
        ToyboxColors.warn,
        ToyboxColors.bad,
      ]) {
        expect(color.a, equals(1.0), reason: '$color');
      }
    });
  });
}

/// The WCAG contrast ratio between [a] and [b].
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}
