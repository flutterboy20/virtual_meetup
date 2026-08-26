import 'package:client/game/bean_component.dart';
import 'package:client/game/remote_players.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

void main() {
  const alice = PlayerState(
    id: 'p1',
    name: 'Alice',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
    x: 100,
    y: 200,
  );
  const bob = PlayerState(
    id: 'p2',
    name: 'Bob',
    color: 0xFF7ED9B6,
    cosmetic: PlayerCosmetic.headphones,
    x: 300,
    y: 400,
  );

  /// A snapshot announcing [players] and placing them where they say they are.
  SnapshotMessage arrival(List<PlayerState> players) => SnapshotMessage(
    appeared: players,
    positions: players
        .map(
          (player) => PlayerPosition(id: player.id, x: player.x, y: player.y),
        )
        .toList(growable: false),
  );

  /// A snapshot moving [id] to ([x], [y]).
  SnapshotMessage moved(String id, double x, double y) => SnapshotMessage(
    positions: [PlayerPosition(id: id, x: x, y: y)],
  );

  /// Mounts a [RemotePlayers] in a bare game and returns it.
  Future<RemotePlayers> mount(FlameGame game) async {
    final remotes = RemotePlayers(maxSpeed: 140);
    await game.world.add(remotes);
    await game.ready();
    return remotes;
  }

  /// Runs [seconds] of game loop at 60fps.
  void run(RemotePlayers remotes, double seconds) {
    for (var i = 0; i < (seconds * 60).round(); i++) {
      remotes.update(1 / 60);
    }
  }

  group('appearing', () {
    testWithGame<FlameGame>(
      'adds a bean for each player who comes into range',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);

        remotes.apply(arrival([alice, bob]));
        await game.ready();

        expect(remotes.count, 2);
        expect(remotes.beans.keys, containsAll(<String>['p1', 'p2']));
        expect(remotes.children.whereType<BeanComponent>().length, 2);
      },
    );

    testWithGame<FlameGame>(
      'places each bean where the server said',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);

        remotes.apply(arrival([alice]));

        expect(remotes.beans['p1']!.position, Vector2(100, 200));
      },
    );

    testWithGame<FlameGame>(
      'dresses each bean in its own colour and hat',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);

        remotes.apply(arrival([alice, bob]));

        expect(
          remotes.beans['p1']!.appearance.bodyColor.toARGB32(),
          alice.color,
        );
        expect(remotes.beans['p2']!.appearance.cosmetic, bob.cosmetic);
      },
    );

    testWithGame<FlameGame>(
      'a repeated appearance does not duplicate a bean',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);

        remotes
          ..apply(arrival([alice]))
          ..apply(arrival([alice]));
        await game.ready();

        expect(remotes.count, 1);
        expect(remotes.children.whereType<BeanComponent>().length, 1);
      },
    );

    testWithGame<FlameGame>(
      'a new bean does not slide in from somewhere else',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        run(remotes, 1);

        remotes.apply(arrival([alice]));
        run(remotes, 0.5);

        // It stands where it appeared until it has somewhere newer to be.
        expect(remotes.beans['p1']!.position, Vector2(100, 200));
      },
    );
  });

  group('interpolation', () {
    testWithGame<FlameGame>(
      'draws a bean between the last two reported positions',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice]));

        // Two snapshots one server tick apart, then enough frames for the
        // render head — which runs `interpolationDelay` behind — to reach
        // the midpoint between them.
        run(remotes, 1 / 15);
        remotes.apply(moved('p1', 200, 200));
        run(remotes, 1 / 15);

        expect(remotes.renderTime, closeTo(1 / 30, 0.001));
        expect(remotes.beans['p1']!.position.x, closeTo(150, 0.001));
      },
    );

    testWithGame<FlameGame>(
      'moves every frame, not once per snapshot',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice]));

        // A server tick every four frames, a bean walking steadily right —
        // which is what 15Hz data feeding a 60fps renderer looks like.
        final seen = <double>{};
        var x = 100.0;
        for (var frame = 0; frame < 36; frame++) {
          if (frame % 4 == 0) {
            x += 10;
            remotes.apply(moved('p1', x, 200));
          }
          remotes.update(1 / 60);
          seen.add(remotes.beans['p1']!.position.x);
        }

        // Steppy motion would produce a handful of distinct positions; smooth
        // motion produces one per frame.
        expect(seen.length, greaterThan(20));
      },
    );

    testWithGame<FlameGame>(
      'ends up at the reported position, not near it',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice]));
        run(remotes, 1 / 15);
        remotes.apply(moved('p1', 150, 250));

        // Long enough for the render head to pass the newest sample.
        run(remotes, 1);

        expect(remotes.beans['p1']!.position, Vector2(150, 250));
      },
    );

    testWithGame<FlameGame>(
      'a missing snapshot holds the bean still instead of stuttering',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice]));
        run(remotes, 1 / 15);
        remotes.apply(moved('p1', 120, 200));
        run(remotes, 0.5);
        final held = remotes.beans['p1']!.position.clone();

        // Silence, then the delayed snapshot finally lands.
        run(remotes, 0.3);
        expect(remotes.beans['p1']!.position, held);

        remotes.apply(moved('p1', 140, 200));
        run(remotes, 1);

        expect(remotes.beans['p1']!.position, Vector2(140, 200));
      },
    );

    testWithGame<FlameGame>(
      'gives the bean a velocity so it animates',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice]));
        run(remotes, 1 / 15);
        remotes.apply(moved('p1', 200, 200));
        run(remotes, 1 / 15);

        expect(remotes.beans['p1']!.velocity.x, greaterThan(0));
        expect(remotes.beans['p1']!.velocity.y, isZero);
      },
    );

    testWithGame<FlameGame>(
      'never reports more than the top speed',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice]));
        run(remotes, 1 / 15);

        // A teleport across the world would otherwise imply a wild velocity
        // and a bean squashed flat for a frame.
        remotes.apply(moved('p1', 1500, 1100));
        run(remotes, 1 / 15);

        expect(
          remotes.beans['p1']!.velocity.length,
          lessThanOrEqualTo(140.001),
        );
      },
    );

    testWithGame<FlameGame>(
      'a bean that stopped walking stops animating',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice]));
        run(remotes, 1 / 15);
        remotes.apply(moved('p1', 110, 200));

        run(remotes, 1);

        expect(remotes.beans['p1']!.velocity.length, lessThan(1));
      },
    );

    testWithGame<FlameGame>(
      'ignores a position for somebody it was never told about',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);

        remotes.apply(moved('ghost', 1, 2));

        expect(remotes.count, isZero);
      },
    );
  });

  group('leaving', () {
    testWithGame<FlameGame>(
      'removes a player who walked out of range',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice, bob]));
        await game.ready();

        remotes.apply(const SnapshotMessage(outOfRange: ['p1']));
        await game.ready();

        expect(remotes.beans.keys, equals(<String>['p2']));
        expect(remotes.children.whereType<BeanComponent>().length, 1);
      },
    );

    testWithGame<FlameGame>(
      'removes a player who left the world',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice, bob]));
        await game.ready();

        remotes.apply(const PlayerLeftMessage(id: 'p1'));
        await game.ready();

        expect(remotes.beans.keys, equals(<String>['p2']));
      },
    );

    testWithGame<FlameGame>(
      'a removal for somebody unknown is harmless',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);

        expect(
          () => remotes
            ..apply(const PlayerLeftMessage(id: 'ghost'))
            ..apply(const SnapshotMessage(outOfRange: ['ghost'])),
          returnsNormally,
        );
      },
    );

    testWithGame<FlameGame>(
      'somebody who walks back in restarts from where they re-appeared',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice]));
        run(remotes, 0.5);
        remotes.apply(const SnapshotMessage(outOfRange: ['p1']));
        await game.ready();

        // Back, in a completely different corner of the world. The bean must
        // appear there, not glide across the map from where it used to be.
        remotes.apply(
          arrival([
            const PlayerState(
              id: 'p1',
              name: 'Alice',
              color: 0xFF54C5F8,
              cosmetic: PlayerCosmetic.cap,
              x: 900,
              y: 900,
            ),
          ]),
        );
        await game.ready();
        run(remotes, 0.5);

        expect(remotes.beans['p1']!.position, Vector2(900, 900));
      },
    );
  });

  group('welcome', () {
    testWithGame<FlameGame>(
      'starts a fresh, empty world',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice, bob]));
        await game.ready();

        // A welcome is a new session, e.g. after a reconnect. Who is nearby
        // arrives in the next snapshot.
        remotes.apply(const WelcomeMessage(yourId: 'me'));
        await game.ready();

        expect(remotes.count, isZero);
        expect(remotes.children.whereType<BeanComponent>(), isEmpty);
      },
    );
  });

  group('messages it does not own', () {
    testWithGame<FlameGame>(
      'ignores client-to-server and unknown messages',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);

        remotes
          ..apply(
            const JoinMessage(
              sessionId: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
              name: 'Alice',
              color: 0xFF54C5F8,
              cosmetic: PlayerCosmetic.cap,
            ),
          )
          ..apply(const MoveMessage(x: 1, y: 2))
          ..apply(const UnknownMessage(reason: 'unknown message type'));

        expect(remotes.count, isZero);
      },
    );
  });

  group('a moderator rename', () {
    testWithGame<FlameGame>(
      'changes the name over a bean already on screen',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice, bob]));
        await game.ready();

        remotes.apply(
          const PlayerRenamedMessage(id: 'p1', name: 'Guest'),
        );

        final names = {
          for (final view in remotes.views) view.id: view.name,
        };
        expect(names['p1'], equals('Guest'));
        expect(names['p2'], equals('Bob'));
      },
    );

    testWithGame<FlameGame>(
      'leaves the bean itself alone',
      FlameGame.new,
      (game) async {
        // A rename is a name and nothing else: it must not move anybody or
        // reset the history their motion is interpolated from.
        final remotes = await mount(game);
        remotes.apply(arrival([alice]));
        await game.ready();

        remotes.apply(
          const PlayerRenamedMessage(id: 'p1', name: 'Guest'),
        );

        expect(remotes.count, equals(1));
        expect(remotes.beanOf('p1'), isNotNull);
      },
    );

    testWithGame<FlameGame>(
      'is ignored for somebody out of view',
      FlameGame.new,
      (game) async {
        // Safe to drop: the next snapshot carries the current name on
        // appearance, so walking up to them shows the right one anyway.
        final remotes = await mount(game);

        remotes.apply(
          const PlayerRenamedMessage(id: 'nobody', name: 'Guest'),
        );

        expect(remotes.count, isZero);
      },
    );
  });

  group('clear', () {
    testWithGame<FlameGame>(
      'empties the world of other people',
      FlameGame.new,
      (game) async {
        final remotes = await mount(game);
        remotes.apply(arrival([alice, bob]));
        await game.ready();

        remotes.clear();
        await game.ready();

        expect(remotes.count, isZero);
        expect(remotes.children.whereType<BeanComponent>(), isEmpty);
      },
    );
  });
}
