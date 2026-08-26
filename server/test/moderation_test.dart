import 'dart:convert';
import 'dart:io';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  group('ModerationState bans', () {
    test('an unbanned session is not banned', () {
      expect(ModerationState().isBanned('a' * 32), isFalse);
    });

    test('a ban sticks and is persisted', () {
      final storage = InMemoryBanStorage();
      ModerationState(storage: storage).ban('a' * 32);

      expect(storage.saved, equals({'a' * 32}));
    });

    test('bans are loaded back on construction', () {
      // The restart-mid-event case: a server that comes back up with an
      // empty ban list has silently readmitted everybody it removed.
      final storage = InMemoryBanStorage({'a' * 32});

      expect(ModerationState(storage: storage).isBanned('a' * 32), isTrue);
    });

    test('banning twice writes once', () {
      var writes = 0;
      final storage = _CountingBanStorage(() => writes++);
      ModerationState(storage: storage)
        ..ban('a' * 32)
        ..ban('a' * 32);

      expect(writes, equals(1));
    });

    test('an unban is persisted too', () {
      final storage = InMemoryBanStorage({'a' * 32});
      ModerationState(storage: storage).unban('a' * 32);

      expect(storage.saved, isEmpty);
    });
  });

  group('ModerationState ban list', () {
    final session = 'a' * 32;

    test('a handle never contains the session id it is for', () {
      // The whole reason the handle exists: a session id is a bearer token,
      // so it must not reach the admin screen even under a trusted moderator.
      final handle = ModerationState.banHandleFor(session);

      expect(handle, isNot(contains(session)));
      expect(session, isNot(contains(handle)));
      expect(handle, hasLength(16));
    });

    test('the same session always gets the same handle', () {
      // Without this a ban read off disk after a restart could never be
      // lifted from the screen — its row would answer to a handle nobody had.
      expect(
        ModerationState.banHandleFor(session),
        equals(ModerationState.banHandleFor(session)),
      );
      expect(
        ModerationState.banHandleFor(session),
        isNot(equals(ModerationState.banHandleFor('b' * 32))),
      );
    });

    test('a ban taken this run carries the name and the moment', () {
      final at = DateTime.utc(2026, 8, 22, 18, 30);
      final state = ModerationState(
        storage: InMemoryBanStorage(),
        now: () => at,
      )..ban(session, name: 'Rude');

      final ban = state.bans.single;
      expect(ban.id, equals(ModerationState.banHandleFor(session)));
      expect(ban.name, equals('Rude'));
      expect(ban.bannedAt, equals(at));
      expect(ban.isRemembered, isTrue);
    });

    test('a ban loaded from disk has a handle and nothing else', () {
      // The ban file keeps ids and nothing else, on purpose: a file of the
      // names people were removed for is a document somebody has to own.
      final state = ModerationState(storage: InMemoryBanStorage({session}));

      final ban = state.bans.single;
      expect(ban.id, equals(ModerationState.banHandleFor(session)));
      expect(ban.name, isEmpty);
      expect(ban.bannedAt, isNull);
      expect(ban.isRemembered, isFalse);
    });

    test('remembered bans come first, newest of them at the top', () {
      var clock = DateTime.utc(2026);
      final state = ModerationState(
        storage: InMemoryBanStorage({'c' * 32}),
        now: () => clock,
      )..ban('a' * 32, name: 'First');
      clock = clock.add(const Duration(minutes: 5));
      state.ban('b' * 32, name: 'Second');

      expect(
        state.bans.map((ban) => ban.name),
        equals(['Second', 'First', '']),
      );
    });

    test('unbanning by handle lifts it and says whose it was', () {
      final storage = InMemoryBanStorage();
      final state = ModerationState(storage: storage)
        ..ban(session, name: 'Rude');

      final name = state.unbanByHandle(ModerationState.banHandleFor(session));

      expect(name, equals('Rude'));
      expect(state.isBanned(session), isFalse);
      expect(storage.saved, isEmpty);
      expect(state.bans, isEmpty);
    });

    test('a forgotten ban lifts to the empty string, not to null', () {
      // Null means "no such ban"; empty means "lifted, and this run never
      // knew whose it was". The admin screen shows different things for the
      // two, so they must not be the same answer.
      final state = ModerationState(storage: InMemoryBanStorage({session}));

      expect(
        state.unbanByHandle(ModerationState.banHandleFor(session)),
        isEmpty,
      );
      expect(state.isBanned(session), isFalse);
    });

    test('a handle nobody answers to lifts nothing', () {
      final state = ModerationState(storage: InMemoryBanStorage({session}));

      expect(state.unbanByHandle('0123456789abcdef'), isNull);
      expect(state.isBanned(session), isTrue);
    });

    test('a lifted ban forgets the name with it', () {
      // Otherwise a re-ban of the same session would show the name they had
      // the *first* time, which may be exactly the name that got them
      // removed and then changed.
      final state = ModerationState(storage: InMemoryBanStorage())
        ..ban(session, name: 'Rude')
        ..unban(session)
        ..ban(session);

      expect(state.bans.single.name, isEmpty);
    });
  });

  group('ModerationState kick cooldown', () {
    final session = 'f' * 32;

    test('a session nobody kicked may join right now', () {
      expect(ModerationState().kickCooldownLeft(session), isNull);
    });

    test('a kicked session is refused for the cooldown', () {
      // The whole reason this exists: the client reconnects in well under a
      // second, so a kick that only closes a socket is a kick that undoes
      // itself before the moderator has looked up from the phone.
      var now = DateTime.utc(2026, 3, 14, 9, 30);
      final state = ModerationState(now: () => now)..recordKick(session);

      expect(
        state.kickCooldownLeft(session),
        equals(const Duration(seconds: 30)),
      );

      now = now.add(const Duration(milliseconds: 500));
      expect(
        state.kickCooldownLeft(session),
        equals(const Duration(seconds: 29, milliseconds: 500)),
      );
    });

    test('the cooldown ends and does not come back', () {
      var now = DateTime.utc(2026, 3, 14, 9, 30);
      final state = ModerationState(now: () => now)..recordKick(session);

      now = now.add(const Duration(seconds: 30));

      expect(state.kickCooldownLeft(session), isNull);
      expect(state.kickCooldownLeft(session), isNull);
    });

    test('a second kick restarts the clock', () {
      var now = DateTime.utc(2026, 3, 14, 9, 30);
      final state = ModerationState(now: () => now)..recordKick(session);

      now = now.add(const Duration(seconds: 20));
      state.recordKick(session);

      expect(
        state.kickCooldownLeft(session),
        equals(const Duration(seconds: 30)),
      );
    });

    test('a zero cooldown records nothing', () {
      // A supported configuration, not a special case: it is what a
      // deployment whose clients never auto-reconnect would want.
      final state = ModerationState(kickCooldown: Duration.zero)
        ..recordKick(session);

      expect(state.kickCooldownLeft(session), isNull);
    });

    test('kicking nobody else', () {
      final state = ModerationState()..recordKick(session);

      expect(state.kickCooldownLeft('a' * 32), isNull);
    });

    test('expired entries are swept by the next kick', () {
      // The map must not grow for the length of the event.
      var now = DateTime.utc(2026, 3, 14, 9, 30);
      final state = ModerationState(now: () => now)..recordKick(session);

      now = now.add(const Duration(seconds: 31));
      state.recordKick('a' * 32);

      expect(state.cooldownCount, equals(1));
    });
  });

  group('ModerationState blocked names', () {
    final session = 'e' * 32;

    test('a name nobody took away is usable', () {
      expect(ModerationState().isNameBlocked(session, 'Ada'), isFalse);
    });

    test('a blocked name stays blocked', () {
      final state = ModerationState()..blockName(session, 'Ada');

      expect(state.isNameBlocked(session, 'Ada'), isTrue);
      expect(state.blockedNameCount, equals(1));
    });

    test('capitals and spacing are not a way round it', () {
      // Three spellings of one name, as far as anybody reading a bean is
      // concerned.
      final state = ModerationState()..blockName(session, 'Ada Lovelace');

      expect(state.isNameBlocked(session, ' ada   lovelace '), isTrue);
      expect(state.isNameBlocked(session, 'ADA LOVELACE'), isTrue);
    });

    test('a second kick blocks the new name too', () {
      final state = ModerationState()
        ..blockName(session, 'Ada')
        ..blockName(session, 'Bob');

      expect(state.isNameBlocked(session, 'Ada'), isTrue);
      expect(state.isNameBlocked(session, 'Bob'), isTrue);
    });

    test('another name is still free', () {
      final state = ModerationState()..blockName(session, 'Ada');

      expect(state.isNameBlocked(session, 'Grace'), isFalse);
    });

    test('it blocks nobody else', () {
      // Keyed on the session, like every other moderation decision. Taking a
      // name off the whole event would punish everybody who shares it.
      final state = ModerationState()..blockName(session, 'Ada');

      expect(state.isNameBlocked('a' * 32, 'Ada'), isFalse);
    });
  });

  group('ModerationState mute', () {
    final session = 'b' * 32;

    test('an unmuted session keeps the name it chose', () {
      expect(ModerationState().effectiveName(session, 'Ada'), equals('Ada'));
    });

    test('a muted session is shown as the placeholder', () {
      final state = ModerationState()..muteName(session, 'Ada');

      expect(state.effectiveName(session, 'Ada'), equals(mutedDisplayName));
      expect(state.isNameMuted(session), isTrue);
    });

    test('an unmute gives the chosen name back', () {
      final state = ModerationState()..muteName(session, 'Ada');

      expect(state.unmuteName(session), equals('Ada'));
      expect(state.effectiveName(session, 'Ada'), equals('Ada'));
    });

    test('muting twice does not overwrite the chosen name', () {
      // Without the guard the second mute records "Guest" as the name they
      // chose, and the unmute hands it back as their real one.
      final state = ModerationState()
        ..muteName(session, 'Ada')
        ..muteName(session, mutedDisplayName);

      expect(state.unmuteName(session), equals('Ada'));
    });

    test('rejoining under a new name stays muted, and records the new one', () {
      // The obvious workaround — reconnect with a different name — has to
      // fail, and the admin list has to show what they tried.
      final state = ModerationState()..muteName(session, 'Ada');

      expect(
        state.effectiveName(session, 'Something Else'),
        equals(mutedDisplayName),
      );
      expect(state.chosenNameOf(session), equals('Something Else'));
    });

    test('unmuting a session that was never muted is null', () {
      expect(ModerationState().unmuteName(session), isNull);
    });
  });

  group('FileBanStorage', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('bans'));
    tearDown(() => dir.deleteSync(recursive: true));

    String pathIn(String name) => '${dir.path}${Platform.pathSeparator}$name';

    test('a missing file reads as no bans', () {
      expect(FileBanStorage(path: pathIn('nope.json')).load(), isEmpty);
    });

    test('what is saved is what is loaded', () {
      final path = pathIn('bans.json');
      FileBanStorage(path: path).save({'a' * 32, 'b' * 32});

      expect(
        FileBanStorage(path: path).load(),
        equals({'a' * 32, 'b' * 32}),
      );
    });

    test('a corrupt file reads as no bans instead of throwing', () {
      // An event with no bans loaded is a bad day. An event with no server
      // is a much worse one, so a mangled file must not stop startup.
      final path = pathIn('bans.json');
      File(path).writeAsStringSync('{not json');

      final errors = <String>[];
      expect(FileBanStorage(path: path, onError: errors.add).load(), isEmpty);
      expect(errors, hasLength(1));
    });

    test('entries that are not session ids are ignored', () {
      // A hand-edited file should not be able to put "../" or a megabyte of
      // text into a set the server keys lookups on.
      final path = pathIn('bans.json');
      File(path).writeAsStringSync(jsonEncode(['a' * 32, '../etc', 7]));

      expect(FileBanStorage(path: path).load(), equals({'a' * 32}));
    });
  });

  group('AuditLog', () {
    test('records the action, the target and when it happened', () {
      final lines = <String>[];
      AuditLog(
        path: null,
        log: lines.add,
        now: () => DateTime.utc(2026, 3, 14, 9, 30),
      ).record(
        action: AdminAction.ban,
        targetId: 'p7',
        targetName: 'Ada',
      );

      expect(lines.single, contains('2026-03-14T09:30:00.000Z'));
      expect(lines.single, contains('ban'));
      expect(lines.single, contains('p7'));
      expect(lines.single, contains('Ada'));
    });

    test('appends to its file without clobbering earlier lines', () {
      final dir = Directory.systemTemp.createTempSync('audit');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}audit.log';

      final audit = AuditLog(path: path, log: (_) {})
        ..record(
          action: AdminAction.kick,
          targetId: 'p1',
          targetName: 'Ada',
        )
        ..record(
          action: AdminAction.muteName,
          targetId: 'p2',
          targetName: 'Bob',
        );

      expect(audit.path, equals(path));
      expect(File(path).readAsLinesSync(), hasLength(2));
    });

    test('a file it cannot write does not stop the action', () {
      // The kick still has to go through: losing the record is bad, leaving
      // the disruption in the room is worse.
      final lines = <String>[];
      AuditLog(
        path: '${Platform.pathSeparator}nope${Platform.pathSeparator}a.log',
        log: lines.add,
      ).record(
        action: AdminAction.kick,
        targetId: 'p1',
        targetName: 'Ada',
      );

      expect(lines.first, contains('audit:'));
      expect(lines.last, contains('could not append'));
    });
  });

  group('registry moderation', () {
    JoinMessage joinAs(String session, String name) => JoinMessage(
      sessionId: session,
      name: name,
      color: 0xFF54C5F8,
      cosmetic: PlayerCosmetic.none,
    );

    test('a muted session is seated under the placeholder', () {
      final moderation = ModerationState()..muteName('c' * 32, 'Rude');
      final registry = PlayerRegistry(moderation: moderation);

      expect(
        registry.seat(joinAs('c' * 32, 'Rude')).player.name,
        equals(mutedDisplayName),
      );
    });

    test('the session behind a player id is answerable', () {
      final registry = PlayerRegistry();
      final seat = registry.seat(joinAs('d' * 32, 'Ada'));

      expect(registry.sessionOf(seat.player.id), equals('d' * 32));
      expect(registry.sessionOf('nobody'), isNull);
    });

    test('a rename keeps everything except the name', () {
      final registry = PlayerRegistry();
      final before = registry.seat(joinAs('e' * 32, 'Ada')).player;

      final after = registry.rename(before.id, mutedDisplayName)!;

      expect(after.name, equals(mutedDisplayName));
      expect(after.color, equals(before.color));
      expect(after.x, equals(before.x));
      expect(after.y, equals(before.y));
      expect(registry[before.id], equals(after));
    });

    test('renaming somebody who is not here is null, not a crash', () {
      expect(PlayerRegistry().rename('p99', 'Guest'), isNull);
    });

    test('forgetting a session drops its held seat', () {
      final registry = PlayerRegistry();
      final seat = registry.seat(joinAs('f' * 32, 'Ada'));
      registry.remove(seat.player.id);
      expect(registry.heldSeatCount, equals(1));

      registry.forgetSession('f' * 32);

      expect(registry.heldSeatCount, isZero);
      // ...so a returning join is a brand-new seat, not a resumed one.
      expect(
        registry.seat(joinAs('f' * 32, 'Ada')).kind,
        equals(SeatKind.fresh),
      );
    });
  });
}

/// A storage that only counts how often it was written to.
class _CountingBanStorage implements BanStorage {
  _CountingBanStorage(this._onSave);

  final void Function() _onSave;

  @override
  Set<String> load() => {};

  @override
  void save(Set<String> sessionIds) => _onSave();
}
