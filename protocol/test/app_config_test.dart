import 'dart:convert';

import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('the repository link', () {
    test('reads what a moderator wrote', () {
      final config = parseAppConfig('{"githubLink": "https://example.dev/x"}');

      expect(config.githubLink, equals('https://example.dev/x'));
    });

    test('falls back to this project when the key is missing', () {
      // The QR in the corner of the world is a poster. A key dropped in an
      // edit must show a repository, not an empty sheet.
      expect(
        parseAppConfig('{"tagline": "walk around"}').githubLink,
        equals(AppConfig.defaultGithubLink),
      );
    });

    test('falls back when the key is there but empty', () {
      expect(
        parseAppConfig('{"githubLink": "   "}').githubLink,
        equals(AppConfig.defaultGithubLink),
      );
    });

    test('survives the round trip the admin editor relies on', () {
      final config = parseAppConfig('{"githubLink": "https://example.dev/x"}');

      final later = parseAppConfig(jsonEncode(config.toJson()));

      expect(later.githubLink, equals('https://example.dev/x'));
      expect(later, equals(config));
    });

    test('is written even when nobody has changed it, so it is findable', () {
      // The document is also the thing a moderator edits by hand: a key that
      // only appears once somebody has used the feature is a key nobody
      // discovers.
      expect(
        AppConfig.defaults.toJson()['githubLink'],
        equals(AppConfig.defaultGithubLink),
      );
    });

    test('two configs differing only in the link are not equal', () {
      expect(
        const AppConfig(githubLink: 'https://example.dev/x'),
        isNot(equals(AppConfig.defaults)),
      );
    });
  });

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

  group('the sponsor list', () {
    test('carries the booth entries through untouched', () {
      final config = parseAppConfig(
        '{"sponsors": [{"id": "a", "name": "A", "x": 1, "y": 2, '
        '"color": "#54C5F8"}]}',
      );

      expect(config.sponsors, hasLength(1));
      expect(config.sponsors.single['id'], equals('a'));
      // Opaque on purpose: the colour stays the text it was written as,
      // because parsing it needs a `dart:ui` type this package cannot have.
      expect(config.sponsors.single['color'], equals('#54C5F8'));
    });

    test('means "use the bundled list" when the key is missing', () {
      expect(parseAppConfig('{}').sponsors, isEmpty);
    });

    test('drops entries that are not objects rather than throwing', () {
      final config = parseAppConfig('{"sponsors": [1, {"id": "a"}, "x"]}');

      expect(config.sponsors, hasLength(1));
      expect(config.sponsors.single['id'], equals('a'));
    });

    test('falls back whole when the key is not a list', () {
      expect(parseAppConfig('{"sponsors": "none"}').sponsors, isEmpty);
    });

    test('survives the round trip the admin editor relies on', () {
      final config = parseAppConfig(
        '{"sponsors": [{"id": "a", "name": "A", "x": 1, "y": 2, '
        '"color": "#54C5F8"}]}',
      );

      final again = AppConfig.fromJson(config.toJson());

      expect(again, equals(config));
      expect(again.sponsors.single['name'], equals('A'));
    });

    test('two configs differing only in a booth are not equal', () {
      final a = parseAppConfig('{"sponsors": [{"id": "a"}]}');
      final b = parseAppConfig('{"sponsors": [{"id": "b"}]}');

      expect(a, isNot(equals(b)));
    });

    test('an unrelated edit does not drop the booths', () {
      // Both copy methods rebuild the whole config by hand, so a field one of
      // them forgot to carry disappears on the next tap of a bot dial.
      final config = parseAppConfig('{"sponsors": [{"id": "a"}]}');

      expect(config.withBotCounts({MapId.beach: 3}).sponsors, hasLength(1));
      expect(config.withMaintenanceUntil(null).sponsors, hasLength(1));
    });

    test('withSponsors replaces the list and keeps everything else', () {
      final config = parseAppConfig(
        '{"worldName": "Held", "sponsors": [{"id": "a"}]}',
      );

      final next = config.withSponsors([
        {'id': 'b', 'name': 'Beta'},
      ]);

      expect(next.sponsors.single['id'], equals('b'));
      expect(next.worldName, equals('Held'));
    });
  });

  group('the pause notice', () {
    test('carries the sentence and the clock flag through the wire', () {
      final config = parseAppConfig(
        '{"maintenanceMessage": " Back in ten. ", '
        '"maintenanceShowTimer": false}',
      );

      expect(config.maintenanceMessage, equals('Back in ten.'));
      expect(config.maintenanceShowTimer, isFalse);
    });

    test('says nothing and shows the clock by default', () {
      // What every config written before this feature existed meant.
      final config = parseAppConfig('{}');

      expect(config.maintenanceMessage, isEmpty);
      expect(config.maintenanceShowTimer, isTrue);
    });

    test('reads the flag written as a string, because people type it', () {
      expect(
        parseAppConfig('{"maintenanceShowTimer": "false"}')
            .maintenanceShowTimer,
        isFalse,
      );
      expect(
        parseAppConfig('{"maintenanceShowTimer": 7}').maintenanceShowTimer,
        isTrue,
      );
    });

    test('survives the round trip the admin editor relies on', () {
      final config = parseAppConfig(
        '{"maintenanceMessage": "Back in ten.", '
        '"maintenanceShowTimer": false}',
      );

      expect(AppConfig.fromJson(config.toJson()), equals(config));
    });

    test('moving the moment alone keeps the sentence', () {
      // The failure this guards is a moderator extending a window and
      // silently wiping the notice they wrote a minute earlier.
      final config = parseAppConfig('{"maintenanceMessage": "Back in ten."}');

      final later = config.withMaintenanceUntil(DateTime.utc(2031));

      expect(later.maintenanceMessage, equals('Back in ten.'));
      expect(later.maintenanceShowTimer, isTrue);
    });

    test('two configs differing only in the notice are not equal', () {
      expect(
        parseAppConfig('{"maintenanceMessage": "a"}'),
        isNot(equals(parseAppConfig('{"maintenanceMessage": "b"}'))),
      );
      expect(
        parseAppConfig('{"maintenanceShowTimer": false}'),
        isNot(equals(parseAppConfig('{}'))),
      );
    });
  });
}
