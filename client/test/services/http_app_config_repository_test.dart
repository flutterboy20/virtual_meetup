import 'dart:async';

import 'package:client/core/server_endpoint.dart';
import 'package:client/services/app_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:protocol/protocol.dart';

/// An HTTP client that answers however the test says, or refuses.
class _FakeClient extends http.BaseClient {
  _FakeClient({this.body = '', this.status = 200, this.throws = false});

  final String body;
  final int status;
  final bool throws;

  /// Every URL this client was asked for.
  final List<Uri> requested = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url);
    if (throws) throw const SocketFailure();
    return http.StreamedResponse(
      Stream.value(body.codeUnits),
      status,
    );
  }
}

/// Stands in for the half-dozen ways a request can fail on venue wifi.
class SocketFailure implements Exception {
  const SocketFailure();
}

void main() {
  final url = Uri.parse('http://localhost:8080/config');

  group('HttpAppConfigRepository', () {
    test('reads the document the server serves', () async {
      final client = _FakeClient(
        body: '{"worldName": "DashConf", "botCounts": {"beach": 2}}',
      );

      final config = await HttpAppConfigRepository(
        url: url,
        client: client,
      ).load();

      expect(config.worldName, equals('DashConf'));
      expect(config.botCountFor(MapId.beach), equals(2));
      expect(client.requested.single, equals(url));
    });

    test('a server that is down costs the copy, not the door', () async {
      // Every failure is the same failure as far as the lobby is concerned,
      // and last week's tagline beats a blank page.
      final config = await HttpAppConfigRepository(
        url: url,
        client: _FakeClient(throws: true),
      ).load();

      expect(config, equals(AppConfig.defaults));
    });

    test('so does a non-200, and a body that is not JSON', () async {
      expect(
        await HttpAppConfigRepository(
          url: url,
          client: _FakeClient(status: 502, body: 'Bad Gateway'),
        ).load(),
        equals(AppConfig.defaults),
      );
      expect(
        await HttpAppConfigRepository(
          url: url,
          client: _FakeClient(body: '<html>504</html>'),
        ).load(),
        equals(AppConfig.defaults),
      );
    });

    test('points at the same server the socket does, over http', () async {
      // One knob, not two. A deployment behind TLS must not silently make a
      // plaintext request a browser would block.
      expect(
        resolveConfigUri(override: 'wss://example.org/ws'),
        equals(Uri.parse('https://example.org/config')),
      );
      expect(
        resolveConfigUri(override: 'ws://localhost:8080/ws'),
        equals(Uri.parse('http://localhost:8080/config')),
      );
    });
  });
}
