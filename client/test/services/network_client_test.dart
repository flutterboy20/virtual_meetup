import 'package:client/core/server_endpoint.dart';
import 'package:client/services/network_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_socket.dart';

void main() {
  const join = JoinMessage(
    sessionId: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
    name: 'Alice',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
  );

  group('connecting', () {
    test('starts idle and connects', () async {
      final (:client, :socket) = fakeNetwork();
      expect(client.status.value, ConnectionStatus.idle);

      await client.connect();

      expect(client.status.value, ConnectionStatus.connected);
      expect(client.isConnected, isTrue);
      expect(socket.closed, isFalse);
      await client.dispose();
    });

    test('a server that is not running leaves the client offline', () async {
      // The whole point: no throw, no error screen, no crash into the game
      // loop. You just end up alone in the world.
      final (:client, :socket) = fakeNetwork(
        openError: StateError('connection refused'),
      );

      await expectLater(client.connect(), completes);

      expect(client.status.value, ConnectionStatus.offline);
      expect(client.isConnected, isFalse);
      await client.dispose();
    });

    test('defaults to the configured server endpoint', () {
      expect(NetworkClient().url, equals(resolveServerUri()));
    });
  });

  group('receiving', () {
    test('decodes messages onto the stream', () async {
      final (:client, :socket) = fakeNetwork();
      await client.connect();
      final received = client.messages.take(2).toList();

      socket
        ..emit(const WelcomeMessage(yourId: 'p1'))
        ..emit(const PlayerLeftMessage(id: 'p2'));

      expect(await received, [
        const WelcomeMessage(yourId: 'p1'),
        const PlayerLeftMessage(id: 'p2'),
      ]);
      await client.dispose();
    });

    test('drops an unreadable frame without breaking the stream', () async {
      final (:client, :socket) = fakeNetwork();
      await client.connect();
      final received = client.messages.take(1).toList();

      socket
        ..emitRaw('not json at all')
        ..emitRaw('{"type":"emote","version":1}')
        ..emit(const PlayerLeftMessage(id: 'p2'));

      expect(await received, [const PlayerLeftMessage(id: 'p2')]);
      expect(client.status.value, ConnectionStatus.connected);
      await client.dispose();
    });
  });

  group('sending', () {
    test('encodes a message onto the socket', () async {
      final (:client, :socket) = fakeNetwork();
      await client.connect();

      client.send(join);

      expect(socket.sentMessages, [join]);
      await client.dispose();
    });

    test('drops a message when there is no connection', () async {
      final (:client, :socket) = fakeNetwork();

      client.send(join);

      expect(socket.sent, isEmpty);
      await client.dispose();
    });
  });

  group('dropping', () {
    test('a server that goes away leaves the client offline', () async {
      final (:client, :socket) = fakeNetwork();
      await client.connect();

      socket.dropFromServer();
      await pumpEventQueue();

      expect(client.status.value, ConnectionStatus.offline);
      expect(client.isConnected, isFalse);
      await client.dispose();
    });

    test('a socket error leaves the client offline, not crashed', () async {
      final (:client, :socket) = fakeNetwork();
      await client.connect();

      socket.failWith(StateError('network went away'));
      await pumpEventQueue();

      expect(client.status.value, ConnectionStatus.offline);
      await client.dispose();
    });

    test('sending after a drop is a no-op', () async {
      final (:client, :socket) = fakeNetwork();
      await client.connect();
      socket.dropFromServer();
      await pumpEventQueue();
      final before = socket.sent.length;

      client.send(join);

      expect(socket.sent, hasLength(before));
      await client.dispose();
    });
  });

  group('dispose', () {
    test('closes the socket', () async {
      final (:client, :socket) = fakeNetwork();
      await client.connect();

      await client.dispose();

      expect(socket.closed, isTrue);
    });

    test('connecting after dispose does nothing', () async {
      final (:client, :socket) = fakeNetwork();
      await client.dispose();

      await client.connect();

      expect(socket.sent, isEmpty);
    });
  });
}
