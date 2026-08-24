import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Session ids for the two people in these tests.
///
/// Fixed strings rather than generated ones: each test opens its own server,
/// so there is no collision to avoid, and a literal is easier to read than a
/// counter.
const String aliceSession = 'a11ce000000000000000000000000001';
const String bobSession = 'b0b00000000000000000000000000002';

void main() {
  // These tests run the real thing: a real HTTP server, a real upgrade, real
  // sockets. Everything about the *protocol* is covered by the fast unit
  // tests in relay_test.dart — this file only proves the transport is wired
  // up and that a socket dying is handled, which a fake cannot prove.
  late HttpServer server;
  late MapRelays hub;
  late Relay relay;
  late Uri wsUri;
  late List<String> logs;

  setUp(() async {
    logs = [];
    hub = MapRelays(
      log: logs.add,
      // A fast tick keeps these tests quick. They are about the transport,
      // not the rate — what a snapshot contains is settled in relay_test.
      tickInterval: const Duration(milliseconds: 10),
    );
    relay = hub.relayFor(MapId.conference);
    hub.start();
    server = await shelf_io.serve(
      buildHandler(relays: hub),
      InternetAddress.loopbackIPv4,
      0,
    );
    wsUri = Uri.parse('ws://127.0.0.1:${server.port}/$webSocketPath');
  });

  tearDown(() async {
    hub.stop();
    await server.close(force: true);
  });

  Future<WebSocketChannel> openSocket() async {
    final channel = WebSocketChannel.connect(wsUri);
    await channel.ready;
    return channel;
  }

  test('a plain GET on the socket path is not upgraded', () async {
    final response = await HttpClient()
        .getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/$webSocketPath'),
        )
        .then((request) => request.close());

    expect(response.statusCode, equals(HttpStatus.notFound));
  });

  test('the health route still works alongside the socket route', () async {
    final response = await HttpClient()
        .getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/$healthPath'),
        )
        .then((request) => request.close());

    expect(response.statusCode, equals(HttpStatus.ok));
  });

  test('a socket joins and is welcomed', () async {
    final channel = await openSocket();
    final inbound = channel.stream.map((data) => decodeMessage(data as String));

    channel.sink.add(
      encodeMessage(
        const JoinMessage(
          sessionId: aliceSession,
          name: 'Alice',
          color: 0xFF54C5F8,
          cosmetic: PlayerCosmetic.cap,
        ),
      ),
    );

    final welcome = await inbound.first as WelcomeMessage;
    expect(welcome.yourId, isNotEmpty);
    expect(relay.playerCount, equals(1));

    await channel.sink.close();
  });

  test('two sockets see each other over the tick loop', () async {
    final alice = await openSocket();
    final seen = <ProtocolMessage>[];
    // Subscribe before Bob arrives, or the messages are gone by the time we
    // ask for them.
    alice.stream.listen((data) => seen.add(decodeMessage(data as String)));

    alice.sink.add(
      encodeMessage(
        const JoinMessage(
          sessionId: aliceSession,
          name: 'Alice',
          color: 0xFF54C5F8,
          cosmetic: PlayerCosmetic.cap,
        ),
      ),
    );
    await _until(() => relay.playerCount == 1);
    alice.sink.add(encodeMessage(const MoveMessage(x: 150, y: 150)));

    final bob = await openSocket();
    bob.sink.add(
      encodeMessage(
        const JoinMessage(
          sessionId: bobSession,
          name: 'Bob',
          color: 0xFF7ED9B6,
          cosmetic: PlayerCosmetic.headphones,
        ),
      ),
    );
    await _until(() => relay.playerCount == 2);
    bob.sink.add(encodeMessage(const MoveMessage(x: 160, y: 160)));

    // A snapshot naming Bob is the whole loop: his move reached the server,
    // the grid put him next to Alice, and the tick told her about him.
    await _until(
      () => seen.whereType<SnapshotMessage>().any(
        (snapshot) => snapshot.appeared.any((player) => player.name == 'Bob'),
      ),
    );
    expect(seen.first, isA<WelcomeMessage>());

    final position = seen.whereType<SnapshotMessage>().last.positions.single;
    expect(position.x, equals(160));
    expect(position.y, equals(160));

    await bob.sink.close();

    // Leaving the world is announced the moment the socket dies, not on the
    // next tick, and only to the people who could see him.
    await _until(() => seen.whereType<PlayerLeftMessage>().isNotEmpty);

    await alice.sink.close();
  });

  test('an abrupt disconnect removes the player', () async {
    // A tab that is force-killed never sends a close frame, and the client
    // API refuses to fake one (close code 1006 is reserved). So this test
    // speaks the handshake and one frame by hand over a raw TCP socket, then
    // destroys it — which is exactly what the server sees from a dead tab.
    final socket = await _rawWebSocket(server.port);
    socket.add(
      _clientFrame(
        encodeMessage(
          const JoinMessage(
            sessionId: aliceSession,
            name: 'Alice',
            color: 0xFF54C5F8,
            cosmetic: PlayerCosmetic.cap,
          ),
        ),
      ),
    );
    await socket.flush();
    await _until(() => relay.playerCount == 1);

    socket.destroy();

    await _until(() => relay.playerCount == 0);
    expect(logs.last, contains('left'));
  });
}

/// Opens a raw TCP socket and completes a WebSocket handshake on it.
Future<Socket> _rawWebSocket(int port) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  final key = base64.encode(
    List<int>.generate(16, (_) => Random().nextInt(256)),
  );
  final upgraded = Completer<void>();
  socket
    ..listen(
      (bytes) {
        if (!upgraded.isCompleted &&
            ascii.decode(bytes, allowInvalid: true).contains('101')) {
          upgraded.complete();
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    )
    ..write(
      'GET /$webSocketPath HTTP/1.1\r\n'
      'Host: 127.0.0.1:$port\r\n'
      'Upgrade: websocket\r\n'
      'Connection: Upgrade\r\n'
      'Sec-WebSocket-Key: $key\r\n'
      'Sec-WebSocket-Version: 13\r\n\r\n',
    );
  await socket.flush();
  await upgraded.future.timeout(const Duration(seconds: 2));
  return socket;
}

/// Encodes [text] as a masked client-to-server text frame.
///
/// Only the short-payload form: every message these tests send is well under
/// 126 bytes.
List<int> _clientFrame(String text) {
  final payload = utf8.encode(text);
  if (payload.length >= 126) {
    throw ArgumentError.value(text, 'text', 'too long for a short frame');
  }
  final mask = List<int>.generate(4, (_) => Random().nextInt(256));
  return [
    0x81, // FIN + text opcode
    0x80 | payload.length, // masked + length
    ...mask,
    for (var i = 0; i < payload.length; i++) payload[i] ^ mask[i % 4],
  ];
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
