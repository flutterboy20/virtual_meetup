import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:test/test.dart';

/// A socket that records what it was sent and whether it was closed.
class FakeConnection implements PlayerConnection {
  final List<String> sent = [];
  bool closed = false;

  /// Everything sent to this socket, decoded.
  List<ProtocolMessage> get received =>
      sent.map(decodeMessage).toList(growable: false);

  @override
  void send(String data) => sent.add(data);

  @override
  void close() => closed = true;
}

/// How long the tests wait for a deadline set to [deadline] to have fired.
///
/// Three times the deadline, because the timer is a real one on a real event
/// loop and a wait equal to the deadline is a flaky test on a loaded machine.
Future<void> pastDeadline(Duration deadline) =>
    Future<void>.delayed(deadline * 3);

void main() {
  // Short enough that the tests finish, long enough that the socket under
  // test is genuinely idle for a while first.
  const deadline = Duration(milliseconds: 40);

  const session = 'a11ce000000000000000000000000001';

  JoinMessage join({String sessionId = session, String name = 'Ada'}) =>
      JoinMessage(
        sessionId: sessionId,
        name: name,
        color: 0xFF54C5F8,
        cosmetic: PlayerCosmetic.cap,
      );

  group('the player join deadline', () {
    /// A relay whose released slots are counted, as the gate counts them.
    ({Relay relay, List<String> log, List<int> released}) world() {
      final log = <String>[];
      final released = <int>[];
      return (
        relay: Relay(
          log: log.add,
          joinDeadline: deadline,
          onSocketClosed: () => released.add(1),
        ),
        log: log,
        released: released,
      );
    }

    test('closes a socket that connects and never joins', () async {
      final it = world();
      final socket = FakeConnection();
      it.relay.open(socket);

      expect(socket.closed, isFalse, reason: 'closed before the deadline');
      await pastDeadline(deadline);

      expect(socket.closed, isTrue);
      expect(it.log.join('\n'), contains('closing a socket that never joined'));
    });

    test('gives the socket slot back, which is the whole point', () async {
      final it = world();
      it.relay.open(FakeConnection());
      await pastDeadline(deadline);

      // Without this the cap only decides who is refused next: a few hundred
      // silent sockets would hold every slot for as long as they stayed open.
      expect(it.released, hasLength(1));
    });

    test('leaves a socket that joined in time alone', () async {
      final it = world();
      final socket = FakeConnection();
      it.relay.open(socket).handleData(encodeMessage(join()));

      await pastDeadline(deadline);

      expect(socket.closed, isFalse);
      expect(it.relay.playerCount, equals(1));
      expect(it.released, isEmpty);
    });

    test('a joined socket keeps the id it was given', () async {
      final it = world();
      final socket = FakeConnection();
      final relaySession = it.relay.open(socket)
        ..handleData(encodeMessage(join()));

      await pastDeadline(deadline);

      expect(relaySession.playerId, isNotNull);
      expect(socket.closed, isFalse);
    });

    test('does not fire twice when the socket closed on its own', () async {
      final it = world();
      it.relay.open(FakeConnection()).close();

      await pastDeadline(deadline);

      // One release, from the close — not a second one from a timer that
      // outlived the socket.
      expect(it.released, hasLength(1));
    });
  });

  group('a rejected join', () {
    test('hands its socket slot back', () {
      final released = <int>[];
      final relay = Relay(
        log: (_) {},
        joinDeadline: deadline,
        onSocketClosed: () => released.add(1),
      );
      final socket = FakeConnection();

      relay
          .open(socket)
          .handleData(encodeMessage(join(sessionId: 'not-a-session-id')));

      expect(socket.closed, isTrue);
      // The regression this guards: `_reject` marks the session closed so the
      // rejection can go out before the socket dies, which used to make the
      // `close` the transport calls next return at its first line — leaking
      // the slot for the life of the process. Refused joins are the cheapest
      // frame in the protocol to send, so that leak was a way to shut the
      // event down for good with 800 malformed messages.
      expect(released, hasLength(1));
    });

    test('is not double-released when the transport closes after', () async {
      final released = <int>[];
      final relay = Relay(
        log: (_) {},
        joinDeadline: deadline,
        onSocketClosed: () => released.add(1),
      );
      relay.open(FakeConnection())
        ..handleData(encodeMessage(join(sessionId: 'not-a-session-id')))
        // What `onDone` does a moment later.
        ..close();

      await pastDeadline(deadline);

      expect(released, hasLength(1));
    });
  });

  group('the admin socket cap', () {
    const token = 'a-long-enough-test-token';

    ({AdminHub hub, List<String> log}) world() {
      final log = <String>[];
      return (
        hub: AdminHub(
          relays: MapRelays(log: log.add),
          token: token,
          log: log.add,
          authDeadline: deadline,
        ),
        log: log,
      );
    }

    void authenticate(AdminHub hub, FakeConnection socket) => hub
        .open(socket)
        .handleData(encodeMessage(const AdminAuthMessage(token: token)));

    test('holds at most four silent sockets', () {
      final it = world();
      final sockets = [for (var i = 0; i < 4; i++) FakeConnection()]
        ..forEach(it.hub.open);

      expect(it.hub.socketCount, equals(maxUnauthenticatedAdminSockets));
      expect(sockets.every((socket) => !socket.closed), isTrue);
    });

    test('evicts the oldest silent socket to seat a newcomer', () {
      final it = world();
      final sockets = [for (var i = 0; i < 4; i++) FakeConnection()]
        ..forEach(it.hub.open);

      final newcomer = FakeConnection();
      it.hub.open(newcomer);

      // The newcomer might be the moderator; the socket that has been silent
      // longest is the best guess at the one that is not.
      expect(sockets.first.closed, isTrue);
      expect(newcomer.closed, isFalse);
      expect(it.hub.unauthorizedCount, equals(maxUnauthenticatedAdminSockets));
      expect(it.log.join('\n'), contains('evicted the oldest'));
    });

    test('a flood never pushes the count past the cap', () {
      final it = world();
      for (var i = 0; i < 50; i++) {
        it.hub.open(FakeConnection());
      }

      expect(it.hub.socketCount, lessThanOrEqualTo(maxAdminSockets));
      expect(
        it.hub.unauthorizedCount,
        lessThanOrEqualTo(maxUnauthenticatedAdminSockets),
      );
    });

    test('never evicts an authorised moderator', () {
      final it = world();
      final moderator = FakeConnection();
      authenticate(it.hub, moderator);

      for (var i = 0; i < 50; i++) {
        it.hub.open(FakeConnection());
      }

      expect(moderator.closed, isFalse);
      expect(it.hub.authorizedCount, equals(1));
    });

    test('a moderator can still get in through a full flood', () {
      final it = world();
      for (var i = 0; i < 50; i++) {
        it.hub.open(FakeConnection());
      }

      final moderator = FakeConnection();
      authenticate(it.hub, moderator);

      // The reservation, seen from the only angle that matters.
      expect(moderator.closed, isFalse);
      expect(it.hub.authorizedCount, equals(1));
    });

    test('refuses a socket when every seat is an authorised one', () {
      final it = world();
      for (var i = 0; i < maxAdminSockets; i++) {
        authenticate(it.hub, FakeConnection());
      }
      expect(it.hub.authorizedCount, equals(maxAdminSockets));

      final refused = FakeConnection();
      it.hub.open(refused);

      expect(refused.closed, isTrue);
      expect(it.hub.socketCount, equals(maxAdminSockets));
      // Told why, rather than dropped: only somebody with the token can be
      // here at all.
      expect(
        refused.received.whereType<AdminAuthResultMessage>().last.authorized,
        isFalse,
      );
      expect(it.log.join('\n'), contains('refused an admin socket'));
    });
  });

  group('the admin auth deadline', () {
    const token = 'a-long-enough-test-token';

    ({AdminHub hub, List<String> log}) world() {
      final log = <String>[];
      return (
        hub: AdminHub(
          relays: MapRelays(log: log.add),
          token: token,
          log: log.add,
          authDeadline: deadline,
        ),
        log: log,
      );
    }

    test('closes a socket that never authenticates', () async {
      final it = world();
      final socket = FakeConnection();
      it.hub.open(socket);

      expect(socket.closed, isFalse);
      await pastDeadline(deadline);

      expect(socket.closed, isTrue);
      expect(it.hub.socketCount, isZero);
      expect(it.log.join('\n'), contains('never authenticated'));
    });

    test('leaves an authenticated moderator connected', () async {
      final it = world();
      final socket = FakeConnection();
      it.hub
          .open(socket)
          .handleData(encodeMessage(const AdminAuthMessage(token: token)));

      await pastDeadline(deadline);

      expect(socket.closed, isFalse);
      expect(it.hub.authorizedCount, equals(1));
    });

    test('recovers every seat a flood took', () async {
      final it = world();
      for (var i = 0; i < 50; i++) {
        it.hub.open(FakeConnection());
      }
      expect(it.hub.socketCount, greaterThan(0));

      await pastDeadline(deadline);

      // The cap bounds the damage; this is what ends it.
      expect(it.hub.socketCount, isZero);
    });
  });
}
