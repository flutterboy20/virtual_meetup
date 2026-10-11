import 'dart:io';

import 'package:client/core/credits.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the promises the about page makes about itself: static, and
/// nothing fetched from anywhere but its own origin.
///
/// Read straight from `web/`, because that is what `flutter build web` copies
/// into the bundle. Tests run from the package root, so the path is relative
/// to `client/`.
void main() {
  final page = File('web${Credits.aboutPath}');

  test('the front door links to a page that exists', () {
    expect(page.existsSync(), isTrue, reason: '${page.path} is missing');
  });

  group('about.html', () {
    late String html;

    setUpAll(() => html = page.readAsStringSync());

    test('runs no JavaScript', () {
      expect(html.toLowerCase(), isNot(contains('<script')));
      expect(
        RegExp(r'\son[a-z]+\s*=', caseSensitive: false).hasMatch(html),
        isFalse,
        reason: 'inline event handlers are JavaScript too',
      );
    });

    test('fetches nothing from another host', () {
      // Links a person clicks (<a href>) may go anywhere. What the browser
      // loads by itself — images, stylesheets, fonts, icons — must not.
      final subresource = RegExp(
        r'''(<(img|link|source|iframe|video|audio)\b[^>]*\s(src|href|srcset)\s*=\s*["']?\s*(https?:)?//)|@import|url\(''',
        caseSensitive: false,
      );
      expect(subresource.hasMatch(html), isFalse);
    });

    test('every local image it shows is in web/', () {
      final sources = RegExp(r'''<img\b[^>]*\ssrc\s*=\s*["']([^"']+)["']''')
          .allMatches(html)
          .map((m) => m.group(1)!)
          .toList();

      expect(sources, isNotEmpty);
      for (final source in sources) {
        expect(File('web/$source').existsSync(), isTrue, reason: source);
      }
    });

    test('reads at phone width', () {
      expect(html, contains('name="viewport"'));
      expect(html, contains('width=device-width'));
    });
  });
}
