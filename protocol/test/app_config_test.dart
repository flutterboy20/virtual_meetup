import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('parsing a config document', () {
    test('reads the wordmark and both lines of copy', () {
      final config = parseAppConfig(
        '{"worldName": "DashConf", "eyebrow": "A tiny world", '
        '"tagline": "walk around"}',
      );

      expect(config.worldName, equals('DashConf'));
      expect(config.eyebrow, equals('A tiny world'));
      expect(config.tagline, equals('walk around'));
    });

    test('names no conference of its own when the document omits one', () {
      // The whole point of the field: the app ships generic, and whoever runs
      // an event writes their name into config rather than into a widget.
      final config = parseAppConfig('{"tagline": "walk around"}');

      expect(config.worldName, equals(AppConfig.defaultWorldName));
    });

    test('trims what somebody pasted in', () {
      final config = parseAppConfig('{"tagline": "  walk around  "}');

      expect(config.tagline, equals('walk around'));
    });

    test('falls back per key, not per document', () {
      // Half a bad document still gets the half that was fine onto the
      // screen: a missing tagline must not cost us the eyebrow too.
      final config = parseAppConfig('{"eyebrow": "A tiny world"}');

      expect(config.eyebrow, equals('A tiny world'));
      expect(config.tagline, equals(AppConfig.defaultTagline));
      expect(config.boardMessage, equals(AppConfig.defaultBoardMessage));
      expect(config.stageLines, equals(AppConfig.defaultStageLines));
    });

    test('treats empty and non-string values as absent', () {
      // An endpoint that answers with a blank string would otherwise wipe the
      // words off the front door, which is the one thing it must not do.
      final config = parseAppConfig('{"eyebrow": "   ", "tagline": 42}');

      expect(config, equals(AppConfig.defaults));
    });

    test('answers with the built-in copy for a document that is not JSON', () {
      expect(
        parseAppConfig('<html>504 Gateway Timeout</html>'),
        equals(AppConfig.defaults),
      );
    });

    test('answers with the built-in copy for JSON of the wrong shape', () {
      expect(parseAppConfig('["eyebrow"]'), equals(AppConfig.defaults));
      expect(parseAppConfig('null'), equals(AppConfig.defaults));
    });
  });

  group('the strict parse', () {
    test('refuses what the lenient one quietly swallows', () {
      // The whole difference between the two, and it exists for one screen:
      // a moderator whose paste has a trailing comma in it has to be told, in
      // the next second, by the thing they typed into.
      expect(tryParseAppConfig('{"tagline": "x",}'), isNull);
      expect(tryParseAppConfig('<html>504</html>'), isNull);
      expect(tryParseAppConfig('["eyebrow"]'), isNull);
      expect(tryParseAppConfig('null'), isNull);
    });

    test('accepts an empty object, which means all defaults', () {
      // Strict about the *document*, not about its contents. A config with no
      // keys is a perfectly good instruction: use everything built in.
      expect(tryParseAppConfig('{}'), equals(AppConfig.defaults));
    });
  });

  group('bot counts', () {
    test('are read per map, and absent means the whole roster', () {
      final config = parseAppConfig('{"botCounts": {"conference": 6}}');

      expect(config.botCountFor(MapId.conference), equals(6));
      expect(
        config.botCountFor(MapId.beach),
        isNull,
        reason: 'a map the document says nothing about is not capped',
      );
    });

    test('zero is a real answer, and means an empty room', () {
      // Distinct from absent on purpose: "no bots" is a thing a moderator
      // might genuinely want on the day the room is actually full.
      final config = parseAppConfig('{"botCounts": {"beach": 0}}');

      expect(config.botCountFor(MapId.beach), equals(0));
    });

    test('a broken entry costs that entry and nothing else', () {
      final config = parseAppConfig(
        '{"botCounts": {"conference": -3, "beach": "lots", "moon": 4}}',
      );

      expect(config.botCounts, isEmpty);
      expect(config.worldName, equals(AppConfig.defaultWorldName));
    });

    test('withBotCounts changes the dial and nothing else', () {
      const before = AppConfig(worldName: 'DashConf', tagline: 'hello');

      final after = before.withBotCounts({MapId.beach: 3});

      expect(after.worldName, equals('DashConf'));
      expect(after.tagline, equals('hello'));
      expect(after.botCountFor(MapId.beach), equals(3));
    });
  });

  group('the round trip', () {
    test('a config that has been through JSON is the config that went in', () {
      // The admin editor relies on this exactly: it shows `toJson`, somebody
      // edits it, and it goes back the way it came.
      const before = AppConfig(
        worldName: 'DashConf',
        eyebrow: 'DAY TWO',
        tagline: 'same beans',
        boardMessage: 'the wifi is fine',
        stageLines: ['one', 'two'],
        botCounts: {MapId.conference: 9, MapId.beach: 2},
      );

      expect(AppConfig.fromJson(before.toJson()), equals(before));
    });

    test('the defaults survive it too', () {
      expect(
        AppConfig.fromJson(AppConfig.defaults.toJson()),
        equals(AppConfig.defaults),
      );
    });

    test('two configs differing only in a bot count are not equal', () {
      // Everything downstream is a no-op on an unchanged config — the game
      // skips the work, the view model skips the notify — so an equality that
      // ignored this field would silently make the dial do nothing.
      const a = AppConfig(botCounts: {MapId.beach: 1});
      const b = AppConfig(botCounts: {MapId.beach: 2});

      expect(a, isNot(equals(b)));
    });

    test('two configs differing only in the maintenance window differ', () {
      // The same reason as the bot count above, and it matters more here:
      // the client's dedupe gates drop a config equal to the one they hold,
      // so an equality that ignored this would let an event be closed on the
      // server and open on every screen.
      final a = AppConfig(maintenanceUntil: DateTime.utc(2026, 8, 22, 18));
      final b = AppConfig(maintenanceUntil: DateTime.utc(2026, 8, 22, 19));

      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(AppConfig.defaults)));
    });
  });

  group('the maintenance window', () {
    final until = DateTime.utc(2026, 8, 22, 18, 30);

    test('survives the round trip, in UTC', () {
      final config = AppConfig(maintenanceUntil: until);

      expect(
        AppConfig.fromJson(config.toJson()).maintenanceUntil,
        equals(until),
      );
    });

    test('a local time is written as the instant it is', () {
      // The server and the phone are in different places. Whatever a picker
      // hands over, what goes on the wire is the moment, not the wall clock.
      final local = DateTime.now();
      final config = AppConfig.defaults.withMaintenanceUntil(local);

      expect(config.maintenanceUntil!.isUtc, isTrue);
      expect(
        config.maintenanceUntil!.millisecondsSinceEpoch,
        local.millisecondsSinceEpoch,
      );
    });

    test('an unreadable value means the event is open', () {
      // This document is hand-edited. One mistyped character must not shut an
      // event, and must not throw where every other field falls back.
      for (final broken in <Object?>[
        'not a date',
        'tomorrow',
        '18:30',
        42,
        <String>[],
        null,
      ]) {
        expect(
          AppConfig.fromJson({'maintenanceUntil': broken}).maintenanceUntil,
          isNull,
          reason: '$broken should read as open',
        );
      }
    });

    test('the key is written even when there is no window', () {
      // A key that only appears once somebody has used the feature is a key
      // nobody discovers in the editor.
      expect(AppConfig.defaults.toJson(), contains('maintenanceUntil'));
      expect(AppConfig.defaults.toJson()['maintenanceUntil'], isNull);
    });

    test('is closed before the moment and open at it', () {
      final config = AppConfig(maintenanceUntil: until);

      expect(
        config.isUnderMaintenanceAt(until.subtract(const Duration(minutes: 1))),
        isTrue,
      );
      // The boundary is open, not closed: "until 18:30" means the door is
      // unlocked at 18:30.
      expect(config.isUnderMaintenanceAt(until), isFalse);
      expect(
        config.isUnderMaintenanceAt(until.add(const Duration(minutes: 1))),
        isFalse,
      );
    });

    test('no window is never under maintenance', () {
      expect(AppConfig.defaults.isUnderMaintenanceAt(DateTime.now()), isFalse);
    });

    test('turning a bot dial does not open a closed event', () {
      // `withBotCounts` rebuilds the whole config. A field it forgot to carry
      // would be silently dropped by the next tap of an unrelated dial.
      final closed = AppConfig(maintenanceUntil: until);

      expect(
        closed.withBotCounts({MapId.beach: 3}).maintenanceUntil,
        equals(until),
      );
    });

    test('a null window reopens the event', () {
      final closed = AppConfig(maintenanceUntil: until);

      expect(closed.withMaintenanceUntil(null).maintenanceUntil, isNull);
    });
  });
}
