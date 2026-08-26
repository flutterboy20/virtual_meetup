import 'package:client/core/credits.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

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

  group('the printed form of a link', () {
    test('drops the scheme and nothing else', () {
      // A shortening a person can check against the QR above it, not a
      // rewrite they have to trust instead of the link.
      expect(
        Credits.linkLabel('https://github.com/flutterboy20/virtual_conference'),
        equals('github.com/flutterboy20/virtual_conference'),
      );
    });

    test('drops a trailing slash', () {
      expect(
        Credits.linkLabel('https://example.dev/'),
        equals('example.dev'),
      );
    });

    test('handles http as well as https', () {
      expect(Credits.linkLabel('http://example.dev'), equals('example.dev'));
    });

    test('leaves anything else exactly as written', () {
      expect(Credits.linkLabel('example.dev/x'), equals('example.dev/x'));
    });

    test('the fallback is the same URL the protocol defaults to', () {
      // Two copies of a URL is two chances to ship a dead one — the same rule
      // the portfolio entry above follows.
      expect(Credits.repositoryUrl, equals(AppConfig.defaultGithubLink));
    });
  });
}
