import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectionGate hard cap', () {
    test('admits up to the cap and refuses past it', () {
      final gate = ConnectionGate(maxSockets: 3);

      expect(gate.tryAdmit(), isTrue);
      expect(gate.tryAdmit(), isTrue);
      expect(gate.tryAdmit(), isTrue);
      expect(gate.tryAdmit(), isFalse);
      expect(gate.openSockets, equals(3));
    });

    test('a refused admission does not consume a slot', () {
      final gate = ConnectionGate(maxSockets: 1)..tryAdmit();

      expect(gate.tryAdmit(), isFalse);
      expect(gate.tryAdmit(), isFalse);
      expect(gate.openSockets, equals(1));
    });

    test('release frees a slot for the next socket', () {
      final gate = ConnectionGate(maxSockets: 2)
        ..tryAdmit()
        ..tryAdmit();
      expect(gate.tryAdmit(), isFalse);

      gate.release();

      expect(gate.openSockets, equals(1));
      expect(gate.tryAdmit(), isTrue);
    });

    test('releasing below zero is a no-op, not a negative count', () {
      // A counter that can go negative silently hands out free slots for the
      // rest of the process after one stray double-release.
      final gate = ConnectionGate(maxSockets: 2)
        ..release()
        ..release();

      expect(gate.openSockets, equals(0));
      expect(gate.tryAdmit(), isTrue);
      expect(gate.tryAdmit(), isTrue);
      expect(gate.tryAdmit(), isFalse);
    });

    test('starts empty', () {
      expect(ConnectionGate().openSockets, equals(0));
    });

    test('defaults sit well above the crowd the event expects', () {
      final gate = ConnectionGate();

      expect(gate.maxSockets, equals(800));
      expect(gate.maxPlayers, equals(400));
      expect(gate.isAtPlayerCap(300), isFalse);
    });

    test('refuses a cap of zero on either ceiling', () {
      expect(() => ConnectionGate(maxSockets: 0), throwsArgumentError);
      expect(() => ConnectionGate(maxPlayers: 0), throwsArgumentError);
    });
  });

  group('ConnectionGate soft cap', () {
    test('reads against the count it is given', () {
      final gate = ConnectionGate(maxPlayers: 2);

      expect(gate.isAtPlayerCap(0), isFalse);
      expect(gate.isAtPlayerCap(1), isFalse);
      expect(gate.isAtPlayerCap(2), isTrue);
      expect(gate.isAtPlayerCap(9), isTrue);
    });

    test('is independent of the socket counter', () {
      // The whole point of two ceilings: a flood of sockets that never join
      // moves `openSockets` and leaves the player count at zero.
      final gate = ConnectionGate(maxSockets: 10, maxPlayers: 2);
      for (var i = 0; i < 10; i++) {
        gate.tryAdmit();
      }

      expect(gate.openSockets, equals(10));
      expect(gate.isAtPlayerCap(0), isFalse);
    });
  });

  group('resolveMaxSockets', () {
    test('falls back to the default when unset', () {
      expect(
        resolveMaxSockets(const {}),
        equals(ConnectionGate.defaultMaxSockets),
      );
    });

    test('falls back to the default when blank', () {
      expect(
        resolveMaxSockets(const {maxSocketsEnvVar: '  '}),
        equals(ConnectionGate.defaultMaxSockets),
      );
    });

    test('reads a valid value, whitespace and all', () {
      expect(resolveMaxSockets(const {maxSocketsEnvVar: ' 120 '}), equals(120));
    });

    test('throws on a value that is not a whole number', () {
      expect(
        () => resolveMaxSockets(const {maxSocketsEnvVar: 'lots'}),
        throwsFormatException,
      );
      expect(
        () => resolveMaxSockets(const {maxSocketsEnvVar: '12.5'}),
        throwsFormatException,
      );
    });

    test('throws on zero and on a negative', () {
      expect(
        () => resolveMaxSockets(const {maxSocketsEnvVar: '0'}),
        throwsFormatException,
      );
      expect(
        () => resolveMaxSockets(const {maxSocketsEnvVar: '-1'}),
        throwsFormatException,
      );
    });
  });

  group('resolveMaxPlayers', () {
    test('falls back to the default when unset', () {
      expect(
        resolveMaxPlayers(const {}),
        equals(ConnectionGate.defaultMaxPlayers),
      );
    });

    test('falls back to the default when blank', () {
      expect(
        resolveMaxPlayers(const {maxPlayersEnvVar: ''}),
        equals(ConnectionGate.defaultMaxPlayers),
      );
    });

    test('reads a valid value', () {
      expect(resolveMaxPlayers(const {maxPlayersEnvVar: '250'}), equals(250));
    });

    test('throws on a bad value', () {
      expect(
        () => resolveMaxPlayers(const {maxPlayersEnvVar: 'four hundred'}),
        throwsFormatException,
      );
      expect(
        () => resolveMaxPlayers(const {maxPlayersEnvVar: '0'}),
        throwsFormatException,
      );
    });
  });
}
