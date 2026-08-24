import 'dart:convert';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final handler = buildHandler();

  Future<Response> get(String path) async =>
      handler(Request('GET', Uri.parse('http://localhost:8080$path')));

  group('buildHandler', () {
    test('GET /health returns 200 with the protocol banner', () async {
      final response = await get('/$healthPath');

      expect(response.statusCode, equals(200));
      expect(await response.readAsString(), equals(helloProtocol()));
    });

    test('GET /metrics returns the current load numbers as JSON', () async {
      final response = await get('/$metricsPath');

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('application/json'));

      final body =
          jsonDecode(await response.readAsString()) as Map<String, Object?>;
      expect(body, contains('players'));
      expect(body, contains('averagePlayersPerSnapshot'));
      expect(body, contains('outboundBytesPerClientPerSecond'));
    });

    test('GET /config serves the event config as JSON', () async {
      // Read by the welcome screen before there is a socket, a session or a
      // name — which is why it is a plain unauthenticated GET.
      final relays = MapRelays(
        config: ConfigStore.inMemory(
          config: const AppConfig(worldName: 'DashConf'),
        ),
      );
      final response = await buildHandler(relays: relays)(
        Request('GET', Uri.parse('http://localhost:8080/$configPath')),
      );

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('application/json'));
      expect(
        parseAppConfig(await response.readAsString()).worldName,
        equals('DashConf'),
      );
    });

    test('GET /config is never cached', () async {
      // A proxy holding yesterday's tagline for an hour would undo the whole
      // feature: the point is that an edit is live on the next reload.
      final response = await get('/$configPath');

      expect(response.headers['cache-control'], equals('no-store'));
    });

    test('an unknown path returns 404', () async {
      final response = await get('/nope');

      expect(response.statusCode, equals(404));
    });

    test('a non-GET method on the health path returns 404', () async {
      final response = await handler(
        Request('POST', Uri.parse('http://localhost:8080/$healthPath')),
      );

      expect(response.statusCode, equals(404));
    });
  });

  group('the admin route', () {
    test('does not exist when no hub is wired in', () async {
      // `buildHandler()` with no admin hub is what a build that never
      // configured moderation gets: the path is a 404 like any other.
      final response = await get('/$adminWebSocketPath');

      expect(response.statusCode, equals(404));
    });

    test('is routed to the upgrade handler when a hub is wired in', () async {
      final hub = MapRelays();
      final withAdmin = buildHandler(
        relays: hub,
        admin: AdminHub(relays: hub, token: 'a-long-enough-test-token'),
      );

      // A malformed upgrade rather than a plain GET: the WebSocket handler
      // answers a plain GET with a 404 of its own, which is
      // indistinguishable from the route not existing. A broken upgrade gets
      // a 400 from it, and only from it — so this proves the request
      // actually reached the admin handler.
      Future<Response> badUpgrade(Handler handler, String path) async =>
          handler(
            Request(
              'GET',
              Uri.parse('http://localhost:8080/$path'),
              headers: const {
                'connection': 'Upgrade',
                'upgrade': 'websocket',
                'sec-websocket-version': '13',
              },
            ),
          );

      expect(
        (await badUpgrade(withAdmin, adminWebSocketPath)).statusCode,
        equals(400),
      );
      // ...and the same request without a hub falls through to the 404.
      expect(
        (await badUpgrade(handler, adminWebSocketPath)).statusCode,
        equals(404),
      );
      // The player route behaves the same way, which is the point: one
      // transport, two destinations.
      expect(
        (await badUpgrade(withAdmin, webSocketPath)).statusCode,
        equals(400),
      );
    });

    test('the public metrics say nothing about moderation', () async {
      // `/metrics` is read by the welcome screen before anybody has logged
      // into anything, so the number of bans does not belong in it.
      final body = jsonDecode(
        await (await get('/$metricsPath')).readAsString(),
      ) as Map<String, Object?>;

      expect(body.keys.join(' ').toLowerCase(), isNot(contains('ban')));
      expect(body.keys.join(' ').toLowerCase(), isNot(contains('admin')));
      expect(body.keys.join(' ').toLowerCase(), isNot(contains('token')));
    });
  });

  group('the admin path', () {
    test('is pinned to the value the client connects to', () {
      // The other half of this decision is `adminSocketPath` in
      // `client/lib/core/server_endpoint.dart`, which cannot import this
      // package. Change one and this fails until you change the other.
      expect(adminWebSocketPath, equals('og-route'));
    });
  });
}
