import 'package:client/app/app.dart';
import 'package:client/core/player_identity.dart';
import 'package:client/core/server_endpoint.dart';
import 'package:client/features/welcome/view/map_picker.dart';
import 'package:client/features/welcome/view_model/welcome_view_model.dart';
import 'package:client/features/world/view/world_screen.dart';
import 'package:client/services/network_client.dart';
import 'package:client/services/server_status_service.dart';
import 'package:client/services/sponsor_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_identity_store.dart';
import '../support/fake_socket.dart';

/// A status service that answers whatever it is told to.
class _FakeStatus implements ServerStatusService {
  _FakeStatus(this.status);

  ServerStatus status;
  int calls = 0;

  @override
  Future<ServerStatus> fetch() async {
    calls++;
    return status;
  }
}

/// A status service that never answers usefully.
class _DownStatus implements ServerStatusService {
  @override
  Future<ServerStatus> fetch() async => const ServerUnreachable();
}

void main() {
  const ada = PlayerIdentity(
    sessionId: FakeIdentityStore.testSessionId,
    name: 'Ada',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.none,
  );

  group('the socket URL', () {
    test('carries the map in its query string', () {
      // The map is decided once, at socket-open, from the URL — it cannot be
      // read off the join message, because the server opens a session the
      // instant the socket upgrades.
      expect(
        resolveServerUriFor(MapId.beach).queryParameters[mapQueryParameter],
        equals('beach'),
      );
      expect(
        resolveServerUriFor(
          MapId.conference,
        ).queryParameters[mapQueryParameter],
        equals('conference'),
      );
    });

    test('keeps the path and anything the deploy flag already carried', () {
      const override = 'wss://event.example/ws?token=abc';

      final url = resolveServerUriFor(MapId.beach, override: override);

      expect(url.scheme, equals('wss'));
      expect(url.host, equals('event.example'));
      expect(url.path, equals('/ws'));
      expect(url.queryParameters['token'], equals('abc'));
      expect(url.queryParameters[mapQueryParameter], equals('beach'));
    });
  });

  group('the stored map', () {
    test('survives a reload', () async {
      final store = FakeIdentityStore(identity: ada);

      expect(await store.readMapId(), equals(MapId.conference));
      await store.writeMapId(MapId.beach);

      expect(await store.readMapId(), equals(MapId.beach));
    });

    test('is forgotten by a log out, along with everything else', () async {
      final store = FakeIdentityStore(identity: ada);
      await store.writeMapId(MapId.beach);

      await store.clear();

      expect(await store.readMapId(), equals(MapId.conference));
    });
  });

  group('WelcomeViewModel', () {
    test('loads the stored map and writes a new choice through', () async {
      final store = FakeIdentityStore(identity: ada);
      await store.writeMapId(MapId.beach);
      final model = WelcomeViewModel(
        status: _FakeStatus(const ServerOnline(0)),
        store: store,
      );

      await model.load();
      expect(model.selectedMap, equals(MapId.beach));

      model.selectMap(MapId.conference);
      expect(model.selectedMap, equals(MapId.conference));
      // Written immediately, not on Join: somebody who taps a card and then
      // closes the tab meant that card.
      await Future<void>.delayed(Duration.zero);
      expect(await store.readMapId(), equals(MapId.conference));

      model.dispose();
    });

    test('reports a head-count per map', () async {
      final model = WelcomeViewModel(
        status: _FakeStatus(
          const ServerOnline(
            9,
            byMap: {MapId.conference: 7, MapId.beach: 2},
          ),
        ),
        store: FakeIdentityStore(identity: ada),
      );

      await model.load();

      expect(model.onlineCount, equals(9));
      expect(model.playersOn(MapId.conference), equals(7));
      expect(model.playersOn(MapId.beach), equals(2));

      model.dispose();
    });

    test('an unreachable server means no counts, not zero counts', () async {
      // "Nobody is there" and "we could not ask" are opposite facts, and on
      // this screen printing the wrong one empties a working beach.
      final model = WelcomeViewModel(
        status: _DownStatus(),
        store: FakeIdentityStore(identity: ada),
      );

      await model.load();

      expect(model.playersOn(MapId.beach), isNull);
      expect(model.onlineCount, isNull);

      model.dispose();
    });

    test('a server with no byMap still gives a total', () async {
      // An older server. The picker loses its counts and nothing else.
      final model = WelcomeViewModel(
        status: _FakeStatus(const ServerOnline(4)),
        store: FakeIdentityStore(identity: ada),
      );

      await model.load();

      expect(model.onlineCount, equals(4));
      expect(model.playersOn(MapId.conference), isNull);

      model.dispose();
    });
  });

  group('/metrics parsing', () {
    test('reads byMap, and forgives a map it has never heard of', () {
      const body = ServerOnline(3, byMap: {MapId.beach: 3});

      expect(body.on(MapId.beach), equals(3));
      expect(body.on(MapId.conference), isNull);
      expect(body, equals(const ServerOnline(3, byMap: {MapId.beach: 3})));
      expect(body, isNot(equals(const ServerOnline(3))));
    });
  });

  // The lobby drifts and the game runs a ticker, so `pumpAndSettle` would
  // never settle: pump a couple of frames by hand instead, exactly as
  // `widget_test.dart` does.
  Future<void> pump(
    WidgetTester tester, {
    required FakeIdentityStore store,
    ServerStatus status = const ServerOnline(
      5,
      byMap: {MapId.conference: 4, MapId.beach: 1},
    ),
    SocketFactory? openSocket,
  }) async {
    final client = NetworkClient(
      openSocket: openSocket ?? (_) => FakeSocket(),
    );
    addTearDown(client.dispose);

    await tester.pumpWidget(
      VirtualConferenceApp(
        store: store,
        statusService: _FakeStatus(status),
        network: client,
        // A widget test must not read the asset bundle any more than it may
        // open a socket.
        sponsors: const StaticSponsorRepository([]),
      ),
    );
    // One for the bootstrap read, one for the status fetch.
    await tester.pump();
    await tester.pump();
  }

  /// Taps [label] and gives the app two frames to react.
  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump();
  }

  group('the front door', () {
    testWidgets('shows a card per map, with its head-count', (tester) async {
      await pump(tester, store: FakeIdentityStore(identity: ada));

      expect(find.byType(MapPicker), findsOneWidget);
      expect(find.text('Conference'), findsOneWidget);
      expect(find.text('Beach'), findsOneWidget);
      expect(find.text('4 people here'), findsOneWidget);
      expect(find.text('1 person here'), findsOneWidget);
    });

    testWidgets('picking the beach and joining opens the beach', (
      tester,
    ) async {
      final store = FakeIdentityStore(identity: ada);
      await pump(tester, store: store);

      await tap(tester, 'Beach');
      await tap(tester, 'Continue as Ada');

      final world = tester.widget<WorldScreen>(find.byType(WorldScreen));
      expect(world.mapId, equals(MapId.beach));
      expect(await store.readMapId(), equals(MapId.beach));
    });

    testWidgets('a stored map is where a returning player lands', (
      tester,
    ) async {
      final store = FakeIdentityStore(identity: ada);
      await store.writeMapId(MapId.beach);

      await pump(tester, store: store);
      await tap(tester, 'Continue as Ada');

      expect(
        tester.widget<WorldScreen>(find.byType(WorldScreen)).mapId,
        equals(MapId.beach),
      );
    });
  });

  group('switching from inside the world', () {
    Future<void> enterWorld(
      WidgetTester tester,
      FakeIdentityStore store, {
      SocketFactory? openSocket,
    }) async {
      await pump(tester, store: store, openSocket: openSocket);
      await tap(tester, 'Continue as Ada');
    }

    testWidgets('the HUD offers the other map, and only the other', (
      tester,
    ) async {
      await enterWorld(tester, FakeIdentityStore(identity: ada));

      expect(find.text('Go to Beach'), findsOneWidget);
      expect(find.text('Go to Conference'), findsNothing);
    });

    testWidgets('tapping it rebuilds the world on the other map', (
      tester,
    ) async {
      final store = FakeIdentityStore(identity: ada);
      await enterWorld(tester, store);

      final before = tester.widget<WorldScreen>(find.byType(WorldScreen));
      expect(before.mapId, equals(MapId.conference));

      await tap(tester, 'Go to Beach');

      final after = tester.widget<WorldScreen>(find.byType(WorldScreen));
      expect(after.mapId, equals(MapId.beach));
      // A new key, which is what makes this a teardown and a rebuild rather
      // than a screen quietly mutating under a live socket and a live game.
      expect(after.key, isNot(equals(before.key)));
      // ...and the offer now points the other way.
      expect(find.text('Go to Conference'), findsOneWidget);
    });

    testWidgets('the switch is remembered across a reload', (tester) async {
      final store = FakeIdentityStore(identity: ada);
      await enterWorld(tester, store);

      await tap(tester, 'Go to Beach');

      expect(await store.readMapId(), equals(MapId.beach));
    });

    testWidgets('the session id survives, so a ban still follows', (
      tester,
    ) async {
      // The whole reason a switch is not a log out: the moderation cooldown,
      // the name block and any ban are keyed on the session id.
      final store = FakeIdentityStore(identity: ada);
      await enterWorld(tester, store);

      await tap(tester, 'Go to Beach');

      final world = tester.widget<WorldScreen>(find.byType(WorldScreen));
      expect(world.identity.sessionId, equals(ada.sessionId));
      expect(await store.sessionId(), equals(ada.sessionId));
    });

    testWidgets('a switch onto a dead server is still a usable screen', (
      tester,
    ) async {
      // The failure this has to survive: the socket for the new map never
      // opens. The player's own bean owns its own position, so the world
      // still works — they see "Reconnecting…" and can walk back.
      final store = FakeIdentityStore(identity: ada);
      var opened = 0;
      await enterWorld(
        tester,
        store,
        openSocket: (_) {
          opened++;
          // The first socket works; the one the switch opens does not.
          if (opened > 1) throw StateError('the beach is unreachable');
          return FakeSocket();
        },
      );

      await tap(tester, 'Go to Beach');
      await tester.pump();

      // Still in the world, still on the beach, and offered a way back.
      expect(find.byType(WorldScreen), findsOneWidget);
      expect(
        tester.widget<WorldScreen>(find.byType(WorldScreen)).mapId,
        equals(MapId.beach),
      );
      expect(find.text('Go to Conference'), findsOneWidget);
      // And it is honest about the socket rather than pretending: whichever
      // of the waiting labels the chip is showing, it is not "Connected".
      expect(find.text('Connected'), findsNothing);
    });
  });
}
