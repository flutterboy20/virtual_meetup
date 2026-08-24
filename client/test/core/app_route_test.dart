import 'package:client/core/app_route.dart';
import 'package:client/core/server_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveRoute', () {
    test('an ordinary URL is the world', () {
      for (final url in <String>[
        'https://event.example/',
        'https://event.example/index.html',
        'http://localhost:8080/',
        'https://event.example/?ref=qr',
        'https://event.example/#',
      ]) {
        expect(
          resolveRoute(Uri.parse(url)),
          equals(AppRoute.world),
          reason: url,
        );
      }
    });

    test('the admin fragment opens the moderation screen', () {
      expect(
        resolveRoute(Uri.parse('https://event.example/#og-route')),
        equals(AppRoute.admin),
      );
      expect(
        resolveRoute(Uri.parse('http://localhost:8080/#og-route')),
        equals(AppRoute.admin),
      );
    });

    test('an admin path works too, for a host that would rather', () {
      expect(
        resolveRoute(Uri.parse('https://event.example/og-route')),
        equals(AppRoute.admin),
      );
    });

    test('a near miss is not the admin screen', () {
      // Nothing fuzzy here: a URL either asks for it or it does not.
      for (final url in <String>[
        'https://event.example/#og-routes',
        'https://event.example/#OG-Route',
        'https://event.example/og',
        'https://event.example/?og-route=1',
        // The obvious guess is not the door.
        'https://event.example/#admin',
        'https://event.example/admin',
      ]) {
        expect(
          resolveRoute(Uri.parse(url)),
          equals(AppRoute.world),
          reason: url,
        );
      }
    });
  });

  group('resolveAdminSocketUri', () {
    test('points at the admin path on the same server', () {
      expect(
        resolveAdminSocketUri(override: 'wss://relay.example/ws').toString(),
        equals('wss://relay.example/og-route'),
      );
    });

    test('follows the player endpoint into TLS', () {
      // One knob, not two. A moderation socket that quietly stayed plaintext
      // while the player one moved to wss is a browser block at the worst
      // possible moment.
      expect(
        resolveAdminSocketUri(override: 'wss://relay.example/ws').isScheme(
          'wss',
        ),
        isTrue,
      );
      expect(
        resolveAdminSocketUri(override: 'ws://localhost:8080/ws').isScheme(
          'ws',
        ),
        isTrue,
      );
    });

    test('falls back with the player endpoint when the override is junk', () {
      expect(
        resolveAdminSocketUri(override: 'not a url').toString(),
        equals('ws://localhost:8080/og-route'),
      );
    });
  });

  group('the admin path', () {
    test('is pinned to the value the server serves', () {
      // The client cannot import `server/`, so this literal and
      // `adminWebSocketPath` in `server/lib/src/handler.dart` are the two
      // halves of one decision. There is a matching test on the server side.
      // If you change one, this fails until you change the other — which is
      // the entire point, because the failure mode is a moderation screen
      // that connects to a 404 in the middle of an event.
      expect(adminSocketPath, equals('og-route'));
      expect(adminRouteFragment, equals('og-route'));
    });

    test('is not a name anybody would guess first', () {
      // Obscurity, not security: it keeps the log quiet enough that a real
      // probe stands out. The token is what actually stops anybody.
      expect(adminSocketPath, isNot('admin'));
    });
  });
}
