import 'dart:async';

import 'package:client/services/network_client.dart';
import 'package:client/services/socket_adapter.dart';
import 'package:protocol/protocol.dart';

/// A socket that never touches the network.
///
/// `NetworkClient` talks to [SocketAdapter], not to `WebSocketChannel`, which
/// is what lets every connection path — including the ones that fail — be
/// tested here with no server and no waiting.
class FakeSocket implements SocketAdapter {
  /// Creates a fake socket.
  ///
  /// Set [openError] to make the socket fail to open, standing in for a
  /// server that is not running.
  FakeSocket({this.openError});

  /// The error [ready] completes with, if any.
  final Object? openError;

  /// Everything the client sent, as raw text.
  final List<String> sent = [];

  /// Whether the client closed this socket.
  bool closed = false;

  final StreamController<String> _incoming = StreamController<String>();

  /// Everything the client sent, decoded.
  List<ProtocolMessage> get sentMessages =>
      sent.map(decodeMessage).toList(growable: false);

  @override
  Future<void> get ready =>
      openError == null ? Future<void>.value() : Future<void>.error(openError!);

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  /// Delivers [message] to the client as if the server had sent it.
  void emit(ProtocolMessage message) => emitRaw(encodeMessage(message));

  /// Delivers raw text to the client, valid or not.
  void emitRaw(String data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }

  /// Drops the connection the way a server going away does.
  void dropFromServer() {
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  /// Fails the connection the way a network error does.
  void failWith(Object error) {
    if (!_incoming.isClosed) _incoming.addError(error);
  }
}

/// A [NetworkClient] wired to a [FakeSocket], plus the socket itself.
///
/// Returned together because most tests need to poke the server side.
({NetworkClient client, FakeSocket socket}) fakeNetwork({Object? openError}) {
  final socket = FakeSocket(openError: openError);
  return (
    client: NetworkClient(
      url: Uri.parse('ws://test/ws'),
      openSocket: (_) => socket,
    ),
    socket: socket,
  );
}

/// A [NetworkClient] that gets a *fresh* [FakeSocket] on every connect.
///
/// [fakeNetwork] hands out one socket for the life of the client, which is
/// right for testing a single connection and useless for testing reconnection:
/// once that socket has been dropped its stream is closed, so the retry has
/// nothing to attach to and the client looks broken when it is not.
///
/// The returned `sockets` list grows by one per connection attempt, so a test
/// can drop `sockets.first` and then assert on what arrived at `sockets.last`.
({NetworkClient client, List<FakeSocket> sockets}) reconnectingNetwork() {
  final sockets = <FakeSocket>[];
  return (
    client: NetworkClient(
      url: Uri.parse('ws://test/ws'),
      openSocket: (_) {
        final socket = FakeSocket();
        sockets.add(socket);
        return socket;
      },
    ),
    sockets: sockets,
  );
}
