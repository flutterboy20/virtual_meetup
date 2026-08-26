import 'package:client/core/app_fonts.dart';
import 'package:client/core/theme.dart';
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
}
