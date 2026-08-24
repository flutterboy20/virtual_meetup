import 'package:client/core/server_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveServerUri', () {
    test('falls back to the local server when nothing is configured', () {
      // No --dart-define in a test run, so this is the real default path.
      expect(resolveServerUri(), equals(Uri.parse(defaultServerUrl)));
    });

    test('uses a ws:// override', () {
      expect(
        resolveServerUri(override: 'ws://192.168.1.20:8080/ws').toString(),
        equals('ws://192.168.1.20:8080/ws'),
      );
    });

    test('uses a wss:// override, which production will need', () {
      expect(
        resolveServerUri(override: 'wss://world.example.org/ws').toString(),
        equals('wss://world.example.org/ws'),
      );
    });

    test('tolerates surrounding whitespace', () {
      expect(
        resolveServerUri(override: '  ws://localhost:9000/ws  ').toString(),
        equals('ws://localhost:9000/ws'),
      );
    });

    test('ignores an override that is not a WebSocket URL', () {
      // A deploy flag with `https://` in it is a typo, not an endpoint.
      for (final bad in ['https://example.org', 'localhost:8080', 'nonsense']) {
        expect(
          resolveServerUri(override: bad),
          equals(Uri.parse(defaultServerUrl)),
          reason: '"$bad" should not be accepted',
        );
      }
    });
  });
}
