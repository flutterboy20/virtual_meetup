import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:test/test.dart';

/// A socket that records what it was sent.
class FakeConnection implements PlayerConnection {
  final List<String> sent = [];
  bool closed = false;

  List<ProtocolMessage> get received =>
      sent.map(decodeMessage).toList(growable: false);

  List<AdminAuthResultMessage> get authResults =>
      received.whereType<AdminAuthResultMessage>().toList(growable: false);

  List<AdminErrorMessage> get errors =>
      received.whereType<AdminErrorMessage>().toList(growable: false);

  List<AdminActionResultMessage> get results =>
      received.whereType<AdminActionResultMessage>().toList(growable: false);

  @override
  void send(String data) => sent.add(data);

  @override
  void close() => closed = true;
}

void main() {
  const token = 'a-long-enough-test-token';

  ({MapRelays relays, AdminHub hub, List<String> log}) world() {
    final log = <String>[];
    final relays = MapRelays(log: log.add);
    return (
      relays: relays,
      hub: AdminHub(relays: relays, token: token, log: log.add),
      log: log,
    );
  }

  void auth(AdminSession session, String candidate) =>
      session.handleData(encodeMessage(AdminAuthMessage(token: candidate)));

  group('the admin auth throttle', () {
    test('four failures leave the socket open and usable', () {
      final it = world();
      final connection = FakeConnection();
      final session = it.hub.open(connection);

      for (var i = 0; i < maxAdminAuthFailures - 1; i++) {
        auth(session, 'wrong-token-$i');
      }

      expect(connection.closed, isFalse);
      expect(connection.authResults, hasLength(maxAdminAuthFailures - 1));
      expect(
        connection.authResults.every((result) => !result.authorized),
        isTrue,
      );

      // Still usable: the right token on the fifth attempt gets in.
      auth(session, token);

      expect(session.isAuthorized, isTrue);
      expect(connection.closed, isFalse);
    });

    test('the fifth failure closes the socket', () {
      final it = world();
      final connection = FakeConnection();
      final session = it.hub.open(connection);

      for (var i = 0; i < maxAdminAuthFailures; i++) {
        auth(session, 'wrong-token-$i');
      }

      expect(connection.closed, isTrue);
      expect(session.isAuthorized, isFalse);
      // The refusal is sent before the socket goes, so a moderator who really
      // did fat-finger it five times is told why rather than watching the
      // connection die in silence.
      expect(connection.authResults, hasLength(maxAdminAuthFailures));
      expect(connection.authResults.last.authorized, isFalse);
    });

    test('a closed socket accepts nothing further', () {
      final it = world();
      final connection = FakeConnection();
      final session = it.hub.open(connection);
      for (var i = 0; i < maxAdminAuthFailures; i++) {
        auth(session, 'wrong-token-$i');
      }
      final sentByThen = connection.sent.length;

      // Even the right token, on a socket that has been closed.
      auth(session, token);

      expect(session.isAuthorized, isFalse);
      expect(connection.sent, hasLength(sentByThen));
    });

    test('a success resets the count', () {
      final it = world();
      final connection = FakeConnection();
      final session = it.hub.open(connection);

      // Four wrong, one right, four wrong again. Without a reset the ninth
      // message would close the socket; with one, it is only the fourth
      // strike of a fresh five.
      for (var i = 0; i < maxAdminAuthFailures - 1; i++) {
        auth(session, 'wrong-$i');
      }
      auth(session, token);
      expect(session.isAuthorized, isTrue);

      for (var i = 0; i < maxAdminAuthFailures - 1; i++) {
        auth(session, 'wrong-again-$i');
      }

      expect(connection.closed, isFalse);
      // A wrong token still drops privilege, throttle or no throttle.
      expect(session.isAuthorized, isFalse);
    });

    test('the log never carries the token that was tried', () {
      final it = world();
      final session = it.hub.open(FakeConnection());

      auth(session, 'hunter2-hunter2-hunter2');

      expect(
        it.log.any((line) => line.contains('hunter2')),
        isFalse,
        reason: 'a rejected token leaked into the log',
      );
    });

    test('each socket carries its own count', () {
      // A shared counter would let one attacker's guesses lock out the
      // moderator, which is the failure this throttle must not create.
      final it = world();
      final attacker = FakeConnection();
      final attackerSession = it.hub.open(attacker);
      final moderator = FakeConnection();
      final moderatorSession = it.hub.open(moderator);

      for (var i = 0; i < maxAdminAuthFailures; i++) {
        auth(attackerSession, 'wrong-$i');
      }
      expect(attacker.closed, isTrue);

      auth(moderatorSession, token);

      expect(moderator.closed, isFalse);
      expect(moderatorSession.isAuthorized, isTrue);
    });
  });

  group('the maintenance re-check is deliberately not throttled', () {
    test('a failed re-check neither closes the socket nor drops privilege', () {
      final it = world();
      final connection = FakeConnection();
      final session = it.hub.open(connection);
      auth(session, token);
      expect(session.isAuthorized, isTrue);

      // Well past the auth throttle's limit, on the confirmation dialog.
      for (var i = 0; i < maxAdminAuthFailures * 3; i++) {
        session.handleData(
          encodeMessage(
            AdminSetMaintenanceMessage(
              token: 'mistyped-$i',
              until: DateTime.now().toUtc().add(const Duration(hours: 1)),
            ),
          ),
        );
      }

      expect(connection.closed, isFalse);
      expect(
        session.isAuthorized,
        isTrue,
        reason:
            'a mistyped confirmation must not cost a moderator their '
            'session mid-incident',
      );
      expect(
        connection.errors.every(
          (error) => error.reason == AdminError.unauthorized,
        ),
        isTrue,
      );
      // Nothing was changed by any of them.
      expect(it.relays.config.config.maintenanceUntil, isNull);
    });

    test('the socket still works after a run of failed re-checks', () {
      final it = world();
      final connection = FakeConnection();
      final session = it.hub.open(connection);
      auth(session, token);
      for (var i = 0; i < maxAdminAuthFailures * 2; i++) {
        session.handleData(
          encodeMessage(
            AdminSetMaintenanceMessage(token: 'mistyped-$i'),
          ),
        );
      }

      final until = DateTime.now().toUtc().add(const Duration(hours: 1));
      session.handleData(
        encodeMessage(AdminSetMaintenanceMessage(token: token, until: until)),
      );

      expect(connection.results.last.action, equals(AdminAction.maintenanceOn));
      expect(it.relays.config.config.maintenanceUntil, equals(until));
    });
  });
}
