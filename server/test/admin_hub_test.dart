import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:test/test.dart';

/// A socket that records what it was sent.
class FakeConnection implements PlayerConnection {
  final List<String> sent = [];
  bool closed = false;

  /// Everything sent to this socket, decoded.
  List<ProtocolMessage> get received =>
      sent.map(decodeMessage).toList(growable: false);

  /// The last message sent to this socket.
  ProtocolMessage get last => received.last;

  /// The errors this socket was sent, in order.
  List<AdminErrorMessage> get errors =>
      received.whereType<AdminErrorMessage>().toList(growable: false);

  /// The configs this socket was sent, in order.
  List<ConfigMessage> get configs =>
      received.whereType<ConfigMessage>().toList(growable: false);

  /// The player lists this socket was sent, in order.
  List<AdminPlayerListMessage> get lists =>
      received.whereType<AdminPlayerListMessage>().toList(growable: false);

  /// The action results this socket was sent, in order.
  List<AdminActionResultMessage> get results =>
      received.whereType<AdminActionResultMessage>().toList(growable: false);

  @override
  void send(String data) => sent.add(data);

  @override
  void close() => closed = true;
}

void main() {
  const token = 'a-long-enough-test-token';

  /// A relay, a hub over it, and somewhere to read the log.
  ({Relay relay, MapRelays relays, AdminHub hub, List<String> log}) world({
    String? adminToken = token,
    ModerationState? moderation,
    ConfigStore? config,
  }) {
    final log = <String>[];
    final relays = MapRelays(
      log: log.add,
      moderation: moderation,
      config: config,
    );
    return (
      relay: relays.relayFor(MapId.conference),
      relays: relays,
      hub: AdminHub(relays: relays, token: adminToken, log: log.add),
      log: log,
    );
  }

  /// Joins a player and returns their session, socket and id.
  ({RelaySession session, FakeConnection socket, String id}) join(
    Relay relay, {
    required String sessionId,
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
    return (session: session, socket: socket, id: session.playerId!);
  }

  /// An authenticated admin socket.
  ({AdminSession session, FakeConnection socket}) admin(AdminHub hub) {
    final socket = FakeConnection();
    final session = hub.open(socket)
      ..handleData(encodeMessage(const AdminAuthMessage(token: token)));
    return (session: session, socket: socket);
  }

  group('authentication', () {
    test('a fresh admin socket is not authorised', () {
      final it = world();
      final socket = FakeConnection();

      expect(it.hub.open(socket).isAuthorized, isFalse);
      expect(it.hub.authorizedCount, isZero);
    });

    test('the right token authorises', () {
      final it = world();
      final socket = FakeConnection();
      final session = it.hub.open(socket)
        ..handleData(encodeMessage(const AdminAuthMessage(token: token)));

      expect(session.isAuthorized, isTrue);
      expect(
        socket.received.whereType<AdminAuthResultMessage>().first.authorized,
        isTrue,
      );
    });

    test('the wrong token does not', () {
      final it = world();
      final socket = FakeConnection();
      final session = it.hub.open(socket)
        ..handleData(encodeMessage(const AdminAuthMessage(token: 'nope')));

      expect(session.isAuthorized, isFalse);
      expect((socket.last as AdminAuthResultMessage).authorized, isFalse);
    });

    test('a wrong token drops privilege that was already granted', () {
      // There is no way to lose privilege by accident, so there must be no
      // way to keep it by accident either.
      final it = world();
      final session = admin(it.hub).session
        ..handleData(encodeMessage(const AdminAuthMessage(token: 'nope')));

      expect(session.isAuthorized, isFalse);
    });

    test('a token of the right length but wrong content is refused', () {
      final it = world();
      final socket = FakeConnection();
      final wrong = 'b' * token.length;
      it.hub
          .open(socket)
          .handleData(
            encodeMessage(AdminAuthMessage(token: wrong)),
          );

      expect((socket.last as AdminAuthResultMessage).authorized, isFalse);
    });

    test('no configured token means nobody can moderate', () {
      // A deployment that forgot the env var gets no moderation, never open
      // moderation.
      final it = world(adminToken: null);
      final socket = FakeConnection();
      final session = it.hub.open(socket)
        ..handleData(encodeMessage(const AdminAuthMessage(token: token)));

      expect(it.hub.isEnabled, isFalse);
      expect(session.isAuthorized, isFalse);
    });

    test('an empty token never matches an unconfigured server', () {
      final it = world(adminToken: null);
      final socket = FakeConnection();
      final session = it.hub.open(socket)
        ..handleData(encodeMessage(const AdminAuthMessage(token: '')));

      expect(session.isAuthorized, isFalse);
    });

    test('the token is never written to the log', () {
      final it = world();
      admin(it.hub);
      it.hub.open(FakeConnection())
        ..handleData(encodeMessage(const AdminAuthMessage(token: token)))
        ..handleData(
          encodeMessage(const AdminAuthMessage(token: 'wrong-but-secret')),
        );

      for (final line in it.log) {
        expect(line, isNot(contains(token)));
        expect(line, isNot(contains('wrong-but-secret')));
      }
    });
  });

  group('authorization is enforced server-side', () {
    // The point of the whole phase: hiding the UI is not security. Every one
    // of these sends a real admin message down a real socket that simply
    // never presented a token.
    for (final message in <ProtocolMessage>[
      const AdminKickMessage(playerId: 'p1'),
      const AdminBanMessage(playerId: 'p1'),
      const AdminMuteNameMessage(playerId: 'p1', muted: true),
      const AdminMuteNameMessage(playerId: 'p1', muted: false),
    ]) {
      test('$message from an unauthenticated socket is refused', () {
        final it = world();
        final player = join(it.relay, sessionId: 'a' * 32);
        final socket = FakeConnection();

        it.hub.open(socket).handleData(encodeMessage(message));

        expect(socket.errors.single.reason, equals(AdminError.unauthorized));
        // ...and nothing actually happened to the player.
        expect(it.relay.registry[player.id], isNotNull);
        expect(player.socket.closed, isFalse);
        expect(it.relay.registry[player.id]!.name, equals('Ada'));
      });
    }

    test('a player socket cannot moderate at all', () {
      // The interesting attack: send a kick down the socket you already
      // have. There is no code on that path that could act on it.
      final it = world();
      final victim = join(it.relay, sessionId: 'a' * 32);
      final attacker = join(it.relay, sessionId: 'b' * 32, name: 'Mallory');

      attacker.session.handleData(
        encodeMessage(AdminKickMessage(playerId: victim.id)),
      );

      expect(it.relay.registry[victim.id], isNotNull);
      expect(victim.socket.closed, isFalse);
      expect(
        it.log.where((line) => line.contains('admin message on a player')),
        hasLength(1),
      );
    });

    test('an admin socket cannot join the world', () {
      final it = world();
      final socket = FakeConnection();
      it.hub
          .open(socket)
          .handleData(
            encodeMessage(
              JoinMessage(
                sessionId: 'c' * 32,
                name: 'Ada',
                color: 1,
                cosmetic: PlayerCosmetic.none,
              ),
            ),
          );

      expect(socket.errors.single.reason, equals(AdminError.badRequest));
      expect(it.relay.playerCount, isZero);
    });

    test('an unreadable frame is dropped, not fatal', () {
      final it = world();
      final admin = FakeConnection();
      final session = it.hub.open(admin)
        ..handleData('{not json')
        ..handleData(42);

      expect(admin.sent, isEmpty);
      expect(session.isAuthorized, isFalse);
    });
  });

  group('kick', () {
    test('disconnects the player and leaves no ghost behind', () {
      final it = world();
      final onlooker = join(it.relay, sessionId: '9' * 32, name: 'Bob');
      final target = join(it.relay, sessionId: 'a' * 32);
      final moderator = admin(it.hub);
      // The onlooker has to actually know about them before "no ghost" is a
      // claim about anything.
      it.relay.tick();
      expect(onlooker.session.known, contains(target.id));

      moderator.session.handleData(
        encodeMessage(AdminKickMessage(playerId: target.id)),
      );

      expect(target.socket.closed, isTrue);
      expect(it.relay.registry[target.id], isNull);
      // Gone from the *interest grid*, not merely from the player map. Both
      // spawn on the same ring, so this query is the one the onlooker's own
      // snapshot runs — a bean left behind in the grid is the ghost this
      // whole test exists for.
      final me = it.relay.registry[onlooker.id]!;
      expect(
        it.relay.registry.near(me.x, me.y).map((player) => player.id),
        isNot(contains(target.id)),
      );
      expect(onlooker.session.known, isNot(contains(target.id)));
      expect(
        onlooker.socket.received.whereType<PlayerLeftMessage>().single.id,
        equals(target.id),
      );
      // A tick after the kick must not resurrect them.
      it.relay.tick();
      expect(it.relay.registry[target.id], isNull);
    });

    test('reports what it did', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32);
      final moderator = admin(it.hub);

      moderator.session.handleData(
        encodeMessage(AdminKickMessage(playerId: target.id)),
      );

      expect(moderator.socket.results.single.action, equals(AdminAction.kick));
      expect(moderator.socket.results.single.targetName, equals('Ada'));
    });

    test('the rejoin the client makes on its own is refused', () {
      // The bug this cooldown exists for: the kicked client cannot tell a
      // moderator from a dropped tunnel, so it reconnects under the same
      // session id within half a second and the kick undoes itself.
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32);
      admin(it.hub).session.handleData(
        encodeMessage(AdminKickMessage(playerId: target.id)),
      );

      final retry = FakeConnection();
      it.relay
          .open(retry)
          .handleData(
            encodeMessage(
              JoinMessage(
                sessionId: 'a' * 32,
                name: 'Ada',
                color: 1,
                cosmetic: PlayerCosmetic.none,
              ),
            ),
          );

      final rejection = retry.last as JoinRejectedMessage;
      expect(rejection.reason, equals(JoinRejection.kicked));
      // The remaining wait is in the words, so the client can say it without
      // parsing anything.
      expect(rejection.detail, contains('30s'));
      expect(retry.closed, isTrue);
      expect(it.relay.playerCount, isZero);
    });

    test('a kicked player may come back once the cooldown is over', () {
      // The whole difference between a kick and a ban — under a new name,
      // which is the difference between a kick and nothing at all.
      var now = DateTime.utc(2026, 3, 14, 9, 30);
      final it = world(moderation: ModerationState(now: () => now));
      final target = join(it.relay, sessionId: 'a' * 32);
      admin(it.hub).session.handleData(
        encodeMessage(AdminKickMessage(playerId: target.id)),
      );

      now = now.add(const Duration(seconds: 31));
      final again = join(it.relay, sessionId: 'a' * 32, name: 'Grace');

      expect(it.relay.registry[again.id], isNotNull);
    });

    test('the name they were kicked under is refused afterwards', () {
      // The point of a kick in a world with no chat: they may come back, but
      // not as whatever got them removed.
      var now = DateTime.utc(2026, 3, 14, 9, 30);
      final it = world(moderation: ModerationState(now: () => now));
      final target = join(it.relay, sessionId: 'a' * 32);
      admin(it.hub).session.handleData(
        encodeMessage(AdminKickMessage(playerId: target.id)),
      );

      now = now.add(const Duration(seconds: 31));
      final retry = FakeConnection();
      it.relay
          .open(retry)
          .handleData(
            encodeMessage(
              // The same name, respaced and recapitalised — which is the
              // obvious first thing to try.
              JoinMessage(
                sessionId: 'a' * 32,
                name: ' ADA ',
                color: 1,
                cosmetic: PlayerCosmetic.none,
              ),
            ),
          );

      final rejection = retry.last as JoinRejectedMessage;
      // Reported as a name problem, because that is the rejection that sends
      // the client back to the setup screen to choose another.
      expect(rejection.reason, equals(JoinRejection.invalidName));
      expect(rejection.detail, contains('moderator removed that name'));
      expect(it.relay.playerCount, isZero);
    });

    test('a different name gets them back in', () {
      var now = DateTime.utc(2026, 3, 14, 9, 30);
      final it = world(moderation: ModerationState(now: () => now));
      final target = join(it.relay, sessionId: 'a' * 32);
      admin(it.hub).session.handleData(
        encodeMessage(AdminKickMessage(playerId: target.id)),
      );

      now = now.add(const Duration(seconds: 31));
      final again = join(it.relay, sessionId: 'a' * 32, name: 'Grace');

      expect(it.relay.registry[again.id], isNotNull);
      expect(it.relay.registry[again.id]!.name, equals('Grace'));
    });

    test('a muted player loses the name they chose, not the placeholder', () {
      // Mute first, kick second is a realistic sequence, and the naive
      // version blocks "Guest" — leaving the name the moderator objected to
      // free and every future Guest blocked.
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32, name: 'Rude');
      final moderator = admin(it.hub);
      moderator.session.handleData(
        encodeMessage(AdminMuteNameMessage(playerId: target.id, muted: true)),
      );
      moderator.session.handleData(
        encodeMessage(AdminKickMessage(playerId: target.id)),
      );

      expect(it.relay.moderation.isNameBlocked('a' * 32, 'Rude'), isTrue);
      expect(
        it.relay.moderation.isNameBlocked('a' * 32, mutedDisplayName),
        isFalse,
      );
    });

    test('kicks nobody else', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32);
      admin(it.hub).session.handleData(
        encodeMessage(AdminKickMessage(playerId: target.id)),
      );

      final bystander = join(it.relay, sessionId: 'b' * 32, name: 'Bob');

      expect(it.relay.registry[bystander.id], isNotNull);
    });

    test('kicking somebody who already left is a typed error', () {
      final it = world();
      final moderator = admin(it.hub);

      moderator.session.handleData(
        encodeMessage(const AdminKickMessage(playerId: 'p99')),
      );

      expect(
        moderator.socket.errors.single.reason,
        equals(AdminError.unknownPlayer),
      );
    });
  });

  group('ban', () {
    test('disconnects them and refuses the rejoin', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32);
      final moderator = admin(it.hub);

      moderator.session.handleData(
        encodeMessage(AdminBanMessage(playerId: target.id)),
      );

      expect(target.socket.closed, isTrue);
      expect(it.relay.registry[target.id], isNull);

      final retry = FakeConnection();
      it.relay
          .open(retry)
          .handleData(
            encodeMessage(
              JoinMessage(
                sessionId: 'a' * 32,
                name: 'Ada',
                color: 1,
                cosmetic: PlayerCosmetic.none,
              ),
            ),
          );

      expect(
        (retry.last as JoinRejectedMessage).reason,
        equals(JoinRejection.banned),
      );
      expect(retry.closed, isTrue);
      expect(it.relay.playerCount, isZero);
    });

    test('does not leave the seat warm for the linger window', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32);
      final moderator = admin(it.hub);

      moderator.session.handleData(
        encodeMessage(AdminBanMessage(playerId: target.id)),
      );

      expect(it.relay.registry.heldSeatCount, isZero);
    });

    test('survives a server restart', () {
      // A ban lost to a restart forty seconds later is a ban that did not
      // happen, and the person it was for is back in the room.
      final storage = InMemoryBanStorage();
      final first = world(moderation: ModerationState(storage: storage));
      final target = join(first.relay, sessionId: 'a' * 32);
      admin(first.hub).session.handleData(
        encodeMessage(AdminBanMessage(playerId: target.id)),
      );

      // A brand-new server over the same file.
      final second = world(moderation: ModerationState(storage: storage));
      final retry = FakeConnection();
      second.relay
          .open(retry)
          .handleData(
            encodeMessage(
              JoinMessage(
                sessionId: 'a' * 32,
                name: 'Ada',
                color: 1,
                cosmetic: PlayerCosmetic.none,
              ),
            ),
          );

      expect(
        (retry.last as JoinRejectedMessage).reason,
        equals(JoinRejection.banned),
      );
    });

    test('bans nobody else', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32);
      admin(it.hub).session.handleData(
        encodeMessage(AdminBanMessage(playerId: target.id)),
      );

      final bystander = join(it.relay, sessionId: 'b' * 32, name: 'Bob');

      expect(it.relay.registry[bystander.id], isNotNull);
    });
  });

  group('mute name', () {
    test('replaces the name without disconnecting them', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32, name: 'Rude');
      final moderator = admin(it.hub);

      moderator.session.handleData(
        encodeMessage(AdminMuteNameMessage(playerId: target.id, muted: true)),
      );

      expect(target.socket.closed, isFalse);
      expect(it.relay.registry[target.id]!.name, equals(mutedDisplayName));
      expect(
        moderator.socket.results.single.action,
        equals(AdminAction.muteName),
      );
      // The audit line records what was muted, not the placeholder.
      expect(moderator.socket.results.single.targetName, equals('Rude'));
    });

    test('the new name reaches everybody who can see them, next tick', () {
      final it = world();
      final onlooker = join(it.relay, sessionId: '9' * 32, name: 'Bob');
      final target = join(it.relay, sessionId: 'a' * 32, name: 'Rude');
      it.relay.tick();
      expect(
        onlooker.socket.received
            .whereType<SnapshotMessage>()
            .expand((snapshot) => snapshot.appeared)
            .single
            .name,
        equals('Rude'),
      );

      admin(it.hub).session.handleData(
        encodeMessage(AdminMuteNameMessage(playerId: target.id, muted: true)),
      );
      it.relay.tick();

      // Re-announced as an appearance, because metadata only ever travels on
      // appearance — there is no "player updated" message and deliberately so.
      expect(
        onlooker.socket.received
            .whereType<SnapshotMessage>()
            .expand((snapshot) => snapshot.appeared)
            .last
            .name,
        equals(mutedDisplayName),
      );
    });

    test('survives a reconnect', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32, name: 'Rude');
      admin(it.hub).session.handleData(
        encodeMessage(AdminMuteNameMessage(playerId: target.id, muted: true)),
      );
      target.session.close();

      final again = join(it.relay, sessionId: 'a' * 32, name: 'Rude');

      expect(it.relay.registry[again.id]!.name, equals(mutedDisplayName));
    });

    test('rejoining under a different name does not escape it', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32, name: 'Rude');
      admin(it.hub).session.handleData(
        encodeMessage(AdminMuteNameMessage(playerId: target.id, muted: true)),
      );
      target.session.close();

      final again = join(it.relay, sessionId: 'a' * 32, name: 'Also Rude');

      expect(it.relay.registry[again.id]!.name, equals(mutedDisplayName));
    });

    test('an unmute gives the chosen name back', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32, name: 'Rude');
      final moderator = admin(it.hub);
      moderator.session.handleData(
        encodeMessage(AdminMuteNameMessage(playerId: target.id, muted: true)),
      );

      moderator.session.handleData(
        encodeMessage(AdminMuteNameMessage(playerId: target.id, muted: false)),
      );

      expect(it.relay.registry[target.id]!.name, equals('Rude'));
      expect(
        moderator.socket.results.last.action,
        equals(AdminAction.unmuteName),
      );
    });

    test('muting twice does not make Guest their real name', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32, name: 'Rude');
      final moderator = admin(it.hub);
      final mute = encodeMessage(
        AdminMuteNameMessage(playerId: target.id, muted: true),
      );
      moderator.session
        ..handleData(mute)
        ..handleData(mute)
        ..handleData(
          encodeMessage(
            AdminMuteNameMessage(playerId: target.id, muted: false),
          ),
        );

      expect(it.relay.registry[target.id]!.name, equals('Rude'));
    });
  });

  group('player list', () {
    test('is not sent to an unauthorised socket', () {
      final it = world();
      join(it.relay, sessionId: 'a' * 32);
      final eavesdropper = FakeConnection();
      it.hub.open(eavesdropper);

      it.hub.broadcastPlayerList();

      expect(eavesdropper.sent, isEmpty);
    });

    test('shows everybody, however far away they are', () {
      // The one uncalled read in the server: the person you were told about
      // is by definition somewhere you are not.
      final it = world();
      join(it.relay, sessionId: 'a' * 32);
      join(it.relay, sessionId: 'b' * 32, name: 'Bob');
      final moderator = admin(it.hub);

      it.hub.broadcastPlayerList();

      expect(moderator.socket.lists.last.online, equals(2));
      expect(
        moderator.socket.lists.last.players.map((player) => player.name),
        containsAll(<String>['Ada', 'Bob']),
      );
    });

    test('shows the chosen name of a muted player, flagged as muted', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32, name: 'Rude');
      final moderator = admin(it.hub);
      moderator.session.handleData(
        encodeMessage(AdminMuteNameMessage(playerId: target.id, muted: true)),
      );

      it.hub.broadcastPlayerList();
      final row = moderator.socket.lists.last.players.single;

      expect(row.name, equals('Rude'));
      expect(row.isNameMuted, isTrue);
      expect(row.displayName, equals(mutedDisplayName));
    });

    test('never carries a session id', () {
      final it = world();
      join(it.relay, sessionId: 'a' * 32);
      final moderator = admin(it.hub);

      it.hub.broadcastPlayerList();

      for (final frame in moderator.socket.sent) {
        expect(frame, isNot(contains('a' * 32)));
      }
    });

    test('is pushed straight after a successful auth', () {
      final it = world();
      join(it.relay, sessionId: 'a' * 32);

      expect(admin(it.hub).socket.lists, hasLength(1));
    });

    test('is pushed again straight after an action', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32);
      final moderator = admin(it.hub);

      moderator.session.handleData(
        encodeMessage(AdminKickMessage(playerId: target.id)),
      );

      expect(moderator.socket.lists.last.online, isZero);
    });

    test('a closed admin socket stops counting as authorised', () {
      final it = world();
      final moderator = admin(it.hub);
      expect(it.hub.authorizedCount, equals(1));

      moderator.session.close();

      expect(it.hub.authorizedCount, isZero);
    });
  });

  group('audit', () {
    test('every action writes one line', () {
      final it = world();
      final a = join(it.relay, sessionId: 'a' * 32);
      final b = join(it.relay, sessionId: 'b' * 32, name: 'Bob');
      final c = join(it.relay, sessionId: 'c' * 32, name: 'Cy');
      final moderator = admin(it.hub);

      moderator.session
        ..handleData(encodeMessage(AdminKickMessage(playerId: a.id)))
        ..handleData(encodeMessage(AdminBanMessage(playerId: b.id)))
        ..handleData(
          encodeMessage(AdminMuteNameMessage(playerId: c.id, muted: true)),
        );

      final audited = it.log.where((line) => line.startsWith('audit:'));
      expect(audited, hasLength(3));
      expect(audited.elementAt(0), contains('kick'));
      expect(audited.elementAt(1), contains('ban'));
      expect(audited.elementAt(2), contains('muteName'));
      expect(audited.elementAt(2), contains('Cy'));
    });

    test('a refused action writes nothing', () {
      final it = world();
      final target = join(it.relay, sessionId: 'a' * 32);

      it.hub
          .open(FakeConnection())
          .handleData(
            encodeMessage(AdminKickMessage(playerId: target.id)),
          );

      expect(it.log.where((line) => line.startsWith('audit:')), isEmpty);
    });
  });

  group('the event config', () {
    test('a fresh admin is handed it the moment it authenticates', () {
      // So the editor opens on what is live rather than on an empty box
      // somebody might reasonably mistake for an empty config.
      final it = world(
        config: ConfigStore.inMemory(
          config: const AppConfig(worldName: 'DashConf'),
        ),
      );

      final socket = admin(it.hub).socket;

      expect(socket.configs, hasLength(1));
      expect(socket.configs.single.config.worldName, equals('DashConf'));
    });

    test('an unauthorised socket cannot push one', () {
      // The rule the whole hub is built around, re-checked on the newest
      // message type rather than inherited from the ones above it.
      final it = world(config: ConfigStore.inMemory());
      final socket = FakeConnection();
      it.hub
          .open(socket)
          .handleData(
            encodeMessage(
              const AdminSetConfigMessage(document: '{"worldName": "Hijack"}'),
            ),
          );

      expect(socket.errors.single.reason, equals(AdminError.unauthorized));
      expect(it.relays.config.config, equals(AppConfig.defaults));
    });

    test('a good push replaces it and reaches everybody in the world', () {
      final it = world(config: ConfigStore.inMemory());
      final player = join(it.relay, sessionId: 'a' * 32);
      final moderator = admin(it.hub);

      moderator.session.handleData(
        encodeMessage(
          const AdminSetConfigMessage(document: '{"worldName": "DashConf"}'),
        ),
      );

      expect(it.relays.config.config.worldName, equals('DashConf'));
      expect(player.socket.configs.last.config.worldName, equals('DashConf'));
      expect(
        moderator.socket.configs.last.config.worldName,
        equals('DashConf'),
        reason: 'the editor has to end up showing what the server parsed',
      );
    });

    test('a push reaches the other map too, because there is one event', () {
      final it = world(config: ConfigStore.inMemory());
      final beach = join(
        it.relays.relayFor(MapId.beach),
        sessionId: 'b' * 32,
      );

      admin(it.hub).session.handleData(
        encodeMessage(
          const AdminSetConfigMessage(document: '{"worldName": "DashConf"}'),
        ),
      );

      expect(beach.socket.configs.last.config.worldName, equals('DashConf'));
    });

    test('a bad push changes nothing and says so', () {
      final it = world(config: ConfigStore.inMemory());
      final player = join(it.relay, sessionId: 'a' * 32);
      final moderator = admin(it.hub);
      final before = player.socket.configs.length;

      moderator.session.handleData(
        encodeMessage(const AdminSetConfigMessage(document: 'oops,')),
      );

      expect(moderator.socket.errors.single.reason, AdminError.badRequest);
      expect(it.relays.config.config, equals(AppConfig.defaults));
      expect(
        player.socket.configs,
        hasLength(before),
        reason: 'a refused push must not fan out to the room',
      );
    });

    test('an arrival is handed the config right behind their welcome', () {
      final it = world(config: ConfigStore.inMemory());
      it.relays.config.apply('{"worldName": "DashConf"}');

      final player = join(it.relay, sessionId: 'a' * 32);

      expect(player.socket.received.first, isA<WelcomeMessage>());
      expect(player.socket.configs.single.config.worldName, equals('DashConf'));
    });
  });

  group('maintenance', () {
    const alice = 'aaaa1111bbbb2222cccc3333dddd4444';
    final until = DateTime.now().toUtc().add(const Duration(hours: 1));

    test('an unauthorised socket cannot close the event', () {
      // The same gate as every other privileged message. The token being
      // asked for twice does not make the first ask optional.
      final it = world();
      final socket = FakeConnection();
      it.hub
          .open(socket)
          .handleData(
            encodeMessage(
              AdminSetMaintenanceMessage(token: token, until: until),
            ),
          );

      expect(socket.errors.single.reason, equals(AdminError.unauthorized));
      expect(it.relays.config.config.maintenanceUntil, isNull);
    });

    test('the wrong token on an authorised socket changes nothing', () {
      final it = world();
      final admin1 = admin(it.hub);

      admin1.session.handleData(
        encodeMessage(
          AdminSetMaintenanceMessage(token: 'not-it', until: until),
        ),
      );

      expect(
        admin1.socket.errors.single.reason,
        equals(AdminError.unauthorized),
      );
      expect(it.relays.config.config.maintenanceUntil, isNull);
      // A mistyped password in a confirmation dialog is an ordinary slip, so
      // it must not throw a moderator back to the token screen mid-incident.
      expect(admin1.session.isAuthorized, isTrue);
    });

    test('the right token closes the event and empties the world', () {
      final it = world();
      final admin1 = admin(it.hub);
      final player = join(it.relay, sessionId: alice);

      admin1.session.handleData(
        encodeMessage(AdminSetMaintenanceMessage(token: token, until: until)),
      );

      expect(it.relays.config.config.maintenanceUntil, equals(until));
      expect(player.socket.closed, isTrue);
      expect(it.relays.playerCount, isZero);
      expect(
        admin1.socket.results.last.action,
        equals(AdminAction.maintenanceOn),
      );
    });

    test('everybody is told why before their socket dies', () {
      // A client that learns the reason can say so. One that just loses a
      // socket reconnects into a refusal it has no words for.
      final it = world();
      final player = join(it.relay, sessionId: alice);

      admin(it.hub).session.handleData(
        encodeMessage(AdminSetMaintenanceMessage(token: token, until: until)),
      );

      expect(player.socket.configs.last.config.maintenanceUntil, equals(until));
    });

    test('the moderator gets the config back too', () {
      final it = world();
      final admin1 = admin(it.hub);

      admin1.session.handleData(
        encodeMessage(AdminSetMaintenanceMessage(token: token, until: until)),
      );

      expect(admin1.socket.configs.last.config.maintenanceUntil, equals(until));
    });

    test('a time that has already passed is refused', () {
      // Refused rather than clamped: "closed until a moment that has gone" is
      // not a window, and reading it as "not closed" answers a tap with the
      // opposite of what it asked for.
      final it = world();
      final admin1 = admin(it.hub);

      admin1.session.handleData(
        encodeMessage(
          AdminSetMaintenanceMessage(
            token: token,
            until: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
          ),
        ),
      );

      expect(admin1.socket.errors.single.reason, equals(AdminError.badRequest));
      expect(it.relays.config.config.maintenanceUntil, isNull);
    });

    test('reopening clears the window and disconnects nobody', () {
      final it = world(
        config: ConfigStore.inMemory(
          config: AppConfig(maintenanceUntil: until),
        ),
      );
      final admin1 = admin(it.hub);
      // Joining is only possible because the gate reads the config live, so
      // this player is seated *before* the window is lifted.
      it.relays.config.setMaintenanceUntil(null);
      final player = join(it.relay, sessionId: alice);

      admin1.session.handleData(
        encodeMessage(const AdminSetMaintenanceMessage(token: token)),
      );

      expect(it.relays.config.config.maintenanceUntil, isNull);
      expect(player.socket.closed, isFalse);
      expect(
        admin1.socket.results.last.action,
        equals(AdminAction.maintenanceOff),
      );
    });

    test('a hand-edited document closes the event just as firmly', () {
      // Enforcement hangs off the state the config is in, not off which
      // message put it there — the field is right there in the editor.
      final it = world();
      final player = join(it.relay, sessionId: alice);

      admin(it.hub).session.handleData(
        encodeMessage(
          AdminSetConfigMessage(
            document: '{"maintenanceUntil":"${until.toIso8601String()}"}',
          ),
        ),
      );

      expect(player.socket.closed, isTrue);
      expect(it.relays.playerCount, isZero);
    });

    test('an ordinary config push disconnects nobody', () {
      final it = world();
      final player = join(it.relay, sessionId: alice);

      admin(it.hub).session.handleData(
        encodeMessage(
          const AdminSetConfigMessage(document: '{"tagline":"still here"}'),
        ),
      );

      expect(player.socket.closed, isFalse);
      expect(it.relays.playerCount, equals(1));
    });

    test('closing the event is written to the audit log', () {
      final it = world();

      admin(it.hub).session.handleData(
        encodeMessage(AdminSetMaintenanceMessage(token: token, until: until)),
      );

      expect(
        it.log.where((line) => line.contains('audit:')).last,
        contains('maintenanceOn'),
      );
    });

    test('the token is never logged, even when it is wrong', () {
      final it = world();

      admin(it.hub).session.handleData(
        encodeMessage(
          AdminSetMaintenanceMessage(token: 'wrong-but-secret', until: until),
        ),
      );

      expect(it.log.join(' '), isNot(contains('wrong-but-secret')));
    });
  });
}
