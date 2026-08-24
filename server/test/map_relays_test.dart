import 'dart:convert';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// A socket that records what the relay wrote to it.
class FakeConnection implements PlayerConnection {
  final List<String> sent = [];
  bool closed = false;

  @override
  void send(String data) => sent.add(data);

  @override
  void close() => closed = true;
}

/// Every message this socket was sent, decoded.
Iterable<ProtocolMessage> received(FakeConnection socket) =>
    socket.sent.map(decodeMessage);

void main() {
  // 32 lowercase hex characters, because the server checks the shape of a
  // session id before it will key anything on one.
  const alice = 'aaaa1111bbbb2222cccc3333dddd4444';
  const bob = 'ffff9999eeee8888dddd7777cccc6666';

  ({RelaySession session, FakeConnection socket}) join(
    Relay relay,
    String sessionId, {
    String name = 'Ada',
  }) {
    final socket = FakeConnection();
    final session = relay.open(socket)
      ..handleData(
        encodeMessage(
          JoinMessage(
            sessionId: sessionId,
            name: name,
            color: 0xFF54C5F8,
            cosmetic: PlayerCosmetic.none,
          ),
        ),
      );
    return (session: session, socket: socket);
  }

  group('MapRelays', () {
    test('builds exactly one relay per map, each with its own spec', () {
      final hub = MapRelays();

      expect(hub.relays.keys.toSet(), equals(MapId.values.toSet()));
      for (final map in MapId.values) {
        final relay = hub.relayFor(map);
        expect(relay.map, equals(map));
        expect(relay.spec, equals(MapSpec.of(map)));
      }
    });

    test('every registry shares one moderation state', () {
      final hub = MapRelays();

      for (final relay in hub.all) {
        expect(identical(relay.moderation, hub.moderation), isTrue);
      }
    });

    test('player ids never collide between maps', () {
      // Two registries each counting from `p1` would hand two different
      // people the same id, and the admin roster is a union of both.
      final hub = MapRelays();
      join(hub.relayFor(MapId.conference), alice);
      join(hub.relayFor(MapId.beach), bob);

      final ids = hub.adminPlayerList().map((row) => row.id).toList();
      expect(ids.toSet().length, equals(ids.length));
    });

    test('a beach player spawns on the beach, in beach coordinates', () {
      final hub = MapRelays();
      join(hub.relayFor(MapId.beach), alice);

      final player = hub.relayFor(MapId.beach).registry.players.single;
      expect(MapSpec.beach.isOnFloor(player.x, player.y), isTrue);
      expect(
        MapSpec.beach.zoneAt(player.x, player.y),
        equals(WorldZone.beachSand),
      );
    });

    test('a beach position is clamped to the beach, not the conference', () {
      final hub = MapRelays();
      final beach = hub.relayFor(MapId.beach);
      final joined = join(beach, alice);
      final id = joined.session.playerId!;

      joined.session.handleData(
        encodeMessage(const MoveMessage(x: 5000, y: 5000)),
      );

      final player = beach.registry[id]!;
      expect(player.x, equals(MapSpec.beach.clampX(5000)));
      expect(player.y, equals(MapSpec.beach.clampY(5000)));
      // And that is genuinely smaller than the conference would have allowed.
      expect(player.x, lessThan(MapSpec.conference.clampX(5000)));
    });

    test('the two worlds cannot see each other', () {
      final hub = MapRelays();
      final onLand = join(hub.relayFor(MapId.conference), alice);
      final onSand = join(hub.relayFor(MapId.beach), bob, name: 'Bob');

      hub.start();
      for (final relay in hub.all) {
        relay.tick();
      }
      hub.stop();

      for (final socket in [onLand.socket, onSand.socket]) {
        for (final message in received(socket)) {
          if (message is! SnapshotMessage) continue;
          expect(message.positions, isEmpty);
          expect(message.appeared, isEmpty);
        }
      }
    });

    group('switching maps', () {
      test('evicts the session from the map it left', () {
        final hub = MapRelays();
        final conference = hub.relayFor(MapId.conference);
        final beach = hub.relayFor(MapId.beach);

        final first = join(conference, alice);
        expect(conference.playerCount, equals(1));

        join(beach, alice);

        expect(conference.playerCount, equals(0));
        expect(beach.playerCount, equals(1));
        // The old socket is closed too, not just forgotten: a socket left
        // open would keep receiving ticks for a world its player has left.
        expect(first.socket.closed, isTrue);
      });

      test('leaves no held seat behind to resume into', () {
        // Without this the switch would be undone by the linger window: the
        // player would walk back onto the conference map at their old spot
        // the next time anything resumed the session.
        final hub = MapRelays();
        final conference = hub.relayFor(MapId.conference);

        join(conference, alice);
        join(hub.relayFor(MapId.beach), alice);

        expect(conference.registry.heldSeatCount, equals(0));
        expect(conference.registry.seatOfSession(alice), isNull);
      });

      test('tells the neighbours the bean is gone', () {
        final hub = MapRelays();
        final conference = hub.relayFor(MapId.conference);
        final leaving = join(conference, alice);
        final staying = join(conference, bob, name: 'Bob');
        final leavingId = leaving.session.playerId!;

        conference.tick();
        staying.socket.sent.clear();

        join(hub.relayFor(MapId.beach), alice);

        expect(
          received(staying.socket).whereType<PlayerLeftMessage>().map(
            (message) => message.id,
          ),
          contains(leavingId),
        );
      });

      test('is a no-op for a session that was never on the other map', () {
        final hub = MapRelays();
        expect(
          hub.relayFor(MapId.beach).evictSession(alice),
          isFalse,
        );
      });

      test('the session id survives, so a kick still follows the player', () {
        final hub = MapRelays();
        join(hub.relayFor(MapId.conference), alice);
        join(hub.relayFor(MapId.beach), alice);

        expect(
          hub.relayFor(MapId.beach).registry.seatOfSession(alice),
          isNotNull,
        );
      });
    });

    group('moderation is global', () {
      test('a ban set on one map blocks a join on the other', () {
        final hub = MapRelays();
        final conference = hub.relayFor(MapId.conference);
        final joined = join(conference, alice);

        expect(conference.ban(joined.session.playerId!), isNotNull);

        final onTheBeach = join(hub.relayFor(MapId.beach), alice);

        expect(hub.relayFor(MapId.beach).playerCount, equals(0));
        expect(
          received(onTheBeach.socket)
              .whereType<JoinRejectedMessage>()
              .single
              .reason,
          equals(JoinRejection.banned),
        );
      });

      test('the roster is the union across maps', () {
        final hub = MapRelays();
        join(hub.relayFor(MapId.conference), alice);
        join(hub.relayFor(MapId.beach), bob, name: 'Bob');

        final rows = hub.adminPlayerList();

        expect(rows.length, equals(2));
        expect(
          rows.map((row) => row.map).toSet(),
          equals({MapId.conference, MapId.beach}),
        );
        expect(
          rows.singleWhere((row) => row.name == 'Bob').map,
          equals(MapId.beach),
        );
      });

      test('an admin kick reaches a player standing on the beach', () {
        // The roster is a union, so a kick names a player id and nothing
        // about a map. It works because the evict-on-join rule means a
        // session is seated in exactly one registry at a time.
        final hub = MapRelays();
        final admin = AdminHub(relays: hub, token: 'a-long-enough-token');
        final onSand = join(hub.relayFor(MapId.beach), bob);
        final id = onSand.session.playerId!;

        final socket = FakeConnection();
        admin.open(socket)
          ..handleData(
            encodeMessage(const AdminAuthMessage(token: 'a-long-enough-token')),
          )
          ..handleData(encodeMessage(AdminKickMessage(playerId: id)));

        expect(hub.relayFor(MapId.beach).playerCount, equals(0));
        expect(onSand.socket.closed, isTrue);
        expect(
          received(socket).whereType<AdminActionResultMessage>().single.action,
          equals(AdminAction.kick),
        );
      });

      test('a ban from the roster follows a beach player everywhere', () {
        final hub = MapRelays();
        final admin = AdminHub(relays: hub, token: 'a-long-enough-token');
        final onSand = join(hub.relayFor(MapId.beach), bob);

        admin.open(FakeConnection())
          ..handleData(
            encodeMessage(const AdminAuthMessage(token: 'a-long-enough-token')),
          )
          ..handleData(
            encodeMessage(
              AdminBanMessage(playerId: onSand.session.playerId!),
            ),
          );

        // Banned on the beach, refused at the conference.
        final comingBack = join(hub.relayFor(MapId.conference), bob);
        expect(hub.relayFor(MapId.conference).playerCount, equals(0));
        expect(
          received(comingBack.socket)
              .whereType<JoinRejectedMessage>()
              .single
              .reason,
          equals(JoinRejection.banned),
        );
      });

      test('the pushed roster carries onlineByMap', () {
        final hub = MapRelays();
        final admin = AdminHub(relays: hub, token: 'a-long-enough-token');
        join(hub.relayFor(MapId.conference), alice);
        join(hub.relayFor(MapId.beach), bob);

        final socket = FakeConnection();
        admin
            .open(socket)
            .handleData(
              encodeMessage(
                const AdminAuthMessage(token: 'a-long-enough-token'),
              ),
            );

        final list = received(
          socket,
        ).whereType<AdminPlayerListMessage>().last;
        expect(list.online, equals(2));
        expect(list.onlineByMap[MapId.conference], equals(1));
        expect(list.onlineByMap[MapId.beach], equals(1));
        expect(
          list.onlineByMap.values.fold(0, (a, b) => a + b),
          equals(list.online),
        );
      });

      test('mapOf and relayOf find a player on whichever map they are on', () {
        final hub = MapRelays();
        final onSand = join(hub.relayFor(MapId.beach), bob);
        final id = onSand.session.playerId!;

        expect(hub.mapOf(id), equals(MapId.beach));
        expect(hub.relayOf(id)?.map, equals(MapId.beach));
        expect(hub.mapOf('nobody'), isNull);
        expect(hub.relayOf('nobody'), isNull);
      });
    });

    group('counts', () {
      test('byMap sums to players', () {
        final hub = MapRelays();
        join(hub.relayFor(MapId.conference), alice);
        join(hub.relayFor(MapId.beach), bob);

        final counts = hub.countsByMap;

        expect(counts[MapId.conference], equals(1));
        expect(counts[MapId.beach], equals(1));
        expect(counts.values.fold(0, (a, b) => a + b), equals(hub.playerCount));
      });

      test('metricsJson keeps players as the grand total', () {
        final hub = MapRelays();
        join(hub.relayFor(MapId.conference), alice);
        join(hub.relayFor(MapId.beach), bob);
        // `players` is a tick-time gauge, so it needs a tick to be recorded.
        for (final relay in hub.all) {
          relay.tick();
        }

        final json = hub.metricsJson();
        final byMap = json['byMap']! as Map<String, Object?>;

        expect(json['players'], equals(2));
        expect(byMap['conference'], equals(1));
        expect(byMap['beach'], equals(1));
        expect(
          byMap.values.cast<int>().fold(0, (a, b) => a + b),
          equals(json['players']),
        );
        // And the shape everything already reading /metrics expects is intact.
        expect(json.keys, contains('averagePlayersPerSnapshot'));
        expect(json.keys, contains('p95TickMillis'));
      });
    });
  });

  group('routing', () {
    Future<Response> upgrade(Handler handler, String query) => Future.value(
      handler(
        Request(
          'GET',
          Uri.parse('http://localhost:8080/$webSocketPath$query'),
        ),
      ),
    ).then((response) async => response);

    test('/metrics reports byMap', () async {
      final hub = MapRelays();
      final handler = buildHandler(relays: hub);

      final response = await handler(
        Request('GET', Uri.parse('http://localhost:8080/$metricsPath')),
      );
      final body = jsonDecode(await response.readAsString());

      expect(body, isA<Map<String, Object?>>());
      expect(
        (body as Map<String, Object?>)['byMap'],
        isA<Map<String, Object?>>(),
      );
    });

    test('a plain GET on /ws is still refused, whatever the map', () async {
      // The upgrade handler answers a non-upgrade GET with a 404. What this
      // proves is that both query strings reach *a* handler rather than
      // falling through to the router's own 404 for an unknown path — the
      // two are indistinguishable by status, so the real routing proof is
      // the relay-level tests below.
      final handler = buildHandler(relays: MapRelays());

      for (final query in ['', '?map=beach', '?map=nonsense']) {
        final response = await upgrade(handler, query);
        expect(response.statusCode, equals(404));
      }
    });

    test('MapId.fromId decides what an unknown map means', () {
      // The routing decision itself, tested where it lives. A mistyped link
      // opens the front door rather than failing the upgrade.
      expect(MapId.fromId('beach'), equals(MapId.beach));
      expect(MapId.fromId('nonsense'), equals(MapId.conference));
      expect(MapId.fromId(null), equals(MapId.conference));
    });
  });

  group('the maintenance gate', () {
    /// A hub whose config closes the event until [until].
    MapRelays closedUntil(DateTime? until) => MapRelays(
      config: ConfigStore.inMemory(
        config: AppConfig(maintenanceUntil: until),
      ),
    );

    JoinRejectedMessage? rejectionOn(FakeConnection socket) =>
        received(socket).whereType<JoinRejectedMessage>().firstOrNull;

    test('a join during the window is refused, on every map', () {
      final hub = closedUntil(
        DateTime.now().toUtc().add(
          const Duration(
            hours: 1,
          ),
        ),
      );

      for (final map in MapId.values) {
        final it = join(hub.relayFor(map), alice);

        expect(
          rejectionOn(it.socket)?.reason,
          equals(JoinRejection.maintenance),
          reason: '${map.id} should be closed too',
        );
        expect(it.socket.closed, isTrue);
        expect(hub.relayFor(map).playerCount, isZero);
      }
    });

    test('the refusal says when the event opens again', () {
      // The one thing somebody staring at a closed event wants to know.
      final until = DateTime.now().toUtc().add(const Duration(hours: 2));
      final hub = closedUntil(until);

      expect(
        rejectionOn(join(hub.relayFor(MapId.conference), alice).socket)?.detail,
        contains(until.toIso8601String()),
      );
    });

    test('a window that has passed lets everybody in', () {
      // Nobody has to remember to switch it off. That is the whole reason
      // this is a moment and not a flag.
      final hub = closedUntil(
        DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      final it = join(hub.relayFor(MapId.conference), alice);

      expect(rejectionOn(it.socket), isNull);
      expect(hub.relayFor(MapId.conference).playerCount, equals(1));
    });

    test('no window at all lets everybody in', () {
      final hub = closedUntil(null);

      expect(
        rejectionOn(join(hub.relayFor(MapId.conference), alice).socket),
        isNull,
      );
    });

    test('the window is re-read per join, not captured at startup', () {
      // The relay is handed a callback rather than a value precisely so a
      // window opened while the server runs shuts the next arrival out.
      final store = ConfigStore.inMemory();
      final hub = MapRelays(config: store);
      expect(
        rejectionOn(join(hub.relayFor(MapId.conference), alice).socket),
        isNull,
      );

      store.setMaintenanceUntil(
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      );

      expect(
        rejectionOn(join(hub.relayFor(MapId.conference), bob).socket)?.reason,
        equals(JoinRejection.maintenance),
      );
    });

    test('disconnectAll empties every map and counts what it closed', () {
      final hub = MapRelays();
      final here = join(hub.relayFor(MapId.conference), alice);
      final there = join(hub.relayFor(MapId.beach), bob);

      expect(hub.disconnectAll(), equals(2));
      expect(here.socket.closed, isTrue);
      expect(there.socket.closed, isTrue);
      expect(hub.playerCount, isZero);
    });

    test('disconnectAll is not a kick: nobody is cooled off or blocked', () {
      // A room full of thirty-second cooldowns would make the reopening
      // worse than the closure, and nobody here did anything wrong.
      final hub = MapRelays();
      join(hub.relayFor(MapId.conference), alice);

      hub.disconnectAll();

      expect(hub.moderation.kickCooldownLeft(alice), isNull);
      expect(hub.moderation.isNameBlocked(alice, 'Ada'), isFalse);
      expect(hub.moderation.isBanned(alice), isFalse);
    });
  });
}
