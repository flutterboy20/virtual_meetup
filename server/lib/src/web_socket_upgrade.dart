import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Upgrades a request to a WebSocket that refuses oversized frames.
///
/// **Why this exists rather than `package:shelf_web_socket`.** That package's
/// handler does everything below and then calls
/// [WebSocket.fromUpgradedSocket] without passing `maxPayloadLength`, and
/// exposes no way to supply one. `dart:io` *does* enforce a cap when given
/// it, and enforces it in the one place that matters: the check sits in the
/// frame parser's `_lengthDone`, which runs the moment the frame's length
/// *header* has been read and before a single payload byte is buffered. A
/// frame declaring a gigabyte is refused as a protocol error while the
/// gigabyte is still on the wire.
///
/// That is the difference between this and the app-level guard in
/// `RelaySession.handleData`, which cannot be anything better than a report:
/// by the time application code sees a frame, the allocation has happened.
/// Both are kept. This one stops the frame; that one stops a frame that is
/// merely rude rather than hostile, and says so in the log.
///
/// **The global switch does not work — do not reach for it.** The SDK
/// documents `dart.io.default.ws.max.payload.length` as settable "in
/// compilation configuration environment". Measured on this SDK, `-D` on
/// `dart run` *and* on `dart compile exe` both leave the limit at its
/// unlimited default: the constant is baked into the prebuilt platform
/// snapshot, so the define never reaches `dart:_http` however it is passed.
/// Application code can read the value back and see its own define, which is
/// exactly what makes the dead end convincing. Passing the argument is the
/// only route that works.
///
/// Structure, header checks and status codes below are adapted from
/// `package:shelf_web_socket` 3.0.0 (BSD-3-Clause, © the Dart project
/// authors). Subprotocol negotiation is dropped: this server has never
/// offered one, so the code that chose between them was always choosing
/// `null`. The licence's full terms are reproduced in
/// `THIRD_PARTY_NOTICES.md` at the repository root, as that licence requires
/// of a source redistribution.
///
/// [maxFrameBytes] is the ceiling. [allowedOrigins] `null` means any origin,
/// an empty set means no browser origin at all, and a request carrying no
/// `Origin` header passes either way — see `resolveAllowedOrigins` for why
/// that last part is deliberate.
Handler webSocketUpgrade(
  void Function(WebSocketChannel channel) onConnection, {
  required int maxFrameBytes,
  Set<String>? allowedOrigins = const {},
  Duration? pingInterval,
}) {
  if (maxFrameBytes < 1) {
    throw ArgumentError.value(maxFrameBytes, 'maxFrameBytes', 'must be >= 1');
  }

  return (Request request) {
    // The order of these checks is load-bearing and matches the package this
    // replaces: a plain `GET` has to fall out as a 404, indistinguishable
    // from the route not existing, while a *malformed upgrade* has to be a
    // 400. Two tests lean on exactly that difference to prove a request
    // reached this handler at all.
    if (request.method != 'GET') return _notFound();

    final connection = request.headers['Connection'];
    if (connection == null) return _notFound();
    final tokens = connection
        .toLowerCase()
        .split(',')
        .map((token) => token.trim());
    if (!tokens.contains('upgrade')) return _notFound();

    final upgrade = request.headers['Upgrade'];
    if (upgrade == null) return _notFound();
    if (upgrade.toLowerCase() != 'websocket') return _notFound();

    final version = request.headers['Sec-WebSocket-Version'];
    if (version == null) {
      return _badRequest('missing Sec-WebSocket-Version header.');
    }
    if (version != '13') return _notFound();

    if (request.protocolVersion != '1.1') {
      return _badRequest(
        'unexpected HTTP version "${request.protocolVersion}".',
      );
    }

    final key = request.headers['Sec-WebSocket-Key'];
    if (key == null) return _badRequest('missing Sec-WebSocket-Key header.');

    if (!request.canHijack) {
      throw ArgumentError(
        'webSocketUpgrade may only be used with a server that supports '
        'request hijacking.',
      );
    }

    // A browser always sends `Origin`, so this is what stops a hostile page
    // opening sockets here through its visitors' browsers. It stops nothing
    // that sends no `Origin` at all, which is the whole of its honest value.
    final origin = request.headers['Origin'];
    if (origin != null &&
        allowedOrigins != null &&
        !allowedOrigins.contains(origin.toLowerCase())) {
      return _forbidden('invalid origin "$origin".');
    }

    // Throws `HijackException` and never returns. That is how shelf says
    // "this is a socket now", and it is what `_admitted` in `handler.dart`
    // watches for to decide whether a connection slot was actually taken.
    request.hijack((channel) {
      utf8.encoder
          .startChunkedConversion(channel.sink)
          .add(
            'HTTP/1.1 101 Switching Protocols\r\n'
            'Upgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            'Sec-WebSocket-Accept: ${WebSocketChannel.signKey(key)}\r\n'
            '\r\n',
          );

      if (channel.sink is! Socket) {
        throw ArgumentError('channel.sink must be a dart:io `Socket`.');
      }

      final socket = WebSocket.fromUpgradedSocket(
        channel.sink as Socket,
        serverSide: true,
        // The whole reason this file exists.
        maxPayloadLength: maxFrameBytes,
      )..pingInterval = pingInterval;

      onConnection(IOWebSocketChannel(socket));
    });
  };
}

Response _notFound() =>
    Response.notFound('Only WebSocket connections are supported.');

Response _badRequest(String message) => Response.badRequest(body: message);

Response _forbidden(String message) => Response.forbidden(message);
