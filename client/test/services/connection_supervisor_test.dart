import 'dart:async';

import 'package:client/core/player_identity.dart';
import 'package:client/services/connection_supervisor.dart';
import 'package:client/services/reconnect_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_socket.dart';

void main() {
  const identity = PlayerIdentity(
    sessionId: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
    name: 'Ada',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
  );

  /// The backoff timers the supervisor asked for, so a test can fire them by
  /// hand instead of waiting seconds of real time out.
  late List<_PendingRetry> pending;

  setUp(() => pending = []);

  Timer fakeTimer(Duration delay, void Function() callback) {
    final retry = _PendingRetry(delay, callback);
    pending.add(retry);
    return retry;
  }

  ({ConnectionSupervisor supervisor, FakeSocket socket}) build() {
    final (:client, :socket) = fakeNetwork();
    addTearDown(client.dispose);
    final supervisor = ConnectionSupervisor(
      network: client,
      identity: identity,
      createTimer: fakeTimer,
    );
    addTearDown(supervisor.dispose);
    return (supervisor: supervisor, socket: socket);
  }

  group('joining', () {
    test('introduces itself the moment the socket opens', () async {
      final (:supervisor, :socket) = build();

      await supervisor.start();

      final join = socket.sentMessages.whereType<JoinMessage>().single;
      expect(join.sessionId, identity.sessionId);
      expect(join.name, 'Ada');
      expect(join.color, identity.color);
      expect(join.cosmetic, PlayerCosmetic.cap);
      expect(supervisor.phase, ConnectionPhase.connected);
    });

    test('starting twice does not join twice', () async {
      final (:supervisor, :socket) = build();

      await supervisor.start();
      await supervisor.start();

      expect(socket.sentMessages.whereType<JoinMessage>(), hasLength(1));
    });
  });

  group('reconnecting', () {
    test('a drop arms a backoff rather than retrying immediately', () async {
      final (:supervisor, :socket) = build();
      await supervisor.start();

      socket.dropFromServer();
      await pumpEventQueue();

      expect(supervisor.phase, ConnectionPhase.waiting);
      expect(supervisor.attempt, 1);
      expect(pending, hasLength(1));
      expect(pending.single.delay.inMicroseconds, greaterThan(0));
    });

    test('the retry re-joins with the SAME session id', () async {
      // The whole reconnection story in one assertion: the server can only
      // re-seat somebody it recognises, and this is what it recognises them
      // by.
      final (:client, :sockets) = reconnectingNetwork();
      addTearDown(client.dispose);
      final supervisor = ConnectionSupervisor(
        network: client,
        identity: identity,
        createTimer: fakeTimer,
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      sockets.single.dropFromServer();
      await pumpEventQueue();

      pending.single.fire();
      await pumpEventQueue();

      expect(sockets, hasLength(2), reason: 'the retry opened a new socket');
      expect(supervisor.phase, ConnectionPhase.connected);

      final rejoin = sockets.last.sentMessages.whereType<JoinMessage>().single;
      expect(rejoin.sessionId, equals(identity.sessionId));
      expect(rejoin.name, equals('Ada'));
    });

    test('a successful retry clears the backoff for next time', () async {
      final (:client, :sockets) = reconnectingNetwork();
      addTearDown(client.dispose);
      final supervisor = ConnectionSupervisor(
        network: client,
        identity: identity,
        createTimer: fakeTimer,
      );
      addTearDown(supervisor.dispose);

      await supervisor.start();
      sockets.single.dropFromServer();
      await pumpEventQueue();
      pending.single.fire();
      await pumpEventQueue();

      expect(supervisor.attempt, isZero);
    });

    test('repeated failures back off further each time', () async {
      final (:supervisor, :socket) = build();
      await supervisor.start();

      socket.dropFromServer();
      await pumpEventQueue();
      // The socket is dead now, so each retry fails and arms the next one.
      for (var i = 0; i < 3; i++) {
        pending.last.fire();
        await pumpEventQueue();
      }

      expect(supervisor.attempt, greaterThan(1));
      expect(pending.length, greaterThan(1));
      // Not a strict > because jitter can make one draw smaller than the
      // last; the *ceiling* is what grows, and over three doublings the
      // spread cannot hide it.
      expect(
        pending.last.delay.inMicroseconds,
        greaterThan(pending.first.delay.inMicroseconds),
      );
    });

    test('notifies its listeners as the phase changes', () async {
      final (:supervisor, :socket) = build();
      var notifications = 0;
      supervisor.addListener(() => notifications++);

      await supervisor.start();
      socket.dropFromServer();
      await pumpEventQueue();

      expect(notifications, greaterThanOrEqualTo(2));
    });

    test('stopping cancels a retry that has not fired yet', () async {
      // A twenty-second backoff left running after somebody leaves would
      // reconnect a player who has gone.
      final (:supervisor, :socket) = build();
      await supervisor.start();
      socket.dropFromServer();
      await pumpEventQueue();
      expect(pending.single.isCancelled, isFalse);

      await supervisor.stop();

      expect(pending.single.isCancelled, isTrue);
    });

    test('a retry that fires after stopping does nothing', () async {
      final (:supervisor, :socket) = build();
      await supervisor.start();
      socket.dropFromServer();
      await pumpEventQueue();
      final before = socket.sent.length;

      await supervisor.stop();
      pending.single.fire();
      await pumpEventQueue();

      expect(socket.sent, hasLength(before));
    });
  });

  group('rejection', () {
    test('records the server refusing the join', () async {
      final (:supervisor, :socket) = build();
      await supervisor.start();

      socket.emit(
        const JoinRejectedMessage(
          reason: JoinRejection.invalidName,
          detail: 'Please pick a different name.',
        ),
      );
      await pumpEventQueue();

      expect(supervisor.wasRejected, isTrue);
      expect(supervisor.rejection?.reason, JoinRejection.invalidName);
      expect(supervisor.rejection?.detail, 'Please pick a different name.');
    });

    test('does not retry a socket the server closed on purpose', () async {
      // Retrying a "no" is an infinite loop of being told no.
      final (:supervisor, :socket) = build();
      await supervisor.start();

      socket.emit(
        const JoinRejectedMessage(
          reason: JoinRejection.invalidName,
          detail: 'nope',
        ),
      );
      await pumpEventQueue();
      socket.dropFromServer();
      await pumpEventQueue();

      expect(pending, isEmpty);
    });
  });

  group('changing identity', () {
    test('re-joins on the open socket under the new name', () async {
      final (:supervisor, :socket) = build();
      await supervisor.start();

      await supervisor.updateIdentity(identity.copyWith(name: 'Ada L'));

      final joins = socket.sentMessages.whereType<JoinMessage>();
      expect(joins.last.name, 'Ada L');
      // Same session id: a new name must not cost the player their seat.
      expect(joins.last.sessionId, identity.sessionId);
    });
  });
}

/// A [Timer] the test fires by hand.
class _PendingRetry implements Timer {
  _PendingRetry(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;

  bool isCancelled = false;
  bool hasFired = false;

  /// Runs the callback as the real timer would.
  void fire() {
    if (isCancelled || hasFired) return;
    hasFired = true;
    _callback();
  }

  @override
  bool get isActive => !isCancelled && !hasFired;

  @override
  int get tick => hasFired ? 1 : 0;

  @override
  void cancel() => isCancelled = true;
}
