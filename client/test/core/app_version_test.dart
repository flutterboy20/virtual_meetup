import 'package:client/core/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appVersionLabel', () {
    test('says it is a dev build when nothing was defined', () {
      // No --dart-define in a test run, so this is the real default path.
      expect(appVersionLabel(), equals(devVersionLabel));
    });

    test('prefixes a release number with v', () {
      expect(appVersionLabel(override: '1.0.0+2'), equals('v1.0.0+2'));
    });

    test('handles a version with no build number', () {
      expect(appVersionLabel(override: '2.1.0'), equals('v2.1.0'));
    });

    test('tolerates surrounding whitespace', () {
      expect(appVersionLabel(override: '  1.0.0+2  '), equals('v1.0.0+2'));
    });

    test('treats a blank define as no define at all', () {
      for (final blank in ['', '   ', '\n']) {
        expect(
          appVersionLabel(override: blank),
          equals(devVersionLabel),
          reason: 'a define that resolved to nothing should not print a bare v',
        );
      }
    });
  });
}
