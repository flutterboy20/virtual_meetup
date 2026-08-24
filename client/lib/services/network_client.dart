import 'dart:async';
import 'dart:developer' as developer;

import 'package:client/core/server_endpoint.dart';
import 'package:client/services/socket_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:protocol/protocol.dart';

/// Where the client is in its connection lifecycle.
enum ConnectionStatus {
  /// Nothing has been attempted yet.
  idle,

  /// A socket is being opened.
  connecting,

  /// The socket is open and messages can flow.
  connected,

  /// The socket was never opened, or has since dropped.
  ///
  /// Not an error state as far as the UI is concerned: the world keeps
  /// running with only your own bean in it. Reconnecting is Phase 4.
  offline,
}

/// Opens a socket to [url].
typedef SocketFactory = SocketAdapter Function(Uri url);

/// The client's one connection to the relay server.
///
/// Framework-agnostic on purpose: no Flame, no widgets, no game types. It
/// turns a socket into a stream of decoded [ProtocolMessage]s and takes
/// messages back the other way, and that is all it knows about.
///
/// Every failure path here is soft. A server that is down, a socket that
/// drops mid-session, a frame that will not decode — none of them may throw
/// into the game loop or put an error screen in front of a conference
/// attendee.
class NetworkClient {
  /// Creates a client pointed at [url], defaulting to the configured server.
  NetworkClient({Uri? url, SocketFactory openSocket = openWebSocket})
    : url = url ?? resolveServerUri(),
      // A named parameter cannot be private, so this cannot be an
      // initializing formal.
      // ignore: prefer_initializing_formals
      _openSocket = openSocket;

  /// The endpoint this client connects to.
  final Uri url;

  final SocketFactory _openSocket;
  final StreamController<ProtocolMessage> _messages =
      StreamController<ProtocolMessage>.broadcast();
  final ValueNotifier<ConnectionStatus> _status = ValueNotifier(
    ConnectionStatus.idle,
  );

  SocketAdapter? _socket;

  // Cancelled in `_teardown`, which every close path goes through; the lint
  // only recognises a cancel in the same function.
  // ignore: cancel_subscriptions
  StreamSubscription<String>? _subscription;
  bool _disposed = false;

  /// Decoded messages from the server.
  ///
  /// A broadcast stream: the game layer listens, and a future HUD may want to
  /// as well. Messages that arrive before anyone listens are dropped, which
  /// is correct — this is live state, not a queue.
  Stream<ProtocolMessage> get messages => _messages.stream;

  /// The current connection lifecycle state, for the UI to watch.
  ValueListenable<ConnectionStatus> get status => _status;

  /// Whether the socket is currently open.
  bool get isConnected => _status.value == ConnectionStatus.connected;

  /// Opens the socket. Never throws; failure just leaves the client offline.
  Future<void> connect() async {
    if (_disposed || _status.value == ConnectionStatus.connecting) return;
    await _teardown();

    _status.value = ConnectionStatus.connecting;
    try {
      final socket = _openSocket(url);
      _socket = socket;
      await socket.ready;
      if (_disposed) {
        await socket.close();
        return;
      }
      _subscription = socket.incoming.listen(
        _handleFrame,
        onError: (Object error) => _handleDrop('socket error: $error'),
        onDone: () => _handleDrop('socket closed by the server'),
        // One bad frame must not tear down the connection.
        cancelOnError: false,
      );
      _status.value = ConnectionStatus.connected;
      _log('connected to $url');
    } on Object catch (error) {
      // A server that is not running is the normal case in development, and
      // a real possibility at the conference. It is not an exception the app
      // should propagate.
      _handleDrop('could not connect to $url: $error');
    }
  }

  /// Sends [message], or drops it if the socket is not open.
  ///
  /// Dropping is deliberate: positions are sent ten times a second, so a
  /// queue of stale ones would be worse than nothing to send.
  void send(ProtocolMessage message) {
    final socket = _socket;
    if (socket == null || !isConnected) return;
    try {
      socket.send(encodeMessage(message));
    } on Object catch (error) {
      _handleDrop('send failed: $error');
    }
  }

  /// Closes the socket but leaves this client usable.
  ///
  /// The difference from [dispose] is whether you intend to come back.
  /// Disposing tears down the message stream and the status notifier, so a
  /// later [connect] would be operating on dead objects; this only drops the
  /// socket, and the next [connect] opens a fresh one.
  ///
  /// Exists for the moderation screen's lock button: locking has to end the
  /// privileged session immediately, and then let the same screen be
  /// unlocked again without being rebuilt.
  Future<void> disconnect() async {
    if (_disposed) return;
    await _teardown();
    // Re-checked after the await: a screen can be torn down while this is in
    // flight, and disposing the client in between would leave this line
    // writing to a disposed notifier.
    if (_disposed) return;
    _status.value = ConnectionStatus.offline;
  }

  /// Closes the socket and releases everything this client owns.
  Future<void> dispose() async {
    _disposed = true;
    await _teardown();
    await _messages.close();
    _status.dispose();
  }

  void _handleFrame(String frame) {
    final message = decodeMessage(frame);
    if (message is UnknownMessage) {
      // Forward compatibility: a message from a newer server is dropped, not
      // fatal.
      _log('dropped an unreadable message: $message');
      return;
    }
    if (!_messages.isClosed) _messages.add(message);
  }

  void _handleDrop(String reason) {
    if (_status.value != ConnectionStatus.offline) _log(reason);
    _status.value = ConnectionStatus.offline;
    unawaited(_teardown());
  }

  Future<void> _teardown() async {
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    await subscription?.cancel();
    try {
      await socket?.close();
    } on Object catch (_) {
      // Closing an already-dead socket is not worth reporting.
    }
  }

  void _log(String message) =>
      developer.log(message, name: 'network', level: 800);
}
