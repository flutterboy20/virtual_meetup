import 'dart:math';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  // Session ids are what decide whether a join is a new person or the same
  // person coming back, so every test that wants a *new* player has to ask
  // with a new session id. This counter is that, and forgetting it is the
  // bug the whole re-seat mechanism is built to cause on purpose.
  var sessionCounter = 0;
  String nextSessionId() =>
      (++sessionCounter).toRadixString(16).padLeft(sessionIdLength, '0');

  JoinMessage newJoin({
    String? sessionId,
    String name = 'Alice',
    int color = 0xFF54C5F8,
    PlayerCosmetic cosmetic = PlayerCosmetic.cap,
  }) => JoinMessage(
    sessionId: sessionId ?? nextSessionId(),
    name: name,
    color: color,
    cosmetic: cosmetic,
  );

  // A seeded Random makes spawn points deterministic, so these tests assert on
  // real behaviour instead of "somewhere in the world, probably".
  PlayerRegistry newRegistry() => PlayerRegistry(random: Random(1));

  /// Seats a brand-new player and returns them.
  PlayerState seatSomebody(PlayerRegistry registry) =>
      registry.seat(newJoin()).player;

  group('seat', () {
    test('assigns an id the client never chose', () {
      final registry = newRegistry();

      final first = seatSomebody(registry);
      final second = seatSomebody(registry);

      expect(first.id, isNotEmpty);
      expect(second.id, isNot(equals(first.id)));
    });

    test('keeps the look the client asked for', () {
      final player = seatSomebody(newRegistry());

      expect(player.name, equals('Alice'));
      expect(player.color, equals(0xFF54C5F8));
      expect(player.cosmetic, equals(PlayerCosmetic.cap));
    });

    test('spawns inside the playable world', () {
      final registry = newRegistry();

      for (var i = 0; i < 50; i++) {
        final player = seatSomebody(registry);
        expect(player.x, inInclusiveRange(0, worldWidth));
        expect(player.y, inInclusiveRange(0, worldHeight));
        expect(player.x, equals(clampWorldX(player.x)));
        expect(player.y, equals(clampWorldY(player.y)));
      }
    });

    test('does not pile everybody on one spawn point', () {
      final registry = newRegistry();

      final spawns = List.generate(
        20,
        (_) => seatSomebody(registry),
      ).map((player) => '${player.x},${player.y}').toSet();

      expect(spawns.length, greaterThan(1));
    });

    test('counts the player', () {
      final registry = newRegistry()..seat(newJoin());

      expect(registry.count, equals(1));
      expect(registry.players.single.name, equals('Alice'));
    });
  });

  group('setBoard', () {
    test('records the flag and hands back the rewritten state', () {
      final registry = newRegistry();
      final player = seatSomebody(registry);

      final updated = registry.setBoard(player.id, hasBoard: true);

      expect(updated?.hasBoard, isTrue);
      expect(registry[player.id]?.hasBoard, isTrue);
      // Everything else about them is untouched.
      expect(updated?.x, equals(player.x));
      expect(updated?.name, equals(player.name));
    });

    test('a player starts without one', () {
      expect(seatSomebody(newRegistry()).hasBoard, isFalse);
    });

    test('putting it down clears the flag', () {
      final registry = newRegistry();
      final player = seatSomebody(registry);

      registry
        ..setBoard(player.id, hasBoard: true)
        ..setBoard(player.id, hasBoard: false);

      expect(registry[player.id]?.hasBoard, isFalse);
    });

    test('an unknown id is null, exactly like move', () {
      expect(newRegistry().setBoard('nobody', hasBoard: true), isNull);
    });

    test('a move keeps the board', () {
      final registry = newRegistry();
      final player = seatSomebody(registry);
      registry.setBoard(player.id, hasBoard: true);

      expect(registry.move(player.id, 300, 400)?.hasBoard, isTrue);
    });

    test('a re-seat keeps the board', () {
      final registry = newRegistry();
      final session = nextSessionId();
      final player = registry.seat(newJoin(sessionId: session)).player;
      registry.setBoard(player.id, hasBoard: true);

      final again = registry.seat(newJoin(sessionId: session));

      expect(again.kind, equals(SeatKind.reseated));
      expect(again.player.hasBoard, isTrue);
    });

    test('a resume inside the linger window keeps the board', () {
      final registry = newRegistry();
      final session = nextSessionId();
      final player = registry.seat(newJoin(sessionId: session)).player;
      registry
        ..setBoard(player.id, hasBoard: true)
        ..remove(player.id);

      final again = registry.seat(newJoin(sessionId: session));

      expect(again.kind, equals(SeatKind.resumed));
      expect(again.player.hasBoard, isTrue);
    });

    test('a rename keeps the board', () {
      final registry = newRegistry();
      final player = seatSomebody(registry);
      registry.setBoard(player.id, hasBoard: true);

      expect(registry.rename(player.id, 'Attendee')?.hasBoard, isTrue);
    });
  });

  group('move', () {
    test('records a reported position', () {
      final registry = newRegistry();
      final player = seatSomebody(registry);

      final moved = registry.move(player.id, 300, 400);

      expect(moved?.x, equals(300));
      expect(moved?.y, equals(400));
      expect(registry[player.id]?.x, equals(300));
    });

    test('clamps a position outside the world instead of dropping it', () {
      final registry = newRegistry();
      final player = seatSomebody(registry);

      final moved = registry.move(player.id, -9999, 9999);

      expect(moved?.x, equals(clampWorldX(-9999)));
      expect(moved?.y, equals(clampWorldY(9999)));
    });

    test('leaves everything but the position alone', () {
      final registry = newRegistry();
      final player = seatSomebody(registry);

      final moved = registry.move(player.id, 10, 10);

      expect(moved?.name, equals(player.name));
      expect(moved?.color, equals(player.color));
      expect(moved?.cosmetic, equals(player.cosmetic));
    });

    test('returns null for a player who is not here', () {
      expect(newRegistry().move('nobody', 1, 1), isNull);
    });
  });

  group('remove', () {
    test('takes the player out and returns their last state', () {
      final registry = newRegistry();
      final player = seatSomebody(registry);

      expect(registry.remove(player.id)?.id, equals(player.id));
      expect(registry.count, isZero);
      expect(registry[player.id], isNull);
    });

    test('removing an unknown id is not an error', () {
      expect(newRegistry().remove('nobody'), isNull);
    });
  });

  group('the interest index', () {
    // The registry owns the grid so the two cannot drift: every write to a
    // position is also a write to the index, through one code path.
    PlayerRegistry gridRegistry() =>
        PlayerRegistry(random: Random(1), cellSize: 100);

    test('a joined player is indexed at their spawn point', () {
      final registry = gridRegistry();

      final player = seatSomebody(registry);

      expect(registry.grid.count, equals(1));
      expect(
        registry.grid.cellOfId(player.id),
        equals(registry.grid.cellAt(player.x, player.y)),
      );
    });

    test('near excludes the asking player', () {
      final registry = gridRegistry();
      final first = seatSomebody(registry);
      final second = seatSomebody(registry);
      registry
        ..move(first.id, 150, 150)
        ..move(second.id, 160, 160);

      expect(
        registry.near(150, 150, exceptId: first.id).map((p) => p.id),
        equals([second.id]),
      );
    });

    test('a move re-files the player in the index', () {
      final registry = gridRegistry();
      final player = seatSomebody(registry);

      registry.move(player.id, 150, 150);

      expect(registry.grid.cellOfId(player.id), equals((1, 1)));
      expect(registry.near(1000, 1000), isEmpty);
      expect(registry.near(150, 150).single.id, equals(player.id));
    });

    test(
      'a clamped move indexes the clamped position, not the reported one',
      () {
        final registry = gridRegistry();
        final player = seatSomebody(registry);

        registry.move(player.id, 99999, 99999);

        expect(
          registry.near(clampWorldX(99999), clampWorldY(99999)).single.id,
          equals(player.id),
        );
      },
    );

    test('a removed player leaves the index too', () {
      final registry = gridRegistry();
      final player = seatSomebody(registry);
      registry
        ..move(player.id, 150, 150)
        ..remove(player.id);

      expect(registry.grid.count, isZero);
      expect(registry.near(150, 150), isEmpty);
    });
  });

  group('sanitizeName', () {
    test('trims and collapses whitespace', () {
      expect(sanitizeName('  Alice   B  '), equals('Alice B'));
    });

    test('is the shared normaliser, not a second set of rules', () {
      // The rules that *reject* a name live in protocol/ and run in the
      // relay. Two copies of them is how a client and a server drift apart.
      expect(sanitizeName('  Alice   B  '), equals(normalizeName('Alice B')));
    });

    test('is applied on seat', () {
      final player = newRegistry().seat(newJoin(name: '  Ada   L  ')).player;

      expect(player.name, equals('Ada L'));
    });
  });

  group('sessions', () {
    test('a new session gets a new seat', () {
      final registry = newRegistry();

      final first = registry.seat(newJoin());
      final second = registry.seat(newJoin());

      expect(first.kind, equals(SeatKind.fresh));
      expect(second.kind, equals(SeatKind.fresh));
      expect(second.player.id, isNot(equals(first.player.id)));
      expect(registry.count, equals(2));
    });

    test('a live session re-seats instead of duplicating', () {
      // The re-seat race: the client came back before the server noticed the
      // old socket had died. Two beans for one person is the bug.
      final registry = newRegistry();
      final session = nextSessionId();

      final first = registry.seat(newJoin(sessionId: session));
      final again = registry.seat(newJoin(sessionId: session));

      expect(again.kind, equals(SeatKind.reseated));
      expect(again.player.id, equals(first.player.id));
      expect(registry.count, equals(1));
    });

    test('a re-seat keeps the player standing where they were', () {
      final registry = newRegistry();
      final session = nextSessionId();
      final player = registry.seat(newJoin(sessionId: session)).player;
      registry.move(player.id, 300, 400);

      final again = registry.seat(newJoin(sessionId: session));

      expect(again.player.x, equals(300));
      expect(again.player.y, equals(400));
    });

    test('a returning session inside the window resumes its old seat', () {
      var now = DateTime(2026);
      final registry = PlayerRegistry(
        random: Random(1),
        linger: const Duration(seconds: 60),
        now: () => now,
      );
      final session = nextSessionId();
      final player = registry
          .seat(
            JoinMessage(
              sessionId: session,
              name: 'Alice',
              color: 1,
              cosmetic: PlayerCosmetic.cap,
            ),
          )
          .player;
      registry
        ..move(player.id, 300, 400)
        ..remove(player.id);

      expect(registry.count, isZero, reason: 'no ghost stands in the world');
      expect(registry.heldSeatCount, equals(1));

      now = now.add(const Duration(seconds: 30));
      final back = registry.seat(
        JoinMessage(
          sessionId: session,
          name: 'Alice',
          color: 1,
          cosmetic: PlayerCosmetic.cap,
        ),
      );

      expect(back.kind, equals(SeatKind.resumed));
      expect(back.player.id, equals(player.id));
      expect(back.player.x, equals(300));
      expect(back.player.y, equals(400));
      expect(registry.heldSeatCount, isZero);
      // A resumed player has to be back in the interest index, or nobody
      // standing next to them can see them.
      expect(registry.near(300, 400).single.id, equals(player.id));
    });

    test('a session that comes back too late is a new player', () {
      var now = DateTime(2026);
      final registry = PlayerRegistry(
        random: Random(1),
        linger: const Duration(seconds: 60),
        now: () => now,
      );
      final session = nextSessionId();
      final player = registry
          .seat(
            JoinMessage(
              sessionId: session,
              name: 'Alice',
              color: 1,
              cosmetic: PlayerCosmetic.cap,
            ),
          )
          .player;
      registry.remove(player.id);

      now = now.add(const Duration(seconds: 61));
      final back = registry.seat(
        JoinMessage(
          sessionId: session,
          name: 'Alice',
          color: 1,
          cosmetic: PlayerCosmetic.cap,
        ),
      );

      expect(back.kind, equals(SeatKind.fresh));
      expect(back.player.id, isNot(equals(player.id)));
      expect(registry.heldSeatCount, isZero);
    });

    test('reports a changed look so neighbours can be told', () {
      final registry = newRegistry();
      final session = nextSessionId();
      registry.seat(newJoin(sessionId: session));

      final same = registry.seat(newJoin(sessionId: session));
      final renamed = registry.seat(newJoin(sessionId: session, name: 'Ada'));

      expect(same.appearanceChanged, isFalse);
      expect(renamed.appearanceChanged, isTrue);
      expect(renamed.player.name, equals('Ada'));
    });

    test('seatOfSession names the seat a live session holds', () {
      final registry = newRegistry();
      final session = nextSessionId();

      expect(registry.seatOfSession(session), isNull);
      final player = registry.seat(newJoin(sessionId: session)).player;
      expect(registry.seatOfSession(session), equals(player.id));

      registry.remove(player.id);
      expect(registry.seatOfSession(session), isNull);
    });

    test('leaving does not hold a seat for a socket that never joined', () {
      final registry = newRegistry()..remove('nobody');

      expect(registry.heldSeatCount, isZero);
    });
  });

  group('sanitizeColor', () {
    test('forces full alpha so no bean can be invisible', () {
      expect(sanitizeColor(0x00000000), equals(0xFF000000));
      expect(sanitizeColor(0x0054C5F8), equals(0xFF54C5F8));
    });

    test('masks anything wider than 32 bits', () {
      expect(sanitizeColor(-1), equals(0xFFFFFFFF));
      expect(sanitizeColor(0x1234FF54C5F8), equals(0xFF54C5F8));
    });
  });

  group('spawning', () {
    test('everybody arrives in the atrium, on the ring', () {
      final registry = PlayerRegistry(random: Random(7));

      for (var i = 0; i < 200; i++) {
        final player = registry
            .seat(
              JoinMessage(
                sessionId: i.toRadixString(16).padLeft(sessionIdLength, '0'),
                name: 'Guest $i',
                color: 0xFF54C5F8,
                cosmetic: PlayerCosmetic.none,
              ),
            )
            .player;

        // In the atrium, because the social premise of the whole thing is
        // that the first thing you see is other people.
        expect(WorldZone.at(player.x, player.y), equals(WorldZone.atrium));
        expect(isOnFloor(player.x, player.y), isTrue);

        // On the ring, because the credit pillar stands at the exact centre.
        final dx = player.x - spawnCenterX;
        final dy = player.y - spawnCenterY;
        final radius = sqrt(dx * dx + dy * dy);
        expect(radius, greaterThan(spawnRingRadius * 0.7));
        expect(radius, lessThanOrEqualTo(spawnRingRadius));
      }
    });

    test('two arrivals do not land on the same spot', () {
      final registry = PlayerRegistry(random: Random(3));
      JoinMessage joinAs(int i) => JoinMessage(
        sessionId: i.toRadixString(16).padLeft(sessionIdLength, '0'),
        name: 'Guest $i',
        color: 0xFF54C5F8,
        cosmetic: PlayerCosmetic.none,
      );

      final first = registry.seat(joinAs(1)).player;
      final second = registry.seat(joinAs(2)).player;

      expect(first.x == second.x && first.y == second.y, isFalse);
    });
  });
}
