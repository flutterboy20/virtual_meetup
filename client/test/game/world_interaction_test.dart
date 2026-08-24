import 'dart:async';

import 'package:client/core/sponsor.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/game/floor_component.dart';
import 'package:client/game/nametag_layer.dart';
import 'package:client/game/splash_field.dart';
import 'package:client/game/world_hud.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_socket.dart';

const _booths = [
  Sponsor(
    id: 'near',
    name: 'Near Co',
    blurb: 'A booth.',
    x: 1130,
    y: 478,
    color: Color(0xFF54C5F8),
  ),
  Sponsor(
    id: 'far',
    name: 'Far Co',
    blurb: 'Another booth.',
    x: 1330,
    y: 478,
    color: Color(0xFF7ED9B6),
  ),
];

/// A player standing at ([x], [y]).
PlayerState _player(String id, double x, double y, {String? name}) =>
    PlayerState(
      id: id,
      name: name ?? 'Player $id',
      color: 0xFF54C5F8,
      cosmetic: PlayerCosmetic.none,
      x: x,
      y: y,
    );

void main() {
  // A real widget pump rather than `testWithGame`, because the interesting
  // behaviour here is asynchronous: the socket opens while the game ticks,
  // which is exactly what happens in the app.
  Future<({ConferenceGame game, FakeSocket socket})> pumpGame(
    WidgetTester tester, {
    List<Sponsor> sponsors = _booths,
  }) async {
    final (:client, :socket) = fakeNetwork();
    addTearDown(client.dispose);
    final game = ConferenceGame(
      network: client,
      sponsors: sponsors,
      spawnAngle: 0,
    );
    unawaited(client.connect());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameWidget(game: game)),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return (game: game, socket: socket);
  }

  Future<void> tick(WidgetTester tester, {int frames = 12}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Teleports the bean, the way a test walks somewhere without waiting.
  Future<void> standAt(
    WidgetTester tester,
    ConferenceGame game,
    double x,
    double y,
  ) async {
    game.bean.position.setValues(x, y);
    await tick(tester, frames: 2);
  }

  group('booth panels', () {
    testWidgets('open when you walk up and close when you walk away', (
      tester,
    ) async {
      final (:game, socket: _) = await pumpGame(tester);
      expect(game.hud.nearbySponsor.value, isNull);

      await standAt(tester, game, 1130, 560);
      expect(game.hud.nearbySponsor.value?.id, equals('near'));

      await standAt(tester, game, 1130, 700);
      expect(game.hud.nearbySponsor.value, isNull);
    });

    testWidgets('the nearest booth wins, not the first in the file', (
      tester,
    ) async {
      final (:game, socket: _) = await pumpGame(tester);

      await standAt(tester, game, 1300, 500);

      expect(game.hud.nearbySponsor.value?.id, equals('far'));
    });

    testWidgets('do not flicker at the boundary', (tester) async {
      // The hysteresis, tested where it matters: a bean sitting between the
      // two radii keeps the panel it already has, and never toggles.
      final (:game, socket: _) = await pumpGame(tester);
      await standAt(tester, game, 1130, 560);
      expect(game.hud.nearbySponsor.value?.id, equals('near'));

      var flips = 0;
      game.hud.nearbySponsor.addListener(() => flips++);
      const between = (Sponsor.approachRadius + Sponsor.leaveRadius) / 2;
      for (var i = 0; i < 20; i++) {
        // Oscillating across the *open* radius, inside the close radius.
        final offset = i.isEven ? between - 4 : between + 4;
        await standAt(tester, game, 1130, 478 + offset);
      }

      expect(flips, isZero, reason: 'the panel flickered at the boundary');
      expect(game.hud.nearbySponsor.value?.id, equals('near'));
    });

    testWidgets('there are no booths when the config is empty', (
      tester,
    ) async {
      final (:game, socket: _) = await pumpGame(tester, sponsors: const []);

      await standAt(tester, game, 1130, 500);

      expect(game.hud.nearbySponsor.value, isNull);
    });
  });

  group('the online counter', () {
    testWidgets('shows what the server says, not what is on screen', (
      tester,
    ) async {
      // The whole point: culling means this client can see two beans while
      // three hundred people are in the world.
      final (:game, :socket) = await pumpGame(tester);

      socket.emit(const WorldStatsMessage(online: 217));
      await tick(tester, frames: 2);

      expect(game.hud.online.value, equals(217));
    });
  });

  group('the minimap feed', () {
    testWidgets('is sampled, not streamed', (tester) async {
      final (:game, socket: _) = await pumpGame(tester);

      var pushes = 0;
      game.hud.minimap.addListener(() => pushes++);
      // Sixty frames of a bean that is genuinely moving, so every frame has
      // something new it *could* push.
      for (var i = 0; i < 60; i++) {
        game.bean.position.setValues(spawnCenterX + i.toDouble(), spawnCenterY);
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Roughly a second at 60fps: six samples, not sixty. That difference is
      // the difference between a minimap and a second render of the world.
      expect(pushes, lessThan(12));
      expect(pushes, greaterThan(2));
    });

    testWidgets('says nothing at all while nobody is moving', (tester) async {
      final (:game, socket: _) = await pumpGame(tester);
      await tick(tester, frames: 30);

      var pushes = 0;
      game.hud.minimap.addListener(() => pushes++);
      await tick(tester, frames: 60);

      // An identical frame is not news. A ValueNotifier assigned an equal
      // value does not notify, which is why MinimapFrame has value equality.
      expect(pushes, isZero);
    });

    testWidgets('carries you and everybody visible', (tester) async {
      final (:game, :socket) = await pumpGame(tester);

      socket.emit(
        SnapshotMessage(
          appeared: [_player('p1', 820, 600), _player('p2', 840, 600)],
          positions: const [
            PlayerPosition(id: 'p1', x: 820, y: 600),
            PlayerPosition(id: 'p2', x: 840, y: 600),
          ],
        ),
      );
      await tick(tester, frames: 24);

      expect(game.hud.minimap.value.others, hasLength(2));
      expect(game.hud.minimap.value.you.dx, equals(game.bean.position.x));
    });
  });

  group('emotes', () {
    testWidgets('a local emote is drawn immediately and sent', (tester) async {
      final (:game, :socket) = await pumpGame(tester);

      final sent = game.emote(EmoteKind.clap);
      await tick(tester, frames: 2);

      expect(sent, isTrue);
      // Drawn without waiting for the server to hand it back: the client owns
      // its own state, and a round trip between a tap and a reaction is the
      // difference between a button that works and one that feels broken.
      expect(game.emotes.count, equals(1));
      expect(
        socket.sentMessages.whereType<EmoteMessage>().single.emote,
        equals(EmoteKind.clap),
      );
    });

    testWidgets('the client throttles itself so it does not waste its own '
        'allowance', (tester) async {
      final (:game, :socket) = await pumpGame(tester);

      game
        ..emote(EmoteKind.clap)
        ..emote(EmoteKind.clap)
        ..emote(EmoteKind.clap);
      await tick(tester, frames: 2);

      expect(socket.sentMessages.whereType<EmoteMessage>(), hasLength(1));
    });

    testWidgets("a neighbour's emote floats above their bean", (tester) async {
      final (:game, :socket) = await pumpGame(tester);
      socket.emit(
        SnapshotMessage(
          appeared: [_player('p1', 820, 600)],
          positions: const [PlayerPosition(id: 'p1', x: 820, y: 600)],
        ),
      );
      await tick(tester, frames: 4);

      socket.emit(
        const PlayerEmotedMessage(id: 'p1', emote: EmoteKind.heart),
      );
      await tick(tester, frames: 2);

      expect(game.emotes.count, equals(1));
    });

    testWidgets('an emote from somebody off screen is dropped', (
      tester,
    ) async {
      final (:game, :socket) = await pumpGame(tester);

      socket.emit(
        const PlayerEmotedMessage(id: 'ghost', emote: EmoteKind.fire),
      );
      await tick(tester, frames: 2);

      expect(game.emotes.count, isZero);
    });

    testWidgets('a bubble fades and is forgotten', (tester) async {
      final (:game, socket: _) = await pumpGame(tester);
      game.emote(EmoteKind.party);
      await tick(tester, frames: 2);
      expect(game.emotes.count, equals(1));

      // Emotes are ephemeral: nothing keeps them, nothing replays them.
      await tick(tester, frames: 130);

      expect(game.emotes.count, isZero);
    });
  });

  group('nametags', () {
    NametagLayer layerOf(ConferenceGame game) =>
        game.world.children.whereType<NametagLayer>().single;

    /// The tags belonging to actual people.
    ///
    /// The layer names the bots by the same rules it names players by — which
    /// is the point of them — so the atrium's own two beans turn up in every
    /// one of these lists. These tests are about the *rules*, and the rules
    /// are easier to state about a crowd the test put there.
    List<VisibleTag> playerTags(NametagLayer layer) => [
      for (final tag in layer.visibleTags())
        if (!tag.id.startsWith(NametagLayer.botTagPrefix)) tag,
    ];

    /// Puts [count] beans in a tight cluster around the local bean.
    Future<void> crowd(
      WidgetTester tester,
      ConferenceGame game,
      FakeSocket socket,
      int count, {
      double spread = 30,
    }) async {
      final players = [
        for (var i = 0; i < count; i++)
          _player(
            'p$i',
            game.bean.position.x + (i % 8) * (spread / 8),
            game.bean.position.y + (i ~/ 8) * (spread / 8),
            name: 'Attendee $i',
          ),
      ];
      socket.emit(
        SnapshotMessage(
          appeared: players,
          positions: [
            for (final player in players)
              PlayerPosition(id: player.id, x: player.x, y: player.y),
          ],
        ),
      );
      await tick(tester, frames: 24);
    }

    testWidgets('a nearby name is fully solid', (tester) async {
      final (:game, :socket) = await pumpGame(tester);
      await crowd(tester, game, socket, 1);

      final tags = playerTags(layerOf(game));

      expect(tags, hasLength(1));
      expect(tags.single.name, equals('Attendee 0'));
      expect(tags.single.alpha, equals(1));
    });

    testWidgets('somebody the server sent but who is far away gets no tag', (
      tester,
    ) async {
      // The tag radius is deliberately far tighter than the sync radius: the
      // server sends everybody within a 3x3 grid block, which is most of a
      // screen and then some.
      final (:game, :socket) = await pumpGame(tester);
      socket.emit(
        SnapshotMessage(
          appeared: [_player('p1', game.bean.position.x + 400, 600)],
          positions: [
            PlayerPosition(id: 'p1', x: game.bean.position.x + 400, y: 600),
          ],
        ),
      );
      await tick(tester, frames: 24);

      expect(playerTags(layerOf(game)), isEmpty);
      expect(game.remotePlayers.count, equals(1), reason: 'still drawn');
    });

    testWidgets('a name fades with distance rather than blinking out', (
      tester,
    ) async {
      final (:game, :socket) = await pumpGame(tester);
      final layer = layerOf(game);
      final middle = (layer.fullRadius + layer.fadeRadius) / 2;
      socket.emit(
        SnapshotMessage(
          appeared: [_player('p1', game.bean.position.x + middle, 600)],
          positions: [
            PlayerPosition(id: 'p1', x: game.bean.position.x + middle, y: 600),
          ],
        ),
      );
      await tick(tester, frames: 24);

      final alpha = playerTags(layer).single.alpha;

      expect(alpha, greaterThan(0));
      expect(alpha, lessThan(1));
    });

    testWidgets('a name is gone once somebody is more than two tiles away', (
      tester,
    ) async {
      // Two tiles is arm's length in this world: a name you can read from
      // across the hall is a label on a stranger, not on somebody you are
      // talking to.
      final (:game, :socket) = await pumpGame(tester);
      final layer = layerOf(game);
      const justOutside = FloorComponent.gridStep * 2 + 1;
      final x = game.bean.position.x + justOutside;
      socket.emit(
        SnapshotMessage(
          appeared: [_player('p1', x, game.bean.position.y)],
          positions: [PlayerPosition(id: 'p1', x: x, y: game.bean.position.y)],
        ),
      );
      await tick(tester, frames: 24);

      expect(layer.fadeRadius, equals(FloorComponent.gridStep * 2));
      expect(playerTags(layer), isEmpty);
      expect(game.remotePlayers.count, equals(1), reason: 'still drawn');
    });

    testWidgets('a crowd is capped, nearest first', (tester) async {
      // The real case, and the one a three-player demo never shows: forty
      // people packed into the atrium at spawn. Forty overlapping labels is a
      // grey smear that hides the beans underneath.
      final (:game, :socket) = await pumpGame(tester);
      await crowd(tester, game, socket, 40);

      final tags = layerOf(game).visibleTags();

      expect(game.remotePlayers.count, equals(40));
      expect(tags, hasLength(NametagLayer.defaultMaxTags));
      // Forty people standing on your toes beat the two beans wandering the
      // atrium: the cap is nearest-first, and it does not play favourites
      // between a person and a bot.
      expect(playerTags(layerOf(game)), hasLength(tags.length));
      // Sorted nearest first, so the cap keeps the people you are standing
      // with rather than an arbitrary ten.
      for (var i = 1; i < tags.length; i++) {
        expect(
          tags[i].distanceSquared,
          greaterThanOrEqualTo(tags[i - 1].distanceSquared),
        );
      }
    });
  });

  group('the chai counter crowd glow', () {
    testWidgets('brightens when people stand on it', (tester) async {
      final (:game, :socket) = await pumpGame(tester);
      expect(game.crowdGlow.glow, isZero);

      game.bean.position.setValues(
        WorldLayout.courtGlowX,
        WorldLayout.courtGlowY,
      );
      socket.emit(
        SnapshotMessage(
          appeared: [
            _player('p1', WorldLayout.courtGlowX + 10, WorldLayout.courtGlowY),
            _player('p2', WorldLayout.courtGlowX - 10, WorldLayout.courtGlowY),
          ],
          positions: const [
            PlayerPosition(
              id: 'p1',
              x: WorldLayout.courtGlowX + 10,
              y: WorldLayout.courtGlowY,
            ),
            PlayerPosition(
              id: 'p2',
              x: WorldLayout.courtGlowX - 10,
              y: WorldLayout.courtGlowY,
            ),
          ],
        ),
      );
      await tick(tester, frames: 90);

      expect(game.crowdGlow.glow, greaterThan(0.2));
    });

    testWidgets('is ambient — it fades again, it does not score anything', (
      tester,
    ) async {
      final (:game, socket: _) = await pumpGame(tester);
      game.bean.position.setValues(
        WorldLayout.courtGlowX,
        WorldLayout.courtGlowY,
      );
      await tick(tester, frames: 60);
      final lit = game.crowdGlow.glow;

      game.bean.position.setValues(spawnCenterX, spawnCenterY);
      await tick(tester, frames: 120);

      expect(lit, greaterThan(0));
      expect(game.crowdGlow.glow, lessThan(0.02));
    });
  });

  group('the pool', () {
    /// Walks the bean out of the pool and back in, the long way round.
    Future<void> dive(WidgetTester tester, ConferenceGame game) async {
      await standAt(
        tester,
        game,
        WorldLayout.pool.centerX,
        WorldLayout.pool.top - 40,
      );
      await standAt(
        tester,
        game,
        WorldLayout.pool.centerX,
        WorldLayout.pool.centerY,
      );
    }

    testWidgets('you can swim in it, and it slows you down', (tester) async {
      final (:game, socket: _) = await pumpGame(tester);

      await dive(tester, game);
      await tick(tester, frames: 40);

      expect(game.bean.swim.submersion, greaterThan(0.8));
      expect(game.water.watcher.isSwimming('local:me'), isTrue);

      // Hold right for a second in the water, then the same on dry deck, and
      // compare how far the bean actually got.
      game.onKeyEvent(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowRight,
          physicalKey: PhysicalKeyboardKey.keyD,
          timeStamp: Duration.zero,
        ),
        {LogicalKeyboardKey.arrowRight},
      );
      final wetStart = game.bean.position.x;
      await tick(tester, frames: 30);
      final wetDistance = game.bean.position.x - wetStart;

      await standAt(
        tester,
        game,
        WorldLayout.pool.left - 120,
        WorldLayout.pool.centerY,
      );
      await tick(tester, frames: 30);
      final dryStart = game.bean.position.x;
      await tick(tester, frames: 30);
      final dryDistance = game.bean.position.x - dryStart;

      expect(wetDistance, greaterThan(0), reason: 'the bean was stuck');
      expect(
        wetDistance,
        lessThan(dryDistance * 0.85),
        reason: 'swimming was not slower than walking',
      );
    });

    testWidgets('a dive splashes, once, and the splash decays', (
      tester,
    ) async {
      final (:game, socket: _) = await pumpGame(tester);
      expect(game.water.field.liveCount, isZero);

      await dive(tester, game);
      await tick(tester, frames: 2);

      final burst = game.water.field.liveCount;
      expect(burst, inInclusiveRange(10, 14));

      // Standing still in the water: wakes keep coming, but no second burst.
      await tick(tester, frames: 90);
      expect(
        game.water.field.liveCount,
        lessThan(burst),
        reason: 'the pool is machine-gunning splashes',
      );
      expect(
        game.water.field.liveCount,
        lessThanOrEqualTo(SplashField.defaultCapacity),
      );
    });

    testWidgets('twenty beans in the pool stay inside the cap', (tester) async {
      // The exit criterion, in a test: twenty simultaneous dives is 280
      // droplets asked for and at most 120 alive.
      final (:game, :socket) = await pumpGame(tester);
      final crowd = [
        for (var i = 0; i < 20; i++)
          _player(
            'swimmer$i',
            WorldLayout.pool.left - 60 + i.toDouble(),
            WorldLayout.pool.centerY,
          ),
      ];
      socket.emit(
        SnapshotMessage(
          appeared: crowd,
          positions: [
            for (final p in crowd) PlayerPosition(id: p.id, x: p.x, y: p.y),
          ],
        ),
      );
      await tick(tester, frames: 20);

      socket.emit(
        SnapshotMessage(
          positions: [
            for (var i = 0; i < 20; i++)
              PlayerPosition(
                id: 'swimmer$i',
                x: WorldLayout.pool.centerX,
                y: WorldLayout.pool.centerY,
              ),
          ],
        ),
      );
      await tick(tester, frames: 30);

      expect(
        game.water.field.liveCount,
        lessThanOrEqualTo(SplashField.defaultCapacity),
      );
    });

    testWidgets('swimming puts nothing new on the wire', (tester) async {
      // The whole point of deriving swimming from position: a second device
      // sees the dive because it runs the same `WorldLayout` code, not
      // because anything was sent. Checked against the message log rather
      // than by eye, which is what the exit criteria ask for.
      final (:game, :socket) = await pumpGame(tester);
      socket.sent.clear();

      await dive(tester, game);
      await tick(tester, frames: 120);

      expect(socket.sent, isNotEmpty, reason: 'the bean never reported in');
      for (final message in socket.sentMessages) {
        expect(
          message,
          isA<MoveMessage>(),
          reason: 'swimming added ${message.runtimeType} to the wire',
        );
      }
    });

    testWidgets('a remote bean swims without being told to', (tester) async {
      final (:game, :socket) = await pumpGame(tester);
      socket.emit(
        SnapshotMessage(
          appeared: [
            _player('p1', WorldLayout.pool.centerX, WorldLayout.pool.top - 60),
          ],
          positions: [
            PlayerPosition(
              id: 'p1',
              x: WorldLayout.pool.centerX,
              y: WorldLayout.pool.top - 60,
            ),
          ],
        ),
      );
      await tick(tester, frames: 20);
      expect(game.remotePlayers.beanOf('p1')!.swim.submersion, isZero);

      socket.emit(
        SnapshotMessage(
          positions: [
            PlayerPosition(
              id: 'p1',
              x: WorldLayout.pool.centerX,
              y: WorldLayout.pool.centerY,
            ),
          ],
        ),
      );
      await tick(tester, frames: 60);

      expect(
        game.remotePlayers.beanOf('p1')!.swim.submersion,
        greaterThan(0.8),
      );
      expect(game.water.watcher.isSwimming('p1'), isTrue);
    });
  });

  group('the HUD boundary', () {
    testWidgets('a dropped connection clears the world but not your bean', (
      tester,
    ) async {
      final (:game, :socket) = await pumpGame(tester);
      socket.emit(
        SnapshotMessage(
          appeared: [_player('p1', 820, 600)],
          positions: const [PlayerPosition(id: 'p1', x: 820, y: 600)],
        ),
      );
      await tick(tester, frames: 4);
      game.emote(EmoteKind.wave);
      final where = game.bean.position.clone();

      socket.dropFromServer();
      await tick(tester, frames: 8);

      expect(game.remotePlayers.count, isZero);
      expect(game.emotes.count, isZero);
      expect(game.bean.position, equals(where));
    });

    testWidgets('the game does not dispose a hud it was handed', (
      tester,
    ) async {
      // The widget listening to these notifiers and the game writing to them
      // are torn down in an order neither controls, so ownership is the
      // screen's and never the game's.
      final hud = WorldHud();
      addTearDown(hud.dispose);
      final game = ConferenceGame(hud: hud, spawnAngle: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameWidget(game: game)),
        ),
      );
      await tick(tester, frames: 4);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(() => hud.online.value = 3, returnsNormally);
    });
  });
}
