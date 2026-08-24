import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  group('resolvePort', () {
    test('falls back to the default when PORT is absent', () {
      expect(resolvePort(const {}), equals(defaultPort));
    });

    test('falls back to the default when PORT is blank', () {
      expect(resolvePort(const {portEnvVar: '   '}), equals(defaultPort));
    });

    test('reads a valid PORT', () {
      expect(resolvePort(const {portEnvVar: '9000'}), equals(9000));
    });

    test('tolerates surrounding whitespace', () {
      expect(resolvePort(const {portEnvVar: ' 9000 '}), equals(9000));
    });

    test('throws on a non-numeric PORT', () {
      expect(
        () => resolvePort(const {portEnvVar: 'eighty'}),
        throwsFormatException,
      );
    });

    test('throws on an out-of-range PORT', () {
      expect(
        () => resolvePort(const {portEnvVar: '70000'}),
        throwsFormatException,
      );
      expect(
        () => resolvePort(const {portEnvVar: '0'}),
        throwsFormatException,
      );
    });
  });

  group('resolveCellSize', () {
    test('falls back to the default when CELL_SIZE is absent', () {
      expect(
        resolveCellSize(const {}),
        equals(SpatialGrid.defaultCellSize),
      );
    });

    test('falls back to the default when CELL_SIZE is blank', () {
      expect(
        resolveCellSize(const {cellSizeEnvVar: '  '}),
        equals(SpatialGrid.defaultCellSize),
      );
    });

    test('reads a valid CELL_SIZE', () {
      expect(resolveCellSize(const {cellSizeEnvVar: ' 250.5 '}), equals(250.5));
    });

    test('throws on a cell size that is not a positive number', () {
      for (final bad in ['0', '-1', 'wide', 'NaN']) {
        expect(
          () => resolveCellSize({cellSizeEnvVar: bad}),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  group('resolveNeighbourCap', () {
    test('falls back to the built-in cap', () {
      expect(resolveNeighbourCap(const {}), equals(Relay.defaultNeighbourCap));
      expect(
        resolveNeighbourCap(const {neighbourCapEnvVar: '  '}),
        equals(Relay.defaultNeighbourCap),
      );
    });

    test('reads a cap from the environment', () {
      expect(resolveNeighbourCap(const {neighbourCapEnvVar: '12'}), equals(12));
    });

    test('refuses a cap that would empty the world', () {
      // A cap of nothing leaves every client alone in a room full of people,
      // which looks exactly like a broken server.
      expect(
        () => resolveNeighbourCap(const {neighbourCapEnvVar: '0'}),
        throwsFormatException,
      );
      expect(
        () => resolveNeighbourCap(const {neighbourCapEnvVar: '-3'}),
        throwsFormatException,
      );
      expect(
        () => resolveNeighbourCap(const {neighbourCapEnvVar: 'lots'}),
        throwsFormatException,
      );
    });
  });

  group('resolveKickCooldown', () {
    test('falls back to the built-in cooldown', () {
      expect(resolveKickCooldown(const {}), equals(defaultKickCooldown));
      expect(
        resolveKickCooldown(const {kickCooldownEnvVar: '  '}),
        equals(defaultKickCooldown),
      );
    });

    test('reads a cooldown from the environment', () {
      expect(
        resolveKickCooldown(const {kickCooldownEnvVar: '5'}),
        equals(const Duration(seconds: 5)),
      );
    });

    test('zero is a configuration, not a mistake', () {
      expect(
        resolveKickCooldown(const {kickCooldownEnvVar: '0'}),
        equals(Duration.zero),
      );
    });

    test('refuses a cooldown that is not whole seconds', () {
      expect(
        () => resolveKickCooldown(const {kickCooldownEnvVar: '-1'}),
        throwsFormatException,
      );
      expect(
        () => resolveKickCooldown(const {kickCooldownEnvVar: 'half a minute'}),
        throwsFormatException,
      );
    });
  });

  group('resolveAdminToken', () {
    test('no variable means moderation is switched off', () {
      // Off, never open. A deployment that forgot the variable gets no
      // moderation, which is a bad day; the other default gets
      // unauthenticated moderation, which is a much worse one.
      expect(resolveAdminToken(const {}), isNull);
      expect(resolveAdminToken(const {adminTokenEnvVar: '   '}), isNull);
    });

    test('reads and trims a token from the environment', () {
      expect(
        resolveAdminToken(const {adminTokenEnvVar: '  0123456789abcdef  '}),
        equals('0123456789abcdef'),
      );
    });

    test('refuses a token short enough to guess', () {
      // The thing it guards is the ability to disconnect every attendee.
      expect(
        () => resolveAdminToken(const {adminTokenEnvVar: 'admin'}),
        throwsFormatException,
      );
    });

    test('the failure never quotes the token back', () {
      // An exception message ends up in a startup log.
      try {
        resolveAdminToken(const {adminTokenEnvVar: 'shortsecret'});
        fail('expected a FormatException');
      } on FormatException catch (error) {
        expect(error.message, isNot(contains('shortsecret')));
      }
    });
  });

  group('resolveBanFilePath', () {
    test('falls back to the default path', () {
      expect(resolveBanFilePath(const {}), equals(defaultBanFilePath));
      expect(
        resolveBanFilePath(const {banFileEnvVar: ' '}),
        equals(defaultBanFilePath),
      );
    });

    test('reads a path from the environment', () {
      expect(
        resolveBanFilePath(const {banFileEnvVar: '/data/bans.json'}),
        equals('/data/bans.json'),
      );
    });
  });

  group('resolveAuditFilePath', () {
    test('falls back to the default path', () {
      expect(resolveAuditFilePath(const {}), equals(defaultAuditFilePath));
    });

    test('reads a path from the environment', () {
      expect(
        resolveAuditFilePath(const {auditFileEnvVar: '/data/audit.log'}),
        equals('/data/audit.log'),
      );
    });
  });

  group('resolveTickInterval', () {
    test('falls back to the relay default when unset or blank', () {
      expect(resolveTickInterval({}), equals(Relay.defaultTickInterval));
      expect(
        resolveTickInterval({tickHzEnvVar: '  '}),
        equals(Relay.defaultTickInterval),
      );
    });

    test('converts Hz to the timer interval the relay wants', () {
      expect(
        resolveTickInterval({tickHzEnvVar: '10'}),
        equals(const Duration(milliseconds: 100)),
      );
      expect(
        resolveTickInterval({tickHzEnvVar: '30'}),
        equals(const Duration(milliseconds: 33)),
      );
    });

    test('rejects a rate that is not a tuning decision', () {
      // Zero would stop the world; a negative one is a typo; anything past
      // the cap costs bandwidth for smoothness the client cannot show.
      for (final bad in ['0', '-5', '600', 'fast', '']) {
        expect(
          () => resolveTickInterval({tickHzEnvVar: bad}),
          bad.isEmpty ? returnsNormally : throwsA(isA<FormatException>()),
          reason: bad,
        );
      }
    });
  });

  group('resolveMetricsCsvPath', () {
    test('is off unless a path is named', () {
      expect(resolveMetricsCsvPath({}), isNull);
      expect(resolveMetricsCsvPath({metricsCsvEnvVar: '   '}), isNull);
    });

    test('takes the path it is given, trimmed', () {
      expect(
        resolveMetricsCsvPath({metricsCsvEnvVar: ' runs/soak.csv '}),
        equals('runs/soak.csv'),
      );
    });
  });
}
