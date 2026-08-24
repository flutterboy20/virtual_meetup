import 'dart:async';

import 'package:protocol/protocol.dart';
import 'package:server/src/admin_hub.dart';
import 'package:server/src/log.dart';
import 'package:server/src/map_relays.dart';
import 'package:server/src/relay.dart';
import 'package:server/src/web_socket_upgrade.dart';
import 'package:shelf/shelf.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// How often the server pings an idle socket.
///
/// A tab that is force-closed, or a phone that walks out of wifi range, never
/// sends a close frame — without a ping the socket would sit "open" forever
/// and its bean would stand in the world as a ghost. The ping's missing pong
/// is what turns an abrupt disconnect into a clean `onDone`.
const Duration socketPingInterval = Duration(seconds: 20);

/// The query parameter a client names its map with: `/ws?map=beach`.
const String mapQueryParameter = 'map';

/// Builds the handler that upgrades a request to a WebSocket and hands the
/// socket to whichever relay in [hub] the request asked for.
///
/// **Routing happens at socket-open, from the query string.** It cannot be
/// done from the `join` message: `Relay.open` runs the moment the socket
/// upgrades, before any frame has arrived, and moving that to "the first
/// join" would restructure the one class this project cannot afford to
/// destabilise.
///
/// An unknown or missing `map=` is the conference — see [MapId.fromId]. A
/// mistyped link should open the front door, not a 400.
///
/// One upgrade handler is built per map rather than one shared handler that
/// looks the map up per connection, because the upgrade hands its callback a
/// channel and no request. The lookup therefore has to happen *outside* the
/// upgrade, which is what the outer function below does.
Handler buildWebSocketHandler(
  MapRelays hub, {
  LogSink log = logLine,
  Set<String>? allowedOrigins = const {},
}) {
  final handlers = {
    for (final map in MapId.values)
      map: _relayHandler(
        hub.relayFor(map),
        log: log,
        allowedOrigins: allowedOrigins,
      ),
  };
  return (Request request) {
    final map = MapId.fromId(request.url.queryParameters[mapQueryParameter]);
    return handlers[map]!(request);
  };
}

Handler _relayHandler(
  Relay relay, {
  required LogSink log,
  Set<String>? allowedOrigins = const {},
}) {
  return webSocketUpgrade(
    (channel) {
      final session = relay.open(_ChannelConnection(channel));
      channel.stream.listen(
        session.handleData,
        onError: (Object error) {
          // An error is a disconnect with extra detail. `onDone` still
          // follows, and closing twice is a no-op, so this only logs.
          log('socket error: $error');
        },
        onDone: session.close,
        // The stream must survive one bad frame; the relay decides what to
        // drop, not the transport.
        cancelOnError: false,
      );
    },
    // See `resolveAllowedOrigins` for what this stops (a hostile web page
    // using its visitors' browsers) and what it does not (anything that sends
    // no `Origin` header at all, `tool/loadtest/` included). `null` is any
    // origin, which now only happens when somebody asks for it by name.
    allowedOrigins: allowedOrigins,
    // Enforced by `dart:io` before the payload is buffered, which is the one
    // thing the guard in `RelaySession.handleData` structurally cannot do.
    // The two numbers are the same on purpose: a frame this rejects is a
    // frame that one would have logged.
    maxFrameBytes: Relay.maxInboundFrameBytes,
    pingInterval: socketPingInterval,
  );
}

/// Builds the handler that upgrades a request to a privileged admin socket.
///
/// Structurally the same as the player one and deliberately kept separate:
/// the two endpoints hand their sockets to different objects, so there is no
/// shared branch that could route a player's frame into [AdminHub].
///
/// Opening this socket grants nothing. Every message on it is refused until
/// an `adminAuth` carrying the right token arrives, and refused again for
/// every message after that if it never does.
Handler buildAdminWebSocketHandler(
  AdminHub hub, {
  LogSink log = logLine,
  Set<String>? allowedOrigins = const {},
}) {
  return webSocketUpgrade(
    (channel) {
      final session = hub.open(_ChannelConnection(channel));
      channel.stream.listen(
        session.handleData,
        onError: (Object error) {
          log('admin socket error: $error');
        },
        onDone: session.close,
        cancelOnError: false,
      );
    },
    // The same list as the player route. The admin path bypasses the
    // *connection cap* — a moderator must be able to get in when the world is
    // full — but there is no reason for it to accept a browser origin the
    // player route would refuse.
    allowedOrigins: allowedOrigins,
    // Sixteen times the player ceiling, because an admin frame carries a
    // whole config document. The same number `AdminSession.handleData`
    // checks against, for the same reason the player pair match.
    maxFrameBytes: maxAdminFrameBytes,
    pingInterval: socketPingInterval,
  );
}

/// Adapts a [WebSocketChannel] to the relay's minimal socket interface.
class _ChannelConnection implements PlayerConnection {
  _ChannelConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  void close() => unawaited(_channel.sink.close());
}
