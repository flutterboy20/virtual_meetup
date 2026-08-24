import 'package:client/core/credits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the social links', () {
    test('are all parseable, absolute URLs', () {
      // The row hands each of these straight to the platform. A relative or
      // unparseable one fails silently at the bottom of the lobby, which is
      // exactly where nobody would notice it.
      for (final link in Credits.social) {
        final uri = Uri.tryParse(link.url);
        expect(uri, isNotNull, reason: '${link.label} is not a URL');
        expect(uri!.hasScheme, isTrue, reason: '${link.label} has no scheme');
        expect(
          uri.scheme,
          anyOf('https', 'mailto'),
          reason: '${link.label} is neither https nor mailto',
        );
      }
    });

    test('carry a label and a target each', () {
      for (final link in Credits.social) {
        expect(link.label, isNotEmpty);
        expect(link.url, isNotEmpty);
      }
    });

    test('do not repeat a destination', () {
      final urls = Credits.social.map((link) => link.url).toSet();

      expect(urls, hasLength(Credits.social.length));
    });

    test('name a bundled path when they name an asset at all', () {
      // A brand mark can be swapped in whenever; what must not happen is a
      // path the bundle has never heard of, which renders as a broken box
      // rather than as the placeholder it replaced.
      for (final link in Credits.social) {
        final asset = link.assetPath;
        if (asset == null) continue;
        expect(
          asset,
          startsWith('assets/'),
          reason: '${link.label} must point inside the asset bundle',
        );
      }
    });

    test('the portfolio entry is the same URL the name links to', () {
      // Two copies of a URL is two chances to ship a dead one.
      final portfolio = Credits.social.firstWhere(
        (link) => link.label == 'Portfolio',
      );

      expect(portfolio.url, equals(Credits.authorUrl));
    });
  });
}
