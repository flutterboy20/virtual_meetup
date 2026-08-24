import 'dart:async';

import 'package:client/core/player_identity.dart';
import 'package:client/services/network_client.dart';
import 'package:client/services/reconnect_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:protocol/protocol.dart';

/// Creates the timer that waits out one backoff delay.
///
/// Matches `Timer.new`, and exists so a test can fire the wait immediately.
/// A timer rather than a `Future.delayed` because a backoff has to be
/// *cancellable*: somebody who leaves the world during a twenty-second wait
/// must not be reconnected twenty seconds later.
typedef RetryTimerFactory = Timer Function(Duration, void Function());

/// Keeps the client connected, and re-joins as the same person when it isn't.
///
/// This is the plumbing half of the reconnection story; the decisions live in
/// [ReconnectionMachine], which owns no timers and no sockets. Splitting them
/// is what makes "drop, fail, fail, succeed" a unit test instead of an
/// afternoon of unplugging a router.
///
/// The contract with the rest of the app is deliberately small: it exposes a
/// [phase] to watch and nothing else. Nobody calls `connect` twice, nobody
/// decides when to retry, and nothing bounces the player back to the lobby —
/// a dropped socket is a temporary condition, not a screen.
class ConnectionSupervisor extends ChangeNotifier {
  /// Creates a supervisor over [network], joining as [identity].
  ///
  /// [createTimer] is injectable so tests can fire the backoff immediately
  /// instead of waiting it out.
  ConnectionSupervisor({
    required NetworkClient network,
    required PlayerIdentity identity,
    ReconnectionMachine? machine,
    RetryTimerFactory createTimer = Timer.new,
  }) : _machine = machine ?? ReconnectionMachine(),
       // Named parameters cannot be private, so none of the three below can
       // be initializing formals.
       // ignore: prefer_initializing_formals
       _network = network,
       // A named parameter cannot be private.
       // ignore: prefer_initializing_formals
       _identity = identity,
       // A named parameter cannot be private.
       // ignore: prefer_initializing_formals
       _createTimer = createTimer;

  final NetworkClient _network;
  final ReconnectionMachine _machine;
  final RetryTimerFactory _createTimer;

  PlayerIdentity _identity;
  StreamSubscription<ProtocolMessage>? _messages;
  Timer? _retry;
  bool _running = false;
  bool _stopped = false;
  JoinRejectedMessage? _rejection;

  /// Where the connection currently is in its lifecycle.
  ConnectionPhase get phase => _machine.phase;

  /// How many consecutive failed attempts have happened.
  int get attempt => _machine.attempt;

  /// The identity every join is made with.
  PlayerIdentity get identity => _identity;

  /// The rejection the server sent, if it refused this client.
  ///
  /// Not a phase: a rejection is a decision about *who you are*, not about
  /// the network, and it is the one connection failure the player has to act
  /// on — by going back to the setup screen and choosing another name.
  JoinRejectedMessage? get rejection => _rejection;

  /// Whether the server refused this client's join.
  bool get wasRejected => _rejection != null;

  /// Opens the connection and keeps it open until [stop] or dispose.
  ///
  /// Returns as soon as the first attempt has been made; the retry loop lives
  /// on past it. Calling it twice is a no-op rather than a second loop.
  Future<void> start() async {
    if (_running || _stopped) return;
    _running = true;
    _messages = _network.messages.listen(_onMessage);
    _network.status.addListener(_onStatusChanged);
    await _attempt();
  }

  /// Changes the identity future joins are made with, and rejoins now.
  ///
  /// The session id inside [identity] is expected to be the same one — that
  /// is what lets the server treat this as the same player wearing a new
  /// name rather than seating a stranger.
  Future<void> updateIdentity(PlayerIdentity identity) async {
    _identity = identity;
    _rejection = null;
    notifyListeners();
    if (_network.isConnected) _network.send(identity.toJoin());
  }

  /// Stops trying and closes the socket. The supervisor cannot be restarted.
  Future<void> stop() async {
    if (_stopped) return;
    _detach();
    notifyListeners();
  }

  @override
  void dispose() {
    // Detaches without notifying, unlike [stop]: a `notifyListeners` from
    // inside `dispose` is an assertion failure, and there is nobody left to
    // tell anyway.
    _detach();
    super.dispose();
  }

  /// Disarms the retry loop and lets go of everything it was listening to.
  void _detach() {
    _stopped = true;
    _machine.reset();
    // Cancelled, not merely abandoned. A twenty-second backoff left running
    // after the player walked out would keep this whole object — socket,
    // identity and all — alive until it fired, and then try to reconnect
    // somebody who has gone.
    _retry?.cancel();
    _retry = null;
    _network.status.removeListener(_onStatusChanged);
    // Not awaited: nothing downstream waits on the cancellation, and both
    // callers must be able to finish synchronously.
    unawaited(_messages?.cancel());
    _messages = null;
  }

  Future<void> _attempt() async {
    if (_stopped) return;
    _machine.beginAttempt();
    notifyListeners();
    await _network.connect();
  }

  void _onStatusChanged() {
    if (_stopped) return;
    switch (_network.status.value) {
      case ConnectionStatus.connected:
        _machine.onConnected();
        notifyListeners();
        // The server knows nothing about this socket, so the first thing
        // over it is who we are. On a reconnect this is the *same* session
        // id, which is what makes the server re-seat us instead of handing
        // out a new bean at a new spawn point.
        _network.send(_identity.toJoin());
      case ConnectionStatus.offline:
        // A rejection already closed this socket on purpose. Retrying would
        // be an infinite loop of being told no.
        if (_rejection != null) return;
        _backOffAndRetry();
      case ConnectionStatus.idle:
      case ConnectionStatus.connecting:
        break;
    }
  }

  void _backOffAndRetry() {
    final delay = _machine.onDropped();
    notifyListeners();
    _retry?.cancel();
    _retry = _createTimer(delay, () {
      // The world can have moved on during the wait: the player may have
      // left, or the socket may have come back on its own.
      if (_stopped || _network.isConnected) return;
      unawaited(_attempt());
    });
  }

  void _onMessage(ProtocolMessage message) {
    if (message is! JoinRejectedMessage) return;
    _rejection = message;
    notifyListeners();
  }
}
