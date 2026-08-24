import 'package:client/services/app_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

void main() {
  // The parsing rules themselves live in `protocol/test/app_config_test.dart`,
  // where the type does. What is left here is the client's own question: is
  // the document this app ships with actually the copy it claims to ship?
  group('the bundled document', () {
    test('parses, and is the copy the app actually ships', () async {
      // The document is JSON text rather than a Dart object precisely so it
      // can be wrong; this is the test that says it is not.
      final config = await const StaticAppConfigRepository().load();

      expect(config.worldName, equals(AppConfig.defaultWorldName));
      expect(config.eyebrow, equals(AppConfig.defaultEyebrow));
      expect(config.tagline, equals(AppConfig.defaultTagline));
    });

    test('serves a document handed to it, the way a fetch will', () async {
      final config = await const StaticAppConfigRepository(
        '{"worldName": "DashConf", "tagline": "day two, same beans"}',
      ).load();

      expect(config.worldName, equals('DashConf'));
      expect(config.tagline, equals('day two, same beans'));
    });
  });
}
