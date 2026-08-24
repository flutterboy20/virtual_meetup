import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  // Everything in this file is the "one bad client must not take the world
  // down" rule: decoding never throws, it degrades to an unknown.
  UnknownMessage decodeBad(String raw) {
    final message = decodeMessage(raw);
    expect(
      message,
      isA<UnknownMessage>(),
      reason: 'decoding "$raw" should fail soft',
    );
    return message as UnknownMessage;
  }

  group('malformed input fails soft', () {
    test('empty text', () {
      expect(decodeBad('').reason, contains('not JSON'));
    });

    test('text that is not JSON at all', () {
      expect(decodeBad('<html>nope</html>').reason, contains('not JSON'));
    });

    test('truncated JSON', () {
      expect(decodeBad('{"type":"move","x":1').reason, contains('not JSON'));
    });

    test('valid JSON that is not an object', () {
      expect(decodeBad('[1,2,3]').reason, contains('top level'));
      expect(decodeBad('"move"').reason, contains('top level'));
      expect(decodeBad('null').reason, contains('top level'));
    });
  });

  group('unknown types fail soft', () {
    test('a type this build has never heard of', () {
      final message = decodeBad('{"type":"confetti","version":9,"n":3}');

      expect(message.rawType, equals('confetti'));
      expect(message.reason, equals('unknown message type'));
    });

    test('a missing type', () {
      final message = decodeBad('{"version":1,"x":1,"y":2}');

      expect(message.rawType, isNull);
    });

    test('a type that is not a string', () {
      expect(decodeBad('{"type":7}').rawType, isNull);
    });
  });

  group('bad fields fail soft', () {
    test('a missing field', () {
      expect(decodeBad('{"type":"move","x":1}').rawType, equals('move'));
    });

    test('a null field', () {
      expect(decodeBad('{"type":"move","x":1,"y":null}').reason, contains('y'));
    });

    test('a field of the wrong type', () {
      expect(
        decodeBad('{"type":"move","x":"far","y":2}').reason,
        contains('x'),
      );
      expect(decodeBad('{"type":"playerLeft","id":9}').reason, contains('id'));
    });

    test('a NaN position', () {
      // JSON has no NaN literal, so a hostile client has to smuggle it as a
      // string; either way it must never reach the position maths.
      expect(
        decodeBad('{"type":"move","x":"NaN","y":2}').reason,
        contains('x'),
      );
    });

    test('a snapshot whose positions field is not a list', () {
      expect(
        decodeBad('{"type":"snapshot","positions":{}}').reason,
        contains('positions'),
      );
    });

    test('a snapshot with a broken entry in an otherwise fine list', () {
      expect(
        decodeBad('{"type":"snapshot","appeared":[{"id":"p2"}]}').reason,
        contains('name'),
      );
    });

    test('a snapshot whose outOfRange list holds something else', () {
      expect(
        decodeBad('{"type":"snapshot","outOfRange":[7]}').reason,
        contains('outOfRange'),
      );
    });
  });

  group('tolerated input', () {
    test('an int is accepted where a double is expected', () {
      expect(
        decodeMessage('{"type":"move","version":1,"x":10,"y":20}'),
        equals(const MoveMessage(x: 10, y: 20)),
      );
    });

    test('a missing version is not fatal', () {
      // Versioning is informational for now: refusing a message on it would
      // turn a rolling deploy into an outage.
      expect(
        decodeMessage('{"type":"playerLeft","id":"p1"}'),
        equals(const PlayerLeftMessage(id: 'p1')),
      );
    });

    test('an unexpected extra field is ignored', () {
      expect(
        decodeMessage('{"type":"move","version":1,"x":1,"y":2,"z":3}'),
        equals(const MoveMessage(x: 1, y: 2)),
      );
    });

    test('a future protocol version still decodes', () {
      expect(
        decodeMessage('{"type":"move","version":99,"x":1,"y":2}'),
        equals(const MoveMessage(x: 1, y: 2)),
      );
    });
  });

  group('MessageType', () {
    test('maps its own wire names back', () {
      for (final type in MessageType.values) {
        expect(MessageType.fromWireName(type.wireName), equals(type));
      }
    });

    test('maps anything else to unknown', () {
      expect(
        MessageType.fromWireName('confetti'),
        equals(MessageType.unknown),
      );
      expect(MessageType.fromWireName(null), equals(MessageType.unknown));
    });
  });

  group('world bounds', () {
    test('clamps a position inside the playable area', () {
      expect(clampWorldX(-500), equals(worldEdgeInset));
      expect(clampWorldX(99999), equals(worldWidth - worldEdgeInset));
      expect(clampWorldY(-500), equals(worldEdgeInset));
      expect(clampWorldY(99999), equals(worldHeight - worldEdgeInset));
    });

    test('leaves a position already inside alone', () {
      expect(clampWorldX(800), equals(800));
      expect(clampWorldY(600), equals(600));
    });
  });
}
