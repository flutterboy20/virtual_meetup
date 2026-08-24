import 'dart:io';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('config-store-test'));
  tearDown(() => dir.deleteSync(recursive: true));

  String pathIn(String name) => '${dir.path}${Platform.pathSeparator}$name';

  group('reading what is already there', () {
    test('a missing file is the built-in copy, not a crash', () {
      // The first boot of every deployment, and it must be a boring one.
      final log = <String>[];
      final store = ConfigStore(path: pathIn('nope.json'), log: log.add);

      expect(store.config, equals(AppConfig.defaults));
      expect(log.join(), contains('no config file'));
    });

    test('a file that is there is the config that is served', () {
      final at = pathIn('config.json');
      File(at).writeAsStringSync('{"worldName": "DashConf"}');

      expect(ConfigStore(path: at).config.worldName, equals('DashConf'));
    });

    test('a file somebody broke by hand is loud, and not fatal', () {
      // The event still has to start. It must not start *silently* on the
      // wrong copy, though — the whole room would be looking at last month's
      // tagline with nothing anywhere saying why.
      final at = pathIn('config.json');
      File(at).writeAsStringSync('{"worldName": "DashConf",}');
      final log = <String>[];

      final store = ConfigStore(path: at, log: log.add);

      expect(store.config, equals(AppConfig.defaults));
      expect(log.join(), contains('not readable JSON'));
    });
  });

  group('applying a push', () {
    test('takes a good document and answers with it', () {
      final store = ConfigStore(path: pathIn('config.json'));

      final applied = store.apply('{"tagline": "day two, same beans"}');

      expect(applied?.tagline, equals('day two, same beans'));
      expect(store.config.tagline, equals('day two, same beans'));
    });

    test('refuses a bad one and changes nothing', () {
      // The one place in the system where somebody is standing there waiting
      // to be told they made a mistake. Quietly keeping the old config would
      // look exactly like a push that worked.
      final store = ConfigStore(path: pathIn('config.json'))
        ..apply('{"tagline": "before"}');

      expect(store.apply('<html>nope</html>'), isNull);
      expect(store.config.tagline, equals('before'));
    });

    test('writes through, so a restart keeps it', () {
      final at = pathIn('config.json');
      ConfigStore(path: at).apply('{"worldName": "DashConf"}');

      expect(ConfigStore(path: at).config.worldName, equals('DashConf'));
    });

    test('the file it writes is the document it serves', () {
      final at = pathIn('config.json');
      final store = ConfigStore(path: at)..apply('{"botCounts": {"beach": 3}}');

      expect(File(at).readAsStringSync(), equals(store.document));
      expect(parseAppConfig(File(at).readAsStringSync()), equals(store.config));
    });
  });

  group('the in-memory store', () {
    test('keeps nothing and touches no disk', () {
      final store = ConfigStore.inMemory()..apply('{"worldName": "DashConf"}');

      expect(store.path, isNull);
      expect(store.config.worldName, equals('DashConf'));
    });

    test(
      'can be seeded, which is how the tests get a world with copy in it',
      () {
        final store = ConfigStore.inMemory(
          config: const AppConfig(worldName: 'DashConf'),
        );

        expect(store.message.config.worldName, equals('DashConf'));
      },
    );
  });

  group('the maintenance window', () {
    final until = DateTime.utc(2026, 8, 22, 18, 30);

    test('survives a restart', () {
      // The whole reason a window is persisted: the restart is usually the
      // thing the window exists for.
      final at = pathIn('config.json');
      ConfigStore(path: at).setMaintenanceUntil(until);

      expect(ConfigStore(path: at).config.maintenanceUntil, equals(until));
    });

    test('leaves the rest of the document alone', () {
      final store = ConfigStore(path: pathIn('config.json'))
        ..apply('{"worldName": "DashConf", "botCounts": {"beach": 3}}')
        ..setMaintenanceUntil(until);

      expect(store.config.worldName, equals('DashConf'));
      expect(store.config.botCountFor(MapId.beach), equals(3));
    });

    test('is cleared by a null, and that survives a restart too', () {
      final at = pathIn('config.json');
      ConfigStore(path: at)
        ..setMaintenanceUntil(until)
        ..setMaintenanceUntil(null);

      expect(ConfigStore(path: at).config.maintenanceUntil, isNull);
    });

    test('a document push can set one as well', () {
      // Same field, same file. The editor is not a second-class route to it.
      final store = ConfigStore.inMemory()
        ..apply('{"maintenanceUntil":"${until.toIso8601String()}"}');

      expect(store.config.maintenanceUntil, equals(until));
    });
  });
}
