import 'dart:io';

import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Refusing sockets that carry no `Origin`, over the real transport.
///
/// The case this exists for: somebody at the conference points the repo's
/// own load tester at the live URL. The tester sends no `Origin`; every
/// browser does. It is a speed bump — the header is trivial to forge — so
/// these tests pin the behaviour, not a promise of security.
void main() {
  group('resolveRequireOrigin', () {
    const pinned = {'https://meet.example.com'};

    test('defaults on when the origins are pinned — production', () {
      expect(resolveRequireOrigin(const {}, allowedOrigins: pinned), isTrue);
    });

    test('defaults off for the wildcard — local development', () {
      expect(resolveRequireOrigin(const {}, allowedOrigins: null), isFalse);
    });

    test('defaults off when no origins are set — curl still connects', () {
      expect(
        resolveRequireOrigin(const {}, allowedOrigins: const {}),
        isFalse,
      );
    });

    test('blank is the same as unset', () {
      expect(
        resolveRequireOrigin(
          const {requireOriginEnvVar: '  '},
          allowedOrigins: pinned,
        ),
        isTrue,
      );
    });

    test('an explicit false wins over pinned origins — load-testing prod', () {
      expect(
        resolveRequireOrigin(
          const {requireOriginEnvVar: 'FALSE'},
          allowedOrigins: pinned,
        ),
        isFalse,
      );
    });

    test('an explicit true wins over the wildcard', () {
      expect(
        resolveRequireOrigin(
          const {requireOriginEnvVar: ' true '},
          allowedOrigins: null,
        ),
        isTrue,
      );
    });

    test('anything else throws rather than picking a side', () {
      for (final value in ['yes', '1', 'on', 'ture']) {
        expect(
          () => resolveRequireOrigin(
            {requireOriginEnvVar: value},
            allowedOrigins: pinned,
          ),
          throwsFormatException,
          reason: value,
        );
      }
    });
  });

  group('with REQUIRE_ORIGIN on', () {
    const listed = 'https://meet.example.com';

    late HttpServer server;
    late MapRelays hub;
    late AdminHub admin;

    setUp(() async {
      hub = MapRelays(tickInterval: const Duration(milliseconds: 10));
      admin = AdminHub(relays: hub, token: 'a-long-enough-test-token');
      hub.start();
      server = await shelf_io.serve(
        buildHandler(
          relays: hub,
          admin: admin,
          allowedOrigins: const {listed},
          requireOrigin: true,
        ),
        InternetAddress.loopbackIPv4,
        0,
      );
    });

    tearDown(() async {
      hub.stop();
      admin.stop();
      await server.close(force: true);
    });

    Uri path(String route) =>
        Uri.parse('http://127.0.0.1:${server.port}/$route');

    Future<HttpClientResponse> upgrade(String route) async {
      final request = await HttpClient().getUrl(path(route));
      request.headers
        ..set('connection', 'Upgrade')
        ..set('upgrade', 'websocket')
        ..set('sec-websocket-version', '13')
        ..set('sec-websocket-key', 'dGhlIHNhbXBsZSBub25jZQ==');
      return await request.close();
    }

    test('a socket with no Origin is refused with 403', () async {
      for (final route in [webSocketPath, adminWebSocketPath]) {
        final response = await upgrade(route);
        expect(
          response.statusCode,
          equals(HttpStatus.forbidden),
          reason: route,
        );
      }
    });

    test('a refused socket gives its connection slot back', () async {
      for (var i = 0; i < 3; i++) {
        await upgrade(webSocketPath);
      }
      expect(hub.gate.openSockets, isZero);
    });

    test('a browser on the listed origin still connects', () async {
      for (final route in [webSocketPath, adminWebSocketPath]) {
        final WebSocketChannel channel = IOWebSocketChannel.connect(
          path(route).replace(scheme: 'ws'),
          headers: {'origin': listed},
        );
        await channel.ready;
        expect(channel.closeCode, isNull, reason: route);
        await channel.sink.close();
      }
    });

    test('the plain GET routes are untouched', () async {
      for (final route in [healthPath, configPath, metricsPath]) {
        final response = await (await HttpClient().getUrl(path(route))).close();
        expect(response.statusCode, equals(HttpStatus.ok), reason: route);
      }
    });
  });
}
