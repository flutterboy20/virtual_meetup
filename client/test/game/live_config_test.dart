import 'dart:async';

import 'package:client/game/beach_map.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/game/stage_screen_component.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_socket.dart';

void main() {
  // `ConferenceGame.onLoad` reaches for `SchedulerBinding.instance`.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the crowd size', () {
    testWithGame<ConferenceGame>(
      'is the whole roster when the config says nothing',
      ConferenceGame.new,
      (game) async {
        await game.ready();

        expect(game.bots, hasLength(game.allBots.length));
        expect(game.bots, hasLength(game.layout.bots.length));
      },
    );

    testWithGame<ConferenceGame>(
      'is what the config says when it says something',
      () => ConferenceGame(
        config: const AppConfig(botCounts: {MapId.conference: 5}),
      ),
      (game) async {
        await game.ready();

        expect(game.bots, hasLength(5));
        // The roster order is a priority order, so a smaller crowd is the
        // front of it: the atrium keeps its two before the garden keeps any.
        expect(
          game.bots.map((bot) => bot.brain.spec.name),
          equals(
            ConferenceBots.roster.take(5).map((spec) => spec.name),
          ),
        );
      },
    );

    testWithGame<ConferenceGame>(
      'only the mounted ones are in the world',
      () => ConferenceGame(
        config: const AppConfig(botCounts: {MapId.conference: 3}),
      ),
      (game) async {
        await game.ready();

        expect(game.allBots.take(3).every((bot) => bot.isMounted), isTrue);
        expect(game.allBots.skip(3).any((bot) => bot.isMounted), isFalse);
      },
    );

    testWithGame<ConferenceGame>(
      'turns down and back up without rebuilding a single bean',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();
        final everybody = List.of(game.allBots);

        game.applyConfig(
          const AppConfig(botCounts: {MapId.conference: 4}),
        );
        await game.ready();
        expect(game.bots, hasLength(4));

        game.applyConfig(AppConfig.defaults);
        await game.ready();

        // Identical instances, not merely an equal count. Rebuilding them
        // would re-seed every brain, so the garden would visibly restart
        // every time somebody nudged the dial.
        expect(game.bots, hasLength(everybody.length));
        for (var i = 0; i < everybody.length; i++) {
          expect(identical(game.bots[i], everybody[i]), isTrue);
        }
      },
    );

    testWithGame<ConferenceGame>(
      'a number bigger than the roster is the roster, not a crash',
      () => ConferenceGame(
        config: const AppConfig(botCounts: {MapId.conference: 900}),
      ),
      (game) async {
        await game.ready();

        expect(game.bots, hasLength(game.allBots.length));
      },
    );

    testWithGame<ConferenceGame>(
      'zero is a real answer, and empties the room',
      () => ConferenceGame(
        config: const AppConfig(botCounts: {MapId.conference: 0}),
      ),
      (game) async {
        await game.ready();

        expect(game.bots, isEmpty);
        expect(game.allBots, isNotEmpty, reason: 'they still exist, unmounted');
      },
    );

    testWithGame<ConferenceGame>(
      'each map reads its own number',
      () => ConferenceGame(
        map: const BeachMap(),
        config: const AppConfig(
          botCounts: {MapId.conference: 1, MapId.beach: 2},
        ),
      ),
      (game) async {
        await game.ready();

        expect(game.bots, hasLength(2));
      },
    );
  });

  group('a live config edit', () {
    testWithGame<ConferenceGame>(
      'repaints the projector without rebuilding the world',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();
        final before = game.bean.position.clone();
        final map = game.layout as ConferenceMap;

        game.applyConfig(const AppConfig(boardMessage: 'the wifi is fine'));
        await game.ready();

        expect(map.boardMessage, equals('the wifi is fine'));
        // The whole reason this is a method and not a rebuild: nobody gets
        // teleported back to the spawn ring over a typo.
        expect(game.bean.position, equals(before));
      },
    );

    testWithGame<ConferenceGame>(
      'puts a new programme on the stage screen',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();
        final screen = game.world.children
            .whereType<StageScreenComponent>()
            .single;

        game.applyConfig(
          const AppConfig(stageLines: ['NEXT UP: lunch', 'then more lunch']),
        );

        expect(
          screen.cycler.lines,
          equals(['NEXT UP: lunch', 'then more lunch']),
        );
        expect(screen.cycler.current, equals('NEXT UP: lunch'));
      },
    );

    testWithGame<ConferenceGame>(
      'a config equal to the one in force does nothing',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();
        final screen = game.world.children
            .whereType<StageScreenComponent>()
            .single;
        // Wind the screen forward so a needless reset would be visible.
        for (var i = 0; i < 60 * 7; i++) {
          game.update(1 / 60);
        }
        final advances = screen.cycler.advances;
        expect(advances, greaterThan(0));

        // The server pushes on every join, so this is the common case rather
        // than a corner one.
        game.applyConfig(AppConfig.defaults);

        expect(screen.cycler.advances, equals(advances));
      },
    );
  });

  group('a config pushed down the socket', () {
    testWidgets('is applied to the world and passed to the widget layer', (
      tester,
    ) async {
      final (:client, :socket) = fakeNetwork();
      addTearDown(client.dispose);
      final seen = <AppConfig>[];
      final game = ConferenceGame(network: client, onConfig: seen.add);
      unawaited(client.connect());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameWidget(game: game)),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      socket.emit(
        const ConfigMessage(
          config: AppConfig(
            worldName: 'DashConf',
            boardMessage: 'the wifi is fine',
            botCounts: {MapId.conference: 2},
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // The world first...
      expect(game.config.worldName, equals('DashConf'));
      expect(
        (game.layout as ConferenceMap).boardMessage,
        equals('the wifi is fine'),
      );
      expect(game.bots, hasLength(2));
      // ...and then everything above it, so the front door behind this screen
      // is showing the same event by the time anybody walks back out to it.
      expect(seen.single.worldName, equals('DashConf'));
    });
  });
}
