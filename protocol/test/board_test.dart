import 'dart:convert';

import 'package:protocol/protocol.dart';
import 'package:protocol/src/json_reader.dart';
import 'package:test/test.dart';

/// The JSON a v3 peer writes for a player: no `hasBoard` field at all.
Map<String, Object?> v3Player({Object? hasBoard = _absent}) => {
  'id': 'p1',
  'name': 'Alice',
  'color': 0xFF54C5F8,
  'cosmetic': 'cap',
  'x': 100.5,
  'y': 200.25,
  if (!identical(hasBoard, _absent)) 'hasBoard': hasBoard,
};

const Object _absent = Object();

void main() {
  group('readOptionalBool', () {
    test('reads a real bool', () {
      expect(readOptionalBool(const {'flag': true}, 'flag'), isTrue);
      expect(readOptionalBool(const {'flag': false}, 'flag'), isFalse);
    });

    test('a missing key reads as the default and does not throw', () {
      expect(readOptionalBool(const {}, 'flag'), isFalse);
      expect(readOptionalBool(const {}, 'flag', orElse: true), isTrue);
    });

    test('a value of the wrong type reads as the default', () {
      // The whole point of the lenient reader: none of these may throw, and
      // none of them may be read as "true" by accident.
      for (final wrong in <Object?>[
        'true',
        1,
        0,
        null,
        <String>[],
        <int, int>{},
      ]) {
        expect(
          readOptionalBool({'flag': wrong}, 'flag'),
          isFalse,
          reason: 'a $wrong should read as the default',
        );
      }
    });

    test('readBool is still strict, so a typo cannot set a flag', () {
      expect(
        () => readBool(const {'flag': 'true'}, 'flag'),
        throwsFormatException,
      );
      expect(() => readBool(const {}, 'flag'), throwsFormatException);
    });
  });

  group('PlayerState.hasBoard', () {
    test('defaults to false when the constructor omits it', () {
      const player = PlayerState(
        id: 'p1',
        name: 'Alice',
        color: 0,
        cosmetic: PlayerCosmetic.none,
        x: 0,
        y: 0,
      );

      expect(player.hasBoard, isFalse);
    });

    test('a v3 player with no hasBoard field reads as false', () {
      expect(PlayerState.fromJson(v3Player()).hasBoard, isFalse);
    });

    test('hasBoard: "true" reads as false rather than throwing', () {
      // A string is not a bool. Reading it as true would let a peer that
      // stringifies its JSON hand everybody a board.
      expect(
        PlayerState.fromJson(v3Player(hasBoard: 'true')).hasBoard,
        isFalse,
      );
      expect(PlayerState.fromJson(v3Player(hasBoard: 1)).hasBoard, isFalse);
      expect(PlayerState.fromJson(v3Player(hasBoard: null)).hasBoard, isFalse);
    });

    test('a real flag survives a round trip', () {
      const player = PlayerState(
        id: 'p1',
        name: 'Alice',
        color: 0,
        cosmetic: PlayerCosmetic.none,
        x: 1,
        y: 2,
        hasBoard: true,
      );

      expect(PlayerState.fromJson(player.toJson()), equals(player));
      expect(PlayerState.fromJson(player.toJson()).hasBoard, isTrue);
    });

    test('movedTo preserves the flag', () {
      const player = PlayerState(
        id: 'p1',
        name: 'Alice',
        color: 0,
        cosmetic: PlayerCosmetic.none,
        x: 1,
        y: 2,
        hasBoard: true,
      );

      expect(player.movedTo(9, 9).hasBoard, isTrue);
      expect(player.movedTo(9, 9).x, equals(9));
    });

    test('two players differing only in the board are not equal', () {
      const dry = PlayerState(
        id: 'p1',
        name: 'Alice',
        color: 0,
        cosmetic: PlayerCosmetic.none,
        x: 1,
        y: 2,
      );

      const wet = PlayerState(
        id: 'p1',
        name: 'Alice',
        color: 0,
        cosmetic: PlayerCosmetic.none,
        x: 1,
        y: 2,
        hasBoard: true,
      );

      expect(wet, isNot(equals(dry)));
      expect(wet.hashCode, isNot(equals(dry.hashCode)));
      // And the same two states are still equal when nothing differs.
      expect(dry.movedTo(1, 2), equals(dry));
    });
  });

  group('the two board messages', () {
    test('a board carries the flag and no id at all', () {
      final json = const BoardMessage(hasBoard: true).toJson();

      expect(json['hasBoard'], isTrue);
      expect(json.containsKey('id'), isFalse);
    });

    test('a board with an unreadable flag decodes as no board', () {
      final decoded = decodeMessage(
        jsonEncode({'type': 'board', 'version': protocolVersion}),
      );

      expect(decoded, equals(const BoardMessage(hasBoard: false)));
    });

    test('a playerBoard needs its id', () {
      final decoded = decodeMessage(
        jsonEncode({'type': 'playerBoard', 'hasBoard': true}),
      );

      expect(decoded, isA<UnknownMessage>());
    });

    test('a playerBoard round-trips through the codec', () {
      const message = PlayerBoardMessage(id: 'p7', hasBoard: true);

      expect(decodeMessage(encodeMessage(message)), equals(message));
    });
  });

  group('version 4', () {
    test('the protocol is at least v4 — the board shipped in it', () {
      // Phase 13 moved the version on to 5. What this group is actually
      // about is the *board* wire shape, which v4 introduced and v5 did not
      // touch, so the assertion is "v4 or later" rather than a second copy
      // of the exact-version pin. That pin lives in
      // `protocol_version_test.dart`, which is the one place it belongs.
      expect(protocolVersion, greaterThanOrEqualTo(4));
      expect(helloProtocol(), contains('v$protocolVersion'));
    });

    test('a type this build has never heard of is still an unknown', () {
      final decoded = decodeMessage(
        jsonEncode({'type': 'surfTrick', 'version': 9}),
      );

      expect(decoded, isA<UnknownMessage>());
      expect((decoded as UnknownMessage).rawType, equals('surfTrick'));
    });

    test('a v3 snapshot decodes, with nobody carrying a board', () {
      final decoded = decodeMessage(
        jsonEncode({
          'type': 'snapshot',
          'version': 3,
          'appeared': [v3Player()],
        }),
      );

      expect(decoded, isA<SnapshotMessage>());
      expect((decoded as SnapshotMessage).appeared.single.hasBoard, isFalse);
    });
  });
}
