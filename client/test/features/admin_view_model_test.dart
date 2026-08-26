import 'package:client/features/admin/view_model/admin_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_socket.dart';

void main() {
  const token = 'a-long-enough-test-token';

  AdminPlayerSummary player(
    String id,
    String name, {
    bool muted = false,
    double x = 0,
    double y = 0,
  }) => AdminPlayerSummary(
    id: id,
    name: name,
    isNameMuted: muted,
    x: x,
    y: y,
  );

  /// A view model over a fake socket, plus the socket to play server with.
  ({AdminViewModel model, FakeSocket socket}) subject() {
    final network = fakeNetwork();
    final model = AdminViewModel(network: network.client);
    addTearDown(model.dispose);
    return (model: model, socket: network.socket);
  }

  /// A model that has already been let in.
  Future<({AdminViewModel model, FakeSocket socket})> unlocked() async {
    final it = subject();
    await it.model.submitToken(token);
    it.socket.emit(
      const AdminAuthResultMessage(authorized: true, detail: 'Authenticated.'),
    );
    await pumpEventQueue();
    return it;
  }

  group('authentication', () {
    test('starts locked', () {
      final it = subject();

      expect(it.model.stage, equals(AdminStage.locked));
      expect(it.model.isUnlocked, isFalse);
    });

    test('an empty token is refused without opening a socket', () async {
      final it = subject();

      await it.model.submitToken('   ');

      expect(it.socket.sent, isEmpty);
      expect(it.model.feedback?.isError, isTrue);
      expect(it.model.stage, equals(AdminStage.locked));
    });

    test('submitting sends an adminAuth and waits', () async {
      final it = subject();

      await it.model.submitToken(token);

      expect(it.socket.sentMessages.single, isA<AdminAuthMessage>());
      expect(
        (it.socket.sentMessages.single as AdminAuthMessage).token,
        equals(token),
      );
      expect(it.model.stage, equals(AdminStage.authenticating));
    });

    test('the token is trimmed before it is sent', () async {
      // A token pasted on a phone picks up a trailing space more often than
      // not, and "that token was not accepted" is a miserable way to find out.
      final it = subject();

      await it.model.submitToken('  $token \n');

      expect(
        (it.socket.sentMessages.single as AdminAuthMessage).token,
        equals(token),
      );
    });

    test('a yes unlocks the screen', () async {
      final it = await unlocked();

      expect(it.model.stage, equals(AdminStage.unlocked));
      expect(it.model.feedback?.isError, isFalse);
    });

    test('a no leaves it locked, with the server sentence', () async {
      final it = subject();
      await it.model.submitToken('wrong');

      it.socket.emit(
        const AdminAuthResultMessage(
          authorized: false,
          detail: 'That token was not accepted.',
        ),
      );
      await pumpEventQueue();

      expect(it.model.stage, equals(AdminStage.locked));
      expect(
        it.model.feedback,
        equals(
          const AdminFeedback(
            'That token was not accepted.',
            isError: true,
          ),
        ),
      );
    });

    test('a server that is not there is a sentence, not a crash', () async {
      final network = fakeNetwork(openError: 'refused');
      final model = AdminViewModel(network: network.client);
      addTearDown(model.dispose);

      await model.submitToken(token);

      expect(model.stage, equals(AdminStage.locked));
      expect(model.feedback?.isError, isTrue);
    });

    test('a second submit while one is in flight is ignored', () async {
      final it = subject();

      await it.model.submitToken(token);
      await it.model.submitToken(token);

      expect(it.socket.sentMessages, hasLength(1));
    });

    test('locking forgets everything and drops the socket', () async {
      final it = await unlocked();
      it.socket.emit(
        AdminPlayerListMessage(players: [player('p1', 'Ada')], online: 1),
      );
      await pumpEventQueue();

      it.model
        ..setSearch('ada')
        ..lock();

      expect(it.model.stage, equals(AdminStage.locked));
      expect(it.model.players, isEmpty);
      expect(it.model.online, isZero);
      expect(it.model.search, isEmpty);
    });
  });

  group('the player list', () {
    test('is taken from the server', () async {
      final it = await unlocked();

      it.socket.emit(
        AdminPlayerListMessage(
          players: [player('p1', 'Ada'), player('p2', 'Bob')],
          online: 2,
        ),
      );
      await pumpEventQueue();

      expect(it.model.online, equals(2));
      expect(it.model.players, hasLength(2));
    });

    test('search matches a name, case-insensitively', () async {
      final it = await unlocked();
      it.socket.emit(
        AdminPlayerListMessage(
          players: [player('p1', 'Ada Lovelace'), player('p2', 'Bob')],
          online: 2,
        ),
      );
      await pumpEventQueue();

      it.model.setSearch('LOVE');

      expect(
        it.model.visiblePlayers.map((row) => row.id),
        equals(['p1']),
      );
    });

    test('search matches a player id', () async {
      // A report during an event is as likely to name an id read off this
      // screen as a name.
      final it = await unlocked();
      it.socket.emit(
        AdminPlayerListMessage(
          players: [player('p1', 'Ada'), player('p47', 'Bob')],
          online: 2,
        ),
      );
      await pumpEventQueue();

      it.model.setSearch('p47');

      expect(it.model.visiblePlayers.single.name, equals('Bob'));
    });

    test('a muted player is still findable by the name they chose', () async {
      final it = await unlocked();
      it.socket.emit(
        AdminPlayerListMessage(
          players: [player('p1', 'Rude Name', muted: true)],
          online: 1,
        ),
      );
      await pumpEventQueue();

      it.model.setSearch('rude');

      expect(it.model.visiblePlayers.single.id, equals('p1'));
      expect(it.model.visiblePlayers.single.displayName, equals('Guest'));
    });

    test('muted players sort to the top, then by name', () async {
      final it = await unlocked();

      it.socket.emit(
        AdminPlayerListMessage(
          players: [
            player('p1', 'Zoe'),
            player('p2', 'Ada'),
            player('p3', 'Yves', muted: true),
          ],
          online: 3,
        ),
      );
      await pumpEventQueue();

      expect(
        it.model.visiblePlayers.map((row) => row.name),
        equals(['Yves', 'Ada', 'Zoe']),
      );
    });

    test('an empty search shows everybody', () async {
      final it = await unlocked();
      it.socket.emit(
        AdminPlayerListMessage(
          players: [player('p1', 'Ada'), player('p2', 'Bob')],
          online: 2,
        ),
      );
      await pumpEventQueue();

      it.model
        ..setSearch('ada')
        ..setSearch('');

      expect(it.model.visiblePlayers, hasLength(2));
    });
  });

  group('actions', () {
    test('kick, ban and mute each send their own message', () async {
      final it = await unlocked();
      it.socket.sent.clear();

      it.model
        ..kick('p1')
        ..ban('p2')
        ..setNameMuted('p3', muted: true)
        ..setNameMuted('p4', muted: false);

      expect(
        it.socket.sentMessages,
        equals(<ProtocolMessage>[
          const AdminKickMessage(playerId: 'p1'),
          const AdminBanMessage(playerId: 'p2'),
          const AdminMuteNameMessage(playerId: 'p3', muted: true),
          const AdminMuteNameMessage(playerId: 'p4', muted: false),
        ]),
      );
    });

    test('nothing is sent before the screen is unlocked', () async {
      // A courtesy, not a control: the server refuses these on its own, and
      // would refuse them just as firmly if this check were deleted.
      final it = subject();

      it.model.kick('p1');

      expect(it.socket.sent, isEmpty);
      expect(it.model.feedback?.isError, isTrue);
    });

    test('a result becomes a sentence naming the person', () async {
      final it = await unlocked();

      it.socket.emit(
        const AdminActionResultMessage(
          action: AdminAction.ban,
          targetId: 'p1',
          targetName: 'Ada',
        ),
      );
      await pumpEventQueue();

      expect(it.model.feedback?.message, contains('Ada'));
      expect(it.model.feedback?.isError, isFalse);
    });

    test('a mute result names the placeholder they now show as', () async {
      final it = await unlocked();

      it.socket.emit(
        const AdminActionResultMessage(
          action: AdminAction.muteName,
          targetId: 'p1',
          targetName: 'Rude',
        ),
      );
      await pumpEventQueue();

      expect(it.model.feedback?.message, contains('Rude'));
      expect(it.model.feedback?.message, contains(mutedDisplayName));
    });

    test('a stale row reports the failure without locking', () async {
      final it = await unlocked();

      it.socket.emit(
        const AdminErrorMessage(
          reason: AdminError.unknownPlayer,
          detail: 'That player is no longer in the world.',
        ),
      );
      await pumpEventQueue();

      expect(it.model.feedback?.isError, isTrue);
      expect(it.model.isUnlocked, isTrue);
    });

    test('an unauthorized error locks the screen', () async {
      // The server disagreeing about who we are — a restart, or a rotated
      // token — and the server is the one that is right.
      final it = await unlocked();

      it.socket.emit(
        const AdminErrorMessage(
          reason: AdminError.unauthorized,
          detail: 'Not authorised.',
        ),
      );
      await pumpEventQueue();

      expect(it.model.stage, equals(AdminStage.locked));
    });

    test('feedback is shown once, then cleared', () async {
      final it = await unlocked();
      it.socket.emit(
        const AdminActionResultMessage(
          action: AdminAction.kick,
          targetId: 'p1',
          targetName: 'Ada',
        ),
      );
      await pumpEventQueue();

      it.model.clearFeedback();

      expect(it.model.feedback, isNull);
    });
  });

  group('the token', () {
    test('is never persisted anywhere the model exposes', () async {
      // The model deliberately has no getter for it. This test exists so
      // that adding one is a deliberate act somebody has to also delete a
      // test for.
      final it = await unlocked();

      expect(
        it.model.toString(),
        isNot(contains(token)),
      );
    });

    test('a refusal drops it, so a retry has to be typed again', () async {
      final it = subject();
      await it.model.submitToken(token);
      it.socket.emit(
        const AdminAuthResultMessage(authorized: false, detail: 'No.'),
      );
      await pumpEventQueue();

      // Nothing is auto-retried: the next auth only happens when a person
      // types one.
      expect(it.socket.sentMessages, hasLength(1));
      expect(it.model.stage, equals(AdminStage.locked));
    });
  });

  group('messages meant for the world', () {
    test('are ignored rather than handled', () async {
      // The admin socket only ever moderates. A snapshot arriving on it is a
      // server bug, not a thing this screen should try to render.
      final it = await unlocked();

      it.socket
        ..emit(const WorldStatsMessage(online: 99))
        ..emit(const PlayerLeftMessage(id: 'p1'));
      await pumpEventQueue();

      expect(it.model.online, isZero);
      expect(it.model.isUnlocked, isTrue);
    });
  });

  group('the event config', () {
    test('starts as the built-in copy, so the editor is never blank', () async {
      final it = await unlocked();

      expect(it.model.config, equals(AppConfig.defaults));
      expect(it.model.configDocument, contains('worldName'));
    });

    test('takes what the server pushes', () async {
      final it = await unlocked();

      it.socket.emit(
        const ConfigMessage(config: AppConfig(worldName: 'DashConf')),
      );
      await pumpEventQueue();

      expect(it.model.config.worldName, equals('DashConf'));
      expect(it.model.configDocument, contains('DashConf'));
    });

    test('the document is what the server holds, not what was typed', () async {
      // Including the keys the moderator left out, which are exactly the ones
      // they opened the editor to find.
      final it = await unlocked();

      it.socket.emit(
        const ConfigMessage(config: AppConfig(worldName: 'DashConf')),
      );
      await pumpEventQueue();

      expect(
        parseAppConfig(it.model.configDocument),
        equals(const AppConfig(worldName: 'DashConf')),
      );
      expect(it.model.configDocument, contains('botCounts'));
    });

    test('a push goes up as the raw text, unparsed', () async {
      // This end deliberately does not judge the document: the server holds
      // the config, so the server is the thing that gets to say no.
      final it = await unlocked()
        ..model.pushConfig('{"tagline": "not, quite, json",}');
      await pumpEventQueue();

      final sent = it.socket.sentMessages.whereType<AdminSetConfigMessage>();
      expect(sent.single.document, equals('{"tagline": "not, quite, json",}'));
    });

    test('an empty editor is a slip, and is refused here', () async {
      final it = await unlocked();

      it.model.pushConfig('   ');

      expect(
        it.socket.sentMessages.whereType<AdminSetConfigMessage>(),
        isEmpty,
      );
      expect(it.model.feedback?.isError, isTrue);
    });

    test('a locked screen cannot push, and is told so', () async {
      final it = subject();

      it.model.pushConfig('{}');

      expect(
        it.socket.sentMessages.whereType<AdminSetConfigMessage>(),
        isEmpty,
      );
      expect(it.model.feedback?.isError, isTrue);
    });

    test('the bot dial sends a whole document, not a number', () async {
      // One config on the server. A second message type that edited one field
      // of it would be a second way for the two to disagree.
      final it = await unlocked();
      it.socket.emit(
        const ConfigMessage(config: AppConfig(worldName: 'DashConf')),
      );
      await pumpEventQueue();

      it.model.setBotCount(MapId.beach, 3);
      await pumpEventQueue();

      final sent = it.socket.sentMessages
          .whereType<AdminSetConfigMessage>()
          .single;
      final pushed = parseAppConfig(sent.document);
      expect(pushed.botCountFor(MapId.beach), equals(3));
      expect(
        pushed.worldName,
        equals('DashConf'),
        reason: 'turning a dial must not revert the copy',
      );
    });

    test('the dial will not go negative', () async {
      final it = await unlocked();

      it.model.setBotCount(MapId.beach, -4);
      await pumpEventQueue();

      final sent = it.socket.sentMessages
          .whereType<AdminSetConfigMessage>()
          .single;
      expect(parseAppConfig(sent.document).botCountFor(MapId.beach), isZero);
    });

    test(
      'showing them all deletes the key rather than writing a big number',
      () async {
        // "As many as there are" and "at most forty" are different intentions,
        // and only one of them survives somebody adding a bean to the roster.
        final it = await unlocked();
        it.socket.emit(
          const ConfigMessage(
            config: AppConfig(botCounts: {MapId.beach: 3}),
          ),
        );
        await pumpEventQueue();

        it.model.clearBotCount(MapId.beach);
        await pumpEventQueue();

        final sent = it.socket.sentMessages
            .whereType<AdminSetConfigMessage>()
            .single;
        expect(parseAppConfig(sent.document).botCountFor(MapId.beach), isNull);
      },
    );

    test('locking forgets it, like everything else on the screen', () async {
      final it = await unlocked();
      it.socket.emit(
        const ConfigMessage(config: AppConfig(worldName: 'DashConf')),
      );
      await pumpEventQueue();

      it.model.lock();

      expect(it.model.config, equals(AppConfig.defaults));
    });
  });

  group('the ban list', () {
    test('starts empty and takes what the server pushes', () async {
      final it = await unlocked();
      expect(it.model.bans, isEmpty);

      it.socket.emit(
        AdminBanListMessage(
          bans: [
            BannedSession(
              id: '0123456789abcdef',
              name: 'Rude',
              bannedAt: DateTime.utc(2026, 8, 22, 18, 30),
            ),
          ],
        ),
      );
      await pumpEventQueue();

      expect(it.model.bans.single.name, equals('Rude'));
    });

    test('an unban names the handle, never a session id', () async {
      // The screen has never held one and cannot: the server does not send
      // them. This pins the shape so a future edit cannot quietly start.
      final it = await unlocked();

      it.model.unban('0123456789abcdef');
      await pumpEventQueue();

      final sent = it.socket.sentMessages.whereType<AdminUnbanMessage>().single;
      expect(sent.banId, equals('0123456789abcdef'));
    });

    test('a forgotten ban still reads as a ban', () async {
      final it = await unlocked();

      it.socket.emit(
        const AdminBanListMessage(
          bans: [BannedSession(id: 'fedcba9876543210')],
        ),
      );
      await pumpEventQueue();

      expect(it.model.bans.single.isRemembered, isFalse);
    });
  });

  group('the booth list', () {
    test('sends a whole document, like the dials do', () async {
      final it = await unlocked();
      it.socket.emit(
        const ConfigMessage(config: AppConfig(worldName: 'DashConf')),
      );
      await pumpEventQueue();

      it.model.setSponsors([
        {'id': 'acme', 'name': 'Acme', 'x': 1130.0, 'y': 478.0},
      ]);
      await pumpEventQueue();

      final sent = it.socket.sentMessages
          .whereType<AdminSetConfigMessage>()
          .single;
      final pushed = parseAppConfig(sent.document);
      expect(pushed.sponsors.single['id'], equals('acme'));
      expect(
        pushed.worldName,
        equals('DashConf'),
        reason: 'editing a booth must not revert the copy',
      );
    });

    test('an empty list is how the bundled one is asked for', () async {
      final it = await unlocked();

      it.model.setSponsors(const []);
      await pumpEventQueue();

      final sent = it.socket.sentMessages
          .whereType<AdminSetConfigMessage>()
          .single;
      expect(parseAppConfig(sent.document).sponsors, isEmpty);
    });

    test('a list the world would refuse is not sent at all', () async {
      // Unlike a hand-typed document, this list is one the screen built out
      // of its own fields. Sending it to be refused would report a bug here
      // as a mistake there.
      final it = await unlocked();

      it.model.setSponsors(
        const [
          {'id': 'a'},
          {'id': 'a'},
        ],
        validate: (entries) {
          if (entries.length > 1) {
            throw const FormatException('two sponsors share the id "a"');
          }
        },
      );
      await pumpEventQueue();

      expect(
        it.socket.sentMessages.whereType<AdminSetConfigMessage>(),
        isEmpty,
      );
      expect(it.model.feedback?.isError, isTrue);
    });
  });

  group('maintenance', () {
    Future<AdminSetMaintenanceMessage?> sentMaintenance(
      FakeSocket socket,
    ) async {
      await pumpEventQueue();
      return socket.sentMessages
          .whereType<AdminSetMaintenanceMessage>()
          .firstOrNull;
    }

    test('sends the moment in UTC, whatever the picker handed over', () async {
      // The picker deals in wall-clock time on one device; the server and
      // every other device need the instant.
      final it = await unlocked();
      final until = DateTime.now().add(const Duration(hours: 2));

      it.model.setMaintenance(token: token, until: until);

      final sent = await sentMaintenance(it.socket);
      expect(sent?.until?.isUtc, isTrue);
      expect(
        sent?.until?.millisecondsSinceEpoch,
        equals(until.millisecondsSinceEpoch),
      );
    });

    test('carries the notice and the clock flag', () async {
      final it = await unlocked();

      it.model.setMaintenance(
        token: token,
        until: DateTime.now().add(const Duration(hours: 2)),
        message: '  The keynote overran.  ',
        showTimer: false,
      );

      final sent = await sentMaintenance(it.socket);
      expect(sent?.message, equals('The keynote overran.'));
      expect(sent?.showTimer, isFalse);
    });

    test('reopening sends the defaults, which is what clears them', () async {
      final it = await unlocked();

      it.model.setMaintenance(token: token);

      final sent = await sentMaintenance(it.socket);
      expect(sent?.message, isEmpty);
      expect(sent?.showTimer, isTrue);
    });

    test('a null until is how the event is reopened', () async {
      final it = await unlocked();

      it.model.setMaintenance(token: token);

      final sent = await sentMaintenance(it.socket);
      expect(sent, isNotNull);
      expect(sent?.until, isNull);
    });

    test(
      'carries the token that was typed, not the one it is holding',
      () async {
        // The point of asking again is that it is asked. A model that quietly
        // reached for its own copy would give the dialog the shape of a
        // security check and none of the substance.
        final it = await unlocked();

        it.model.setMaintenance(token: 'a-different-token');

        expect((await sentMaintenance(it.socket))?.token, 'a-different-token');
      },
    );

    test('an empty token is refused without sending anything', () async {
      final it = await unlocked();

      it.model.setMaintenance(token: '   ');

      expect(await sentMaintenance(it.socket), isNull);
      expect(it.model.feedback?.isError, isTrue);
    });

    test(
      'a time that has passed is refused without sending anything',
      () async {
        final it = await unlocked();

        it.model.setMaintenance(
          token: token,
          until: DateTime.now().subtract(const Duration(minutes: 1)),
        );

        expect(await sentMaintenance(it.socket), isNull);
        expect(it.model.feedback?.isError, isTrue);
      },
    );

    test('a locked screen cannot close the event', () async {
      // The courtesy check, not the control: the server refuses this too.
      final it = subject();

      it.model.setMaintenance(
        token: token,
        until: DateTime.now().add(
          const Duration(hours: 1),
        ),
      );

      expect(await sentMaintenance(it.socket), isNull);
    });

    test('reads the window back off the config the server pushed', () async {
      final it = await unlocked();
      final until = DateTime.now().toUtc().add(const Duration(hours: 1));

      it.socket.emit(ConfigMessage(config: AppConfig(maintenanceUntil: until)));
      await pumpEventQueue();

      expect(it.model.maintenanceUntil, equals(until));
      expect(it.model.isUnderMaintenance, isTrue);
    });

    test('a window that has passed does not read as closed', () async {
      final it = await unlocked();

      it.socket.emit(
        ConfigMessage(
          config: AppConfig(
            maintenanceUntil: DateTime.now().toUtc().subtract(
              const Duration(minutes: 1),
            ),
          ),
        ),
      );
      await pumpEventQueue();

      expect(it.model.isUnderMaintenance, isFalse);
    });

    test('the confirmation reads back on the moderator own clock', () async {
      // They picked a wall-clock time and are owed the same one back, or they
      // cannot tell a success from an off-by-five-hours.
      final it = await unlocked();
      final until = DateTime(2026, 8, 22, 18, 30);

      it.socket.emit(
        AdminActionResultMessage(
          action: AdminAction.maintenanceOn,
          targetId: 'event',
          targetName: until.toUtc().toIso8601String(),
        ),
      );
      await pumpEventQueue();

      expect(it.model.feedback?.message, contains('22 Aug 2026, 18:30'));
      expect(it.model.feedback?.isError, isFalse);
    });

    test('an unreadable moment is still a sentence', () async {
      // A confirmation that threw would turn a successful action into a crash.
      final it = await unlocked();

      it.socket.emit(
        const AdminActionResultMessage(
          action: AdminAction.maintenanceOn,
          targetId: 'event',
          targetName: 'whenever',
        ),
      );
      await pumpEventQueue();

      expect(it.model.feedback?.message, contains('whenever'));
    });
  });
}
