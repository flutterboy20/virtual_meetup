import 'dart:io';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Session ids for the people in these tests.
const String aliceSession = 'a11ce000000000000000000000000001';
const String bobSession = 'b0b00000000000000000000000000002';

/// The gate seen through the real transport: a real HTTP server, a real
/// upgrade, real sockets.
///
/// The unit behaviour is settled in `connection_gate_test.dart`. This file
/// only proves the two caps are wired to the two places they have to be — the
/// upgrade and the join — and that a socket dying gives its slot back, which
/// a fake cannot prove.
void main() {
  late HttpServer server;
  late MapRelays hub;
  late Relay relay;
  late AdminHub admin;
  late Uri wsUri;
  late Uri adminUri;

  Future<void> boot(ConnectionGate gate) async {
    hub = MapRelays(gate: gate, tickInterval: const Duration(milliseconds: 10));
    relay = hub.relayFor(MapId.conference);
    admin = AdminHub(relays: hub, token: 'a-long-enough-test-token');
    hub.start();
    server = await shelf_io.serve(
      buildHandler(relays: hub, admin: admin),
      InternetAddress.loopbackIPv4,
      0,
    );
    wsUri = Uri.parse('ws://127.0.0.1:${server.port}/$webSocketPath');
    adminUri = Uri.parse('ws://127.0.0.1:${server.port}/$adminWebSocketPath');
  }

  tearDown(() async {
    hub.stop();
    admin.stop();
    await server.close(force: true);
  });

  Future<WebSocketChannel> openSocket() async {
    final channel = WebSocketChannel.connect(wsUri);
    await channel.ready;
    return channel;
  }

  JoinMessage join(String sessionId, String name) => JoinMessage(
    sessionId: sessionId,
    name: name,
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
  );

  group('the hard cap', () {
    test('a socket past MAX_SOCKETS is refused with 503', () async {
      await boot(ConnectionGate(maxSockets: 1));
      final first = await openSocket();

      final response = await HttpClient()
          .getUrl(wsUri.replace(scheme: 'http'))
          .then((request) => request.close());

      expect(response.statusCode, equals(HttpStatus.serviceUnavailable));
      // Refused before `webSocketHandler` ran, so no socket was allocated —
      // which is the only refusal cheap enough to survive a flood.
      expect(hub.gate.openSockets, equals(1));
      await first.sink.close();
    });

    test('the relay never sees a refused socket', () async {
      await boot(ConnectionGate(maxSockets: 1));
      final first = await openSocket();
      first.sink.add(encodeMessage(join(aliceSession, 'Alice')));
      await _until(() => relay.playerCount == 1);

      await expectLater(
        WebSocketChannel.connect(wsUri).ready,
        throwsA(isA<Object>()),
      );

      expect(relay.playerCount, equals(1));
      await first.sink.close();
    });

    test('a closed socket frees its slot for the next one', () async {
      await boot(ConnectionGate(maxSockets: 1));
      final first = await openSocket();
      expect(hub.gate.openSockets, equals(1));

      await first.sink.close();
      await _until(() => hub.gate.openSockets == 0);

      final second = await openSocket();
      expect(hub.gate.openSockets, equals(1));
      await second.sink.close();
    });

    test('a plain GET on the socket path holds no slot', () async {
      // The health-check-curls-the-socket-path case. A request that is never
      // upgraded took no socket, so it must not hold one — otherwise a
      // monitor would exhaust the cap on its own.
      await boot(ConnectionGate(maxSockets: 2));

      for (var i = 0; i < 5; i++) {
        final response = await HttpClient()
            .getUrl(wsUri.replace(scheme: 'http'))
            .then((request) => request.close());
        expect(response.statusCode, equals(HttpStatus.notFound));
      }

      expect(hub.gate.openSockets, equals(0));
      final channel = await openSocket();
      expect(hub.gate.openSockets, equals(1));
      await channel.sink.close();
    });

    test('an admin socket connects while the player gate is full', () async {
      // The moment the world is full is the moment a moderator most needs to
      // get in. The admin route does not consult the gate at all.
      await boot(ConnectionGate(maxSockets: 1));
      final player = await openSocket();
      expect(hub.gate.openSockets, equals(1));

      final adminSocket = WebSocketChannel.connect(adminUri);
      await adminSocket.ready;

      adminSocket.sink.add(
        encodeMessage(
          const AdminAuthMessage(token: 'a-long-enough-test-token'),
        ),
      );
      final result = decodeMessage(
        await adminSocket.stream.first as String,
      ) as AdminAuthResultMessage;

      expect(result.authorized, isTrue);
      await adminSocket.sink.close();
      await player.sink.close();
    });
  });

  group('the soft cap', () {
    test('a join past MAX_PLAYERS is rejected with worldFull', () async {
      await boot(ConnectionGate(maxSockets: 10, maxPlayers: 1));
      final alice = await openSocket();
      alice.sink.add(encodeMessage(join(aliceSession, 'Alice')));
      await _until(() => relay.playerCount == 1);

      final bob = await openSocket();
      final inbound = bob.stream.map((data) => decodeMessage(data as String));
      bob.sink.add(encodeMessage(join(bobSession, 'Bob')));

      final rejection = await inbound.first as JoinRejectedMessage;
      expect(rejection.reason, equals(JoinRejection.worldFull));
      // A sentence, and deliberately no time in it: nobody knows when a seat
      // frees.
      expect(rejection.detail, isNotEmpty);
      expect(relay.playerCount, equals(1));

      await alice.sink.close();
      await bob.sink.close();
    });

    test('a seat freeing lets the next join in', () async {
      await boot(ConnectionGate(maxSockets: 10, maxPlayers: 1));
      final alice = await openSocket();
      alice.sink.add(encodeMessage(join(aliceSession, 'Alice')));
      await _until(() => relay.playerCount == 1);

      await alice.sink.close();
      await _until(() => relay.playerCount == 0);

      final bob = await openSocket();
      final inbound = bob.stream.map((data) => decodeMessage(data as String));
      bob.sink.add(encodeMessage(join(bobSession, 'Bob')));

      expect(await inbound.first, isA<WelcomeMessage>());
      await bob.sink.close();
    });

    test('an unset cap behaves exactly as before', () async {
      // The behaviour-preservation check: the default gate is far above
      // anything a laptop reaches, so nothing about a normal join changes.
      await boot(ConnectionGate());
      final alice = await openSocket();
      final inbound = alice.stream.map((data) => decodeMessage(data as String));
      alice.sink.add(encodeMessage(join(aliceSession, 'Alice')));

      expect(await inbound.first, isA<WelcomeMessage>());
      await alice.sink.close();
    });
  });
}

/// Waits until [condition] holds, or fails the test after a second.
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition did not hold within a second');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
