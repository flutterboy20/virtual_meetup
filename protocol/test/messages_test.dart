import 'dart:convert';

import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  const alice = PlayerState(
    id: 'p1',
    name: 'Alice',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
    x: 100.5,
    y: 200.25,
  );
  const bob = PlayerState(
    id: 'p2',
    name: 'Bob',
    color: 0xFF7ED9B6,
    cosmetic: PlayerCosmetic.headphones,
    x: 0,
    y: 0,
  );

  // Every message the protocol can carry. New types get added here, which is
  // what makes the round-trip test cover the whole protocol and not just the
  // messages somebody remembered to list.
  final everyMessage = <ProtocolMessage>[
    const JoinMessage(
      sessionId: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
      name: 'Alice',
      color: 0xFF54C5F8,
      cosmetic: PlayerCosmetic.cap,
    ),
    const JoinMessage(
      sessionId: '',
      name: '',
      color: 0,
      cosmetic: PlayerCosmetic.none,
    ),
    const MoveMessage(x: 12.5, y: -3.25),
    const WelcomeMessage(yourId: 'p3'),
    const SnapshotMessage(
      appeared: [alice, bob],
      positions: [
        PlayerPosition(id: 'p1', x: 100.5, y: 200.25),
        PlayerPosition(id: 'p2', x: 0, y: 0),
      ],
      outOfRange: ['p9'],
    ),
    const SnapshotMessage(
      positions: [PlayerPosition(id: 'p1', x: 4, y: 5.5)],
    ),
    const SnapshotMessage(outOfRange: ['p1']),
    const PlayerLeftMessage(id: 'p1'),
    const JoinRejectedMessage(
      reason: JoinRejection.invalidName,
      detail: 'Please pick a different name.',
    ),
    const JoinRejectedMessage(
      reason: JoinRejection.invalidSession,
      detail: 'Bad session.',
    ),
    const EmoteMessage(emote: EmoteKind.wave),
    const EmoteMessage(emote: EmoteKind.party),
    const PlayerEmotedMessage(id: 'p1', emote: EmoteKind.heart),
    const BoardMessage(hasBoard: true),
    const BoardMessage(hasBoard: false),
    const PlayerBoardMessage(id: 'p1', hasBoard: true),
    const PlayerBoardMessage(id: 'p2', hasBoard: false),
    const WorldStatsMessage(online: 0),
    const WorldStatsMessage(online: 217),
    const UnknownMessage(reason: 'unknown message type', rawType: 'confetti'),
    const UnknownMessage(reason: 'not JSON: bad'),
    // Admin. In the same list on purpose: "covers every message type" below
    // is what stops a privileged message being added without a round-trip
    // test, which is the last place a silent encoding bug should be able to
    // hide.
    const AdminAuthMessage(token: 'not-a-real-token'),
    const AdminAuthResultMessage(authorized: true, detail: 'Welcome.'),
    const AdminAuthResultMessage(authorized: false, detail: 'Wrong token.'),
    const AdminPlayerListMessage(
      players: [
        AdminPlayerSummary(
          id: 'p1',
          name: 'Alice',
          isNameMuted: false,
          x: 100.5,
          y: 200.25,
        ),
        AdminPlayerSummary(
          id: 'p2',
          name: 'Bob',
          isNameMuted: true,
          x: 0,
          y: 0,
        ),
      ],
      online: 2,
    ),
    const AdminPlayerListMessage(players: [], online: 0),
    const AdminKickMessage(playerId: 'p1'),
    const AdminBanMessage(playerId: 'p1'),
    const AdminMuteNameMessage(playerId: 'p1', muted: true),
    const AdminMuteNameMessage(playerId: 'p1', muted: false),
    const AdminActionResultMessage(
      action: AdminAction.kick,
      targetId: 'p1',
      targetName: 'Alice',
    ),
    const AdminActionResultMessage(
      action: AdminAction.unmuteName,
      targetId: 'p2',
      targetName: 'Bob',
    ),
    const AdminErrorMessage(
      reason: AdminError.unauthorized,
      detail: 'Not authorised.',
    ),
    const AdminErrorMessage(
      reason: AdminError.unknownPlayer,
      detail: 'They have already left.',
    ),
    const ConfigMessage(config: AppConfig.defaults),
    const ConfigMessage(
      config: AppConfig(
        worldName: 'DashConf',
        eyebrow: 'DAY TWO',
        tagline: 'same beans',
        boardMessage: 'the wifi is fine',
        stageLines: ['one', 'two'],
        botCounts: {MapId.conference: 9, MapId.beach: 0},
      ),
    ),
    ConfigMessage(
      config: AppConfig(maintenanceUntil: DateTime.utc(2026, 8, 22, 18, 30)),
    ),
    const AdminSetConfigMessage(document: '{"tagline": "walk around"}'),
    // The document is passed through untouched, whatever it is. The server
    // is the thing that judges it, so a push that could not survive the wire
    // would rob the moderator of the error message they were owed.
    const AdminSetConfigMessage(document: 'not json at all'),
    const AdminSetMaintenanceMessage(token: 'a-long-enough-test-token'),
    AdminSetMaintenanceMessage(
      token: 'a-long-enough-test-token',
      until: DateTime.utc(2026, 8, 22, 18, 30),
    ),
  ];

  group('round trip', () {
    for (final message in everyMessage) {
      test('$message survives encode then decode', () {
        expect(decodeMessage(encodeMessage(message)), equals(message));
      });
    }

    test('covers every message type', () {
      expect(
        everyMessage.map((message) => message.type).toSet(),
        equals(MessageType.values.toSet()),
      );
    });
  });

  group('envelope', () {
    test('every message carries its type and the protocol version', () {
      for (final message in everyMessage) {
        final json = message.toJson();
        expect(json['type'], equals(message.type.wireName));
        expect(json['version'], equals(protocolVersion));
      }
    });

    test('readMessageVersion reads the version back', () {
      final json = jsonDecode(
        encodeMessage(const PlayerLeftMessage(id: 'p1')),
      ) as Map<String, Object?>;

      expect(readMessageVersion(json), equals(protocolVersion));
    });

    test('readMessageVersion is null when the field is missing', () {
      expect(readMessageVersion(const {'type': 'move'}), isNull);
    });
  });

  group('wire shape', () {
    test('a snapshot position carries only an id and two numbers', () {
      expect(
        const PlayerPosition(id: 'p1', x: 1, y: 2).toJson().keys,
        equals(['id', 'x', 'y']),
      );
    });

    test('a whole-numbered position is written as an int, not a double', () {
      // Measured at 200 players this halved the outbound bandwidth: a full
      // precision double is 19 characters where an int is three, repeated
      // per neighbour per tick per client.
      final json = const PlayerPosition(id: 'p1', x: 842, y: 992).toJson();

      expect(json['x'], isA<int>());
      expect(jsonEncode(json), equals('{"id":"p1","x":842,"y":992}'));
    });

    test('a fractional position keeps its precision', () {
      final json = const PlayerPosition(id: 'p1', x: 1.5, y: 2).toJson();

      expect(json['x'], equals(1.5));
    });

    test('an appeared player carries everything needed to draw them', () {
      final snapshot = const SnapshotMessage(appeared: [alice]).toJson();

      expect((snapshot['appeared']! as List).single, equals(alice.toJson()));
    });

    test('a snapshot with nothing in it knows that it is empty', () {
      expect(const SnapshotMessage().isEmpty, isTrue);
      expect(
        const SnapshotMessage(outOfRange: ['p1']).isEmpty,
        isFalse,
      );
    });

    test('a snapshot decodes when its empty lists are omitted', () {
      final decoded = decodeMessage(
        jsonEncode({'type': 'snapshot', 'version': protocolVersion}),
      );

      expect(decoded, equals(const SnapshotMessage()));
    });

    test('join carries the session id', () {
      expect(
        const JoinMessage(
          sessionId: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
          name: 'Ada',
          color: 1,
          cosmetic: PlayerCosmetic.none,
        ).toJson()['sessionId'],
        equals('a1b2c3d4e5f60718293a4b5c6d7e8f90'),
      );
    });

    test('a join with no session id decodes to an empty one', () {
      // A v2 client. The server answers it with a typed rejection rather
      // than letting the message become an unreadable unknown.
      final decoded = decodeMessage(
        jsonEncode({
          'type': 'join',
          'version': 2,
          'name': 'Ada',
          'color': 1,
          'cosmetic': 'none',
        }),
      );

      expect(decoded, isA<JoinMessage>());
      expect((decoded as JoinMessage).sessionId, isEmpty);
    });

    test('move carries only a position', () {
      expect(
        const MoveMessage(x: 1, y: 2).toJson().keys,
        equals(['type', 'version', 'x', 'y']),
      );
    });
  });

  group('JoinRejection', () {
    test('round-trips through its wire name', () {
      for (final value in JoinRejection.values) {
        expect(JoinRejection.fromWireName(value.wireName), equals(value));
      }
    });

    test('an unrecognised reason falls back to the fixable one', () {
      // A dead end is a worse failure than sending somebody back to the
      // setup screen for a reason this build cannot name.
      expect(
        JoinRejection.fromWireName('somethingNew'),
        equals(JoinRejection.invalidName),
      );
    });
  });

  group('session ids', () {
    test('accepts a well-formed id', () {
      expect(isValidSessionId('a1b2c3d4e5f60718293a4b5c6d7e8f90'), isTrue);
    });

    test('rejects the wrong length', () {
      expect(isValidSessionId(''), isFalse);
      expect(isValidSessionId('a1b2c3'), isFalse);
      expect(isValidSessionId('a' * (sessionIdLength + 1)), isFalse);
    });

    test('rejects anything that is not lowercase hex', () {
      expect(isValidSessionId('A1B2C3D4E5F60718293A4B5C6D7E8F90'), isFalse);
      expect(isValidSessionId('g1b2c3d4e5f60718293a4b5c6d7e8f90'), isFalse);
      expect(isValidSessionId('../etc/passwd-aaaaaaaaaaaaaaaaaa'), isFalse);
    });
  });

  group('PlayerPosition', () {
    test('round-trips through JSON', () {
      const position = PlayerPosition(id: 'p1', x: 1.5, y: -2.25);

      expect(PlayerPosition.fromJson(position.toJson()), equals(position));
    });

    test('a position with a non-finite coordinate is rejected', () {
      expect(
        () => PlayerPosition.fromJson(const {
          'id': 'p1',
          'x': double.nan,
          'y': 0,
        }),
        throwsFormatException,
      );
    });
  });

  group('PlayerState', () {
    test('round-trips through JSON', () {
      expect(PlayerState.fromJson(alice.toJson()), equals(alice));
    });

    test('movedTo changes only the position', () {
      final moved = alice.movedTo(1, 2);

      expect(moved.x, equals(1));
      expect(moved.y, equals(2));
      expect(moved.id, equals(alice.id));
      expect(moved.name, equals(alice.name));
      expect(moved.color, equals(alice.color));
      expect(moved.cosmetic, equals(alice.cosmetic));
    });

    test('an unrecognised cosmetic decodes to a bare head', () {
      final json = alice.toJson()..['cosmetic'] = 'jetpack';

      expect(PlayerState.fromJson(json).cosmetic, equals(PlayerCosmetic.none));
    });
  });
}
