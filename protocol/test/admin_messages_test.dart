import 'dart:convert';

import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AdminPlayerSummary', () {
    const alice = AdminPlayerSummary(
      id: 'p1',
      name: 'Alice',
      isNameMuted: false,
      x: 10,
      y: 20,
    );

    test('never carries a session id', () {
      // The session id is a bearer token: anybody holding one can walk into
      // that player's bean. An admin is trusted to moderate, which is not
      // the same as being handed everybody's credentials, so it does not
      // leave the server at all.
      expect(
        alice.toJson().keys,
        equals(['id', 'name', 'isNameMuted', 'x', 'y', 'map']),
      );
      // Pinned as a whole list above so that *adding* a field is a decision
      // somebody has to make on purpose — `map` arrived in Phase 10 and had
      // to come through here. This second check is the rule itself, and it
      // holds however the list grows.
      expect(
        alice.toJson().keys.any(
          (key) => key.toLowerCase().contains('session'),
        ),
        isFalse,
      );
    });

    test('reports the chosen name and the displayed name separately', () {
      const muted = AdminPlayerSummary(
        id: 'p2',
        name: 'Something Rude',
        isNameMuted: true,
        x: 0,
        y: 0,
      );

      // The admin sees what they muted; everybody else sees the placeholder.
      expect(muted.name, equals('Something Rude'));
      expect(muted.displayName, equals(mutedDisplayName));
      expect(alice.displayName, equals('Alice'));
    });

    test('survives a JSON round trip', () {
      expect(AdminPlayerSummary.fromJson(alice.toJson()), equals(alice));
    });

    test('a non-boolean mute flag is not read as truthy', () {
      // A moderation flag set by a typo is exactly the bug a truthiness rule
      // would introduce.
      expect(
        () => AdminPlayerSummary.fromJson(const {
          'id': 'p1',
          'name': 'Alice',
          'isNameMuted': 'true',
          'x': 0,
          'y': 0,
        }),
        throwsFormatException,
      );
    });
  });

  group('AdminAuthMessage', () {
    test('does not print its token', () {
      // toString lands in logs and in test failure output.
      expect(
        const AdminAuthMessage(token: 'hunter2').toString(),
        isNot(contains('hunter2')),
      );
    });

    test('carries the token on the wire and nothing else', () {
      expect(
        const AdminAuthMessage(token: 'hunter2').toJson().keys,
        equals(['type', 'version', 'token']),
      );
    });
  });

  group('wire tags', () {
    test('every admin message is namespaced admin.*', () {
      const adminTypes = {
        MessageType.adminAuth,
        MessageType.adminAuthResult,
        MessageType.adminPlayerList,
        MessageType.adminKick,
        MessageType.adminBan,
        MessageType.adminMuteName,
        MessageType.adminSetConfig,
        MessageType.adminSetMaintenance,
        MessageType.adminActionResult,
        MessageType.adminError,
      };

      for (final type in adminTypes) {
        expect(type.wireName, startsWith('admin.'));
      }
      // ...and nothing else is, so "is this privileged" is answerable by
      // looking at a log line.
      for (final type in MessageType.values.toSet().difference(adminTypes)) {
        expect(type.wireName, isNot(startsWith('admin.')));
      }
    });
  });

  group('AdminAction', () {
    test('round-trips through its wire name', () {
      for (final action in AdminAction.values) {
        expect(AdminAction.fromWireName(action.wireName), equals(action));
      }
    });

    test('an unknown action is null, not a guess', () {
      expect(AdminAction.fromWireName('delete'), isNull);
    });

    test('a result naming an unknown action decodes as unknown', () {
      // Reporting "you kicked them" for an action a newer server invented
      // would be worse than reporting nothing.
      final decoded = decodeMessage(
        jsonEncode({
          'type': MessageType.adminActionResult.wireName,
          'version': protocolVersion,
          'action': 'vaporise',
          'targetId': 'p1',
          'targetName': 'Alice',
        }),
      );

      expect(decoded, isA<UnknownMessage>());
    });
  });

  group('AdminError', () {
    test('round-trips through its wire name', () {
      for (final error in AdminError.values) {
        expect(AdminError.fromWireName(error.wireName), equals(error));
      }
    });

    test('an unrecognised reason falls back to badRequest', () {
      expect(AdminError.fromWireName('teapot'), equals(AdminError.badRequest));
    });
  });

  group('JoinRejection.banned', () {
    test('is its own reason, not a name problem', () {
      // The client branches on this: a bad name sends you to setup to fix
      // it, a ban has nothing to fix.
      expect(
        JoinRejection.fromWireName('banned'),
        equals(JoinRejection.banned),
      );
      expect(JoinRejection.banned, isNot(equals(JoinRejection.invalidName)));
    });
  });

  group('JoinRejection.kicked', () {
    test('is its own reason, and not the ban next to it', () {
      // The client branches on this too, and the branch is the point: a ban
      // is a dead end, a kick is a wait.
      expect(
        JoinRejection.fromWireName('kicked'),
        equals(JoinRejection.kicked),
      );
      expect(JoinRejection.kicked, isNot(equals(JoinRejection.banned)));
    });
  });

  group('JoinRejection.maintenance', () {
    test('is its own reason', () {
      expect(
        JoinRejection.fromWireName('maintenance'),
        equals(JoinRejection.maintenance),
      );
    });
  });

  group('JoinRejection.worldFull', () {
    test('round trips through fromWireName', () {
      expect(
        JoinRejection.fromWireName('worldFull'),
        equals(JoinRejection.worldFull),
      );
    });

    test('is its own reason, not the maintenance next to it', () {
      // Both are refusals about the event rather than the person, and the
      // client shows a different screen for each: maintenance names a moment
      // the doors reopen, full cannot.
      expect(
        JoinRejection.worldFull,
        isNot(equals(JoinRejection.maintenance)),
      );
    });

    test('an unknown reason still falls back to invalidName', () {
      // The v4 fallback this value's doc comment is about. It must keep
      // failing closed rather than throwing, or every future addition here
      // becomes a crash on every older client.
      expect(
        () => JoinRejection.fromWireName('somethingFromV6'),
        returnsNormally,
      );
      expect(
        JoinRejection.fromWireName('somethingFromV6'),
        equals(JoinRejection.invalidName),
      );
    });

    test('the five older reasons are untouched', () {
      expect(
        JoinRejection.values,
        containsAll(<JoinRejection>[
          JoinRejection.invalidName,
          JoinRejection.invalidSession,
          JoinRejection.banned,
          JoinRejection.kicked,
          JoinRejection.maintenance,
        ]),
      );
      expect(JoinRejection.values, hasLength(6));
    });
  });

  group('AdminSetMaintenanceMessage', () {
    final until = DateTime.utc(2026, 8, 22, 18, 30);

    test('round trips through the codec', () {
      final message = AdminSetMaintenanceMessage(
        token: 'a-long-enough-test-token',
        until: until,
      );

      final decoded = decodeMessage(encodeMessage(message));

      expect(decoded, equals(message));
      expect((decoded as AdminSetMaintenanceMessage).until, equals(until));
    });

    test('a null until round trips as "open the event"', () {
      const message = AdminSetMaintenanceMessage(token: 'tok');

      expect(decodeMessage(encodeMessage(message)), equals(message));
    });

    test('an unreadable until is dropped, not read as open', () {
      // The opposite of the config document's tolerance, and deliberately so:
      // a client that sent a timestamp meant something, and turning that into
      // "reopen the event" would be the reverse of what was asked.
      final decoded = decodeMessage(
        '{"type":"admin.setMaintenance","token":"tok","until":"soon"}',
      );

      expect(decoded, isA<UnknownMessage>());
    });

    test('does not print the token', () {
      // It ends up in log lines, like every other toString here.
      const message = AdminSetMaintenanceMessage(token: 'super-secret');

      expect(message.toString(), isNot(contains('super-secret')));
    });
  });
}
