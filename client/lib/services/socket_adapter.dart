import 'package:web_socket_channel/web_socket_channel.dart';

/// A bidirectional text socket, reduced to what the client actually needs.
///
/// `NetworkClient` is written against this rather than `WebSocketChannel` so
/// its logic can be tested with a fake — no server, no ports, no timing — and
/// so the one place that touches `web_socket_channel` is this file.
abstract class SocketAdapter {
  /// Completes when the socket is open, or with an error if it never opens.
  Future<void> get ready;

  /// Text frames arriving from the server.
  Stream<String> get incoming;

  /// Sends one text frame.
  void send(String data);

  /// Closes the socket.
  Future<void> close();
}

/// Opens a real WebSocket to [url].
///
/// This is the default socket factory used by `NetworkClient`; tests pass
/// their own.
SocketAdapter openWebSocket(Uri url) =>
    WebSocketAdapter(WebSocketChannel.connect(url));

/// A [SocketAdapter] backed by a real [WebSocketChannel].
class WebSocketAdapter implements SocketAdapter {
  /// Wraps an open or opening [WebSocketChannel].
  WebSocketAdapter(this._channel);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<String> get incoming =>
      // The protocol is JSON text. A binary frame is not something this
      // server sends, so it is dropped rather than guessed at.
      _channel.stream.where((frame) => frame is String).cast<String>();

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();
}
