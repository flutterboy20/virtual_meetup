import 'package:client/core/player_identity.dart';
import 'package:client/features/world/view/world_screen.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/services/sponsor_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_identity_store.dart';
import '../support/fake_socket.dart';

void main() {
  const returning = PlayerIdentity(
    sessionId: FakeIdentityStore.testSessionId,
    name: 'Ada',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
  );

  /// Pumps enough frames for the world to build and for a pushed config to
  /// reach it, booth parse and all.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  const acme = {
    'id': 'acme',
    'name': 'Acme',
    'blurb': 'a booth',
    'x': 1130.0,
    'y': 478.0,
    'color': '#54C5F8',
  };

  /// The world screen on its own, over a fake socket and no bundled booths.
  ///
  /// Straight to [WorldScreen] rather than through the app, because what is
  /// being tested is the wire from a pushed config to the running game — and
  /// walking in through the welcome screen would test the welcome screen.
  Future<({ConferenceGame game, FakeSocket socket})> pumpWorld(
    WidgetTester tester, {
    AppConfig config = AppConfig.defaults,
  }) async {
    final (:client, :socket) = fakeNetwork();
    addTearDown(client.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: WorldScreen(
          identity: returning,
          store: FakeIdentityStore(identity: returning),
          network: client,
          appConfig: config,
          // No bundled list behind it, so every booth in these tests came
          // from a config and nothing else.
          sponsors: const StaticSponsorRepository([]),
        ),
      ),
    );
    // Pumped a fixed number of frames rather than settled: a Flame game never
    // stops scheduling frames, so `pumpAndSettle` here waits for a world that
    // is working exactly as intended and then calls it a timeout.
    await settle(tester);

    final game = tester
        .widget<GameWidget<ConferenceGame>>(
          find.byType(GameWidget<ConferenceGame>),
        )
        .game!;
    return (game: game, socket: socket);
  }

  testWidgets('a booth pushed mid-event stands up without a reload', (
    tester,
  ) async {
    // The bug this file exists for: a moderator adds a sponsor, the config
    // reaches every client, and the east arm stays empty until everybody
    // reloads the page.
    final (:game, :socket) = await pumpWorld(tester);
    expect(game.layout.sponsors, isEmpty);

    socket.emit(const ConfigMessage(config: AppConfig(sponsors: [acme])));
    await settle(tester);

    expect(game.layout.sponsors.single.name, equals('Acme'));
  });

  testWidgets('a renamed booth changes its sign', (tester) async {
    final (:game, :socket) = await pumpWorld(
      tester,
      config: const AppConfig(sponsors: [acme]),
    );
    expect(game.layout.sponsors.single.name, equals('Acme'));

    socket.emit(
      const ConfigMessage(
        config: AppConfig(
          sponsors: [
            {
              'id': 'acme',
              'name': 'Acme Industries',
              'blurb': 'a booth',
              'x': 1130.0,
              'y': 478.0,
              'color': '#54C5F8',
            },
          ],
        ),
      ),
    );
    await settle(tester);

    expect(
      game.layout.sponsors.single.name,
      equals('Acme Industries'),
    );
  });

  testWidgets('a removed booth takes its collision with it', (tester) async {
    final (:game, :socket) = await pumpWorld(
      tester,
      config: const AppConfig(sponsors: [acme]),
    );
    expect(game.collision.isFree(1130, 478), isFalse);

    // An empty list means "use the bundled one", and this world was handed a
    // bundled list with nothing in it.
    socket.emit(const ConfigMessage(config: AppConfig.defaults));
    await settle(tester);

    expect(game.layout.sponsors, isEmpty);
    expect(game.collision.isFree(1130, 478), isTrue);
  });

  testWidgets('a booth list that stopped parsing leaves the room alone', (
    tester,
  ) async {
    // Loud on the admin screen, in front of whoever broke it. Silent here:
    // emptying an arm of the map under everybody is the worse failure.
    final (:game, :socket) = await pumpWorld(
      tester,
      config: const AppConfig(sponsors: [acme]),
    );

    socket.emit(
      const ConfigMessage(
        config: AppConfig(
          sponsors: [
            {'name': 'no id at all'},
          ],
        ),
      ),
    );
    await settle(tester);

    expect(game.layout.sponsors.single.name, equals('Acme'));
  });
}
