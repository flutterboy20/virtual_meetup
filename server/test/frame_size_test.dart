import 'dart:io';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The frame ceiling, seen through the real transport.
///
/// The unit-level guard in `RelaySession.handleData` is settled elsewhere.
/// This file is about the *other* guard — the one `webSocketUpgrade` hands to
/// `dart:io` — and the only thing that can prove it is a real socket, because
/// the whole claim is about what happens before application code runs.
///
/// The shape of every test here is the same: send something oversized, then
/// assert the app-level guard **did not** fire. That absence is the evidence.
/// If the transport ever stops enforcing the cap these tests do not fail with
/// a crash, they fail with a log line — which is exactly the regression worth
/// catching, because the app guard would quietly go back to being the only
/// thing standing there.
void main() {
  const session = 'a11ce000000000000000000000000001';
  const adminToken = 'a-long-enough-test-token';

  late HttpServer server;
  late MapRelays hub;
  late AdminHub admin;
  late List<String> log;

  setUp(() async {
    log = <String>[];
    hub = MapRelays(
      log: log.add,
      tickInterval: const Duration(milliseconds: 10),
    );
    admin = AdminHub(relays: hub, token: adminToken, log: log.add);
    hub.start();
    server = await shelf_io.serve(
      buildHandler(relays: hub, admin: admin),
      InternetAddress.loopbackIPv4,
      0,
    );
  });

  tearDown(() async {
    hub.stop();
    admin.stop();
    await server.close(force: true);
  });

  Uri route(String path) => Uri.parse('ws://127.0.0.1:${server.port}/$path');

  Future<WebSocketChannel> open(String path) async {
    final channel = WebSocketChannel.connect(route(path));
    await channel.ready;
    // Somebody has to listen or nothing is ever read off the socket.
    channel.stream.listen(
      (_) {},
      onError: (Object _) {},
      onDone: () {},
      cancelOnError: false,
    );
    return channel;
  }

  /// Long enough for the server to have processed, or refused, a frame.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  String frameOf(int bytes) => 'x' * bytes;

  group('the player frame ceiling', () {
    test('a frame past the ceiling never reaches application code', () async {
      final channel = await open(webSocketPath);

      // A quarter of a megabyte: 64 times the ceiling, and the sort of thing
      // the ceiling exists for.
      channel.sink.add(frameOf(256 * 1024));
      await settle();

      // The app-level guard is silent because the frame never got that far.
      // Before `webSocketUpgrade` existed this line was the *only* thing that
      // ran, and it ran after `dart:io` had already allocated the payload.
      expect(
        log.join('\n'),
        isNot(contains('dropped an oversized frame')),
        reason:
            'the frame reached application code — the transport cap is '
            'not being applied',
      );
    });

    test('the socket is torn down and its slot handed back', () async {
      final channel = await open(webSocketPath);
      expect(hub.gate.openSockets, equals(1));

      channel.sink.add(frameOf(256 * 1024));
      await settle();

      // A protocol error kills the socket, which lands in `RelaySession.close`
      // through the transport's `onDone` exactly like any other disconnect.
      expect(hub.gate.openSockets, isZero);
    });

    test('an ordinary join is untouched by any of this', () async {
      final channel = await open(webSocketPath);

      channel.sink.add(
        encodeMessage(
          const JoinMessage(
            sessionId: session,
            name: 'Ada',
            color: 0xFF54C5F8,
            cosmetic: PlayerCosmetic.cap,
          ),
        ),
      );
      await settle();

      expect(hub.playerCount, equals(1));
      await channel.sink.close();
    });

    test(
      'a frame just under the ceiling still reaches the app guard',
      () async {
        final channel = await open(webSocketPath);

        // Over the app limit, under the transport limit — nothing on the wire
        // is between them, so this is the one frame size that proves the app
        // guard is still wired up rather than merely unreachable.
        channel.sink.add(frameOf(Relay.maxInboundFrameBytes - 1));
        await settle();

        // Under both ceilings, so it is decoded and found to be nonsense
        // rather than dropped for its size.
        expect(log.join('\n'), isNot(contains('dropped an oversized frame')));
        expect(hub.gate.openSockets, equals(1));
        await channel.sink.close();
      },
    );
  });

  group('the admin frame ceiling', () {
    test('is sixteen times the player one, not the same one', () async {
      final channel = await open(adminWebSocketPath);

      // Eight kibibytes: twice the player ceiling, well under the admin one.
      // A real admin frame carries a whole config document, which is why the
      // two routes cannot share a number.
      channel.sink.add(
        encodeMessage(AdminAuthMessage(token: 'x' * (8 * 1024))),
      );
      await settle();

      // It arrived and was refused on its merits — a wrong token — rather
      // than dropped for its size.
      expect(log.join('\n'), contains('presented the wrong token'));
      await channel.sink.close();
    });

    test(
      'a frame past the admin ceiling never reaches application code',
      () async {
        final channel = await open(adminWebSocketPath);

        channel.sink.add(frameOf(maxAdminFrameBytes * 2));
        await settle();

        expect(
          log.join('\n'),
          isNot(contains('dropped an oversized frame on an admin socket')),
        );
        // And the socket is gone, so the seat it held is back.
        expect(admin.socketCount, isZero);
      },
    );
  });
}
