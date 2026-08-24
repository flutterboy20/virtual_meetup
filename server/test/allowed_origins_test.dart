import 'dart:io';

import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Origin pinning and CORS, over the real transport.
///
/// Both halves read the same list — the socket handshake and the two public
/// GET routes — so they are tested together, against one running server, in
/// the two states that matter: the list set, and the list unset.
void main() {
  group('resolveAllowedOrigins', () {
    test('is empty when unset — no browser origin at all', () {
      // The flip. This used to be `null`, meaning allow any, on the reasoning
      // that local development should need no environment. The cost was that
      // the *exposed* configuration was the one you got by saying nothing, so
      // a production deploy that forgot the variable looked exactly like one
      // that had been set correctly. Now forgetting it fails loudly.
      expect(resolveAllowedOrigins(const {}), isEmpty);
    });

    test('is empty when blank', () {
      expect(
        resolveAllowedOrigins(const {allowedOriginsEnvVar: '   '}),
        isEmpty,
      );
    });

    test('is null — every origin — only for an explicit wildcard', () {
      expect(
        resolveAllowedOrigins(const {allowedOriginsEnvVar: anyOriginWildcard}),
        isNull,
      );
    });

    test('the wildcard survives whitespace around it', () {
      expect(
        resolveAllowedOrigins(const {allowedOriginsEnvVar: '  *  '}),
        isNull,
      );
    });

    test('refuses a wildcard mixed into a list', () {
      // Either the wildcard is redundant or the origins are, and which one
      // the author meant is exactly the thing not to guess about.
      expect(
        () => resolveAllowedOrigins(const {
          allowedOriginsEnvVar: 'https://a.test,*',
        }),
        throwsFormatException,
      );
    });

    test('reads a single origin', () {
      expect(
        resolveAllowedOrigins(const {
          allowedOriginsEnvVar: 'https://meet.example.com',
        }),
        equals({'https://meet.example.com'}),
      );
    });

    test('reads a comma-separated list', () {
      expect(
        resolveAllowedOrigins(const {
          allowedOriginsEnvVar: 'https://a.example.com,https://b.example.com',
        }),
        equals({'https://a.example.com', 'https://b.example.com'}),
      );
    });

    test('trims whitespace around every entry', () {
      expect(
        resolveAllowedOrigins(const {
          allowedOriginsEnvVar: ' https://a.example.com , https://b.test ',
        }),
        equals({'https://a.example.com', 'https://b.test'}),
      );
    });

    test('lowercases, because that is the form the comparison uses', () {
      expect(
        resolveAllowedOrigins(const {
          allowedOriginsEnvVar: 'HTTPS://Meet.Example.COM',
        }),
        equals({'https://meet.example.com'}),
      );
    });

    test('drops empty entries from a trailing or doubled comma', () {
      expect(
        resolveAllowedOrigins(const {
          allowedOriginsEnvVar: 'https://a.test,,https://b.test,',
        }),
        equals({'https://a.test', 'https://b.test'}),
      );
    });

    test('throws when it is set but names nothing', () {
      // Reading "  , ,  " as "allow any" would be the most dangerous possible
      // reading of a typo.
      expect(
        () => resolveAllowedOrigins(const {allowedOriginsEnvVar: ' , , '}),
        throwsFormatException,
      );
    });
  });

  group('with ALLOWED_ORIGINS set', () {
    const listed = 'https://meet.example.com';
    const unlisted = 'https://evil.example.com';

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

    Future<HttpClientResponse> get(String route, {String? origin}) async {
      final request = await HttpClient().getUrl(path(route));
      if (origin != null) request.headers.set('origin', origin);
      return request.close();
    }

    Future<WebSocketChannel> socket(String route, {String? origin}) async {
      final channel = IOWebSocketChannel.connect(
        path(route).replace(scheme: 'ws'),
        headers: origin == null ? null : {'origin': origin},
      );
      await channel.ready;
      return channel;
    }

    test('a listed origin connects', () async {
      final channel = await socket(webSocketPath, origin: listed);
      expect(channel.closeCode, isNull);
      await channel.sink.close();
    });

    test('a listed origin connects in any case it is typed', () async {
      final channel = await socket(
        webSocketPath,
        origin: 'HTTPS://Meet.Example.com',
      );
      expect(channel.closeCode, isNull);
      await channel.sink.close();
    });

    test('an unlisted origin is refused', () async {
      await expectLater(
        socket(webSocketPath, origin: unlisted),
        throwsA(isA<Object>()),
      );
    });

    test('the admin socket pins the same origins', () async {
      await expectLater(
        socket(adminWebSocketPath, origin: unlisted),
        throwsA(isA<Object>()),
      );
      final channel = await socket(adminWebSocketPath, origin: listed);
      expect(channel.closeCode, isNull);
      await channel.sink.close();
    });

    test('a request with no Origin connects — the load-test case', () async {
      // `tool/loadtest/` sends no `Origin`, and this is load-bearing: a
      // hardening phase that broke the load tester would be undone at the
      // next load-testing phase. It is also why origin pinning is not access
      // control — `curl` sends no `Origin` either.
      final channel = await socket(webSocketPath);
      expect(channel.closeCode, isNull);
      await channel.sink.close();
    });

    test('/config carries a matching Access-Control-Allow-Origin', () async {
      final response = await get(configPath, origin: listed);

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(
        response.headers.value('access-control-allow-origin'),
        equals(listed),
      );
      expect(response.headers.value('vary'), equals('Origin'));
      // Everything it already sent, it still sends.
      expect(response.headers.value('cache-control'), equals('no-store'));
    });

    test('/metrics carries a matching Access-Control-Allow-Origin', () async {
      final response = await get(metricsPath, origin: listed);

      expect(response.statusCode, equals(HttpStatus.ok));
      expect(
        response.headers.value('access-control-allow-origin'),
        equals(listed),
      );
    });

    test('an unlisted origin gets no header on either route', () async {
      for (final route in [configPath, metricsPath]) {
        final response = await get(route, origin: unlisted);

        expect(response.statusCode, equals(HttpStatus.ok));
        expect(
          response.headers.value('access-control-allow-origin'),
          isNull,
          reason: '$route echoed an unlisted origin',
        );
      }
    });

    test('no Origin gets no header', () async {
      final response = await get(configPath);

      expect(response.headers.value('access-control-allow-origin'), isNull);
    });
  });

  group('with ALLOWED_ORIGINS unset', () {
    late HttpServer server;
    late MapRelays hub;

    setUp(() async {
      hub = MapRelays(tickInterval: const Duration(milliseconds: 10))..start();
      server = await shelf_io.serve(
        buildHandler(relays: hub),
        InternetAddress.loopbackIPv4,
        0,
      );
    });

    tearDown(() async {
      hub.stop();
      await server.close(force: true);
    });

    Uri path(String route) =>
        Uri.parse('http://127.0.0.1:${server.port}/$route');

    test('no browser origin connects', () async {
      // The whole flip, in one assertion. This test used to say "every origin
      // connects, listed or not" — that was the old default, and it is the
      // behaviour a forgotten environment variable used to hand an attacker.
      for (final origin in ['https://a.test', 'https://b.test']) {
        final connecting = IOWebSocketChannel.connect(
          path(webSocketPath).replace(scheme: 'ws'),
          headers: {'origin': origin},
        ).ready;
        await expectLater(
          connecting,
          throwsA(isA<Object>()),
          reason: '$origin connected to a server that named no origins',
        );
      }
    });

    test('a request with no Origin still connects', () async {
      // The load tester, curl, and anything else that is not a browser. This
      // is what the flip does *not* change, and it is why origin pinning is
      // not access control: the socket cap is what stops these.
      final channel = IOWebSocketChannel.connect(
        path(webSocketPath).replace(scheme: 'ws'),
      );
      await channel.ready;
      expect(channel.closeCode, isNull);
      await channel.sink.close();
    });

    test('the GET routes send no CORS header, exactly as before', () async {
      // The half that did not change. An empty list matches nothing, so no
      // header appears — not `*`, not an echo — which is byte-for-byte what
      // an unset variable produced before the flip.
      for (final route in [configPath, metricsPath]) {
        final request = await HttpClient().getUrl(path(route));
        request.headers.set('origin', 'https://anything.test');
        final response = await request.close();

        expect(response.statusCode, equals(HttpStatus.ok));
        expect(
          response.headers.value('access-control-allow-origin'),
          isNull,
          reason: '$route grew a CORS header with no list configured',
        );
        expect(response.headers.value('vary'), isNull);
      }
    });
  });

  group('with ALLOWED_ORIGINS=*', () {
    late HttpServer server;
    late MapRelays hub;

    setUp(() async {
      hub = MapRelays(tickInterval: const Duration(milliseconds: 10))..start();
      server = await shelf_io.serve(
        // What `resolveAllowedOrigins` returns for the wildcard.
        buildHandler(relays: hub, allowedOrigins: null),
        InternetAddress.loopbackIPv4,
        0,
      );
    });

    tearDown(() async {
      hub.stop();
      await server.close(force: true);
    });

    Uri path(String route) =>
        Uri.parse('http://127.0.0.1:${server.port}/$route');

    test('every origin connects — the development escape hatch', () async {
      for (final origin in ['https://a.test', 'https://b.test']) {
        final channel = IOWebSocketChannel.connect(
          path(webSocketPath).replace(scheme: 'ws'),
          headers: {'origin': origin},
        );
        await channel.ready;
        expect(channel.closeCode, isNull);
        await channel.sink.close();
      }
    });

    test('the GET routes echo whatever asked', () async {
      // Echoed rather than answered with a literal `*`, because `*` is a
      // different and wider promise than the one being made here.
      const origin = 'http://localhost:4242';
      final request = await HttpClient().getUrl(path(configPath));
      request.headers.set('origin', origin);
      final response = await request.close();

      expect(
        response.headers.value('access-control-allow-origin'),
        equals(origin),
      );
      expect(response.headers.value('vary'), equals('Origin'));
    });
  });
}
