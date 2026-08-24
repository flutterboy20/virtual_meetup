import 'dart:math';

/// Where the client is in the connect / drop / retry cycle.
///
/// This is a *lifecycle*, not a health flag, which is why it is five states
/// and not a bool. The UI needs to tell "we are between retries, sit tight"
/// apart from "we are trying right now", and the retry logic needs to know
/// whether a failure is the first one or the ninth.
enum ConnectionPhase {
  /// No socket yet, and none has been asked for.
  idle,

  /// A connection attempt is in flight.
  connecting,

  /// The socket is open.
  connected,

  /// The socket dropped and the client is waiting out a backoff delay.
  ///
  /// The deliberate pause. Two hundred phones whose wifi blinked at once,
  /// all retrying immediately and then immediately again, is a denial of
  /// service the conference performs on itself.
  waiting,

  /// A retry attempt is in flight after at least one failure.
  ///
  /// Separate from [connecting] because the first attempt is not a *re*-try:
  /// only this one means the player has already been in the world, so only
  /// this one should show a "reconnecting" indicator rather than a spinner.
  reconnecting,
}

/// Whether this phase means the client currently has a working socket.
extension ConnectionPhaseX on ConnectionPhase {
  /// Whether the socket is open right now.
  bool get isConnected => this == ConnectionPhase.connected;

  /// Whether the client is trying, or about to try, to get back in.
  ///
  /// This is the one the "reconnecting…" indicator watches: it stays lit for
  /// the whole waiting-then-attempting cycle rather than flickering once per
  /// retry.
  bool get isRecovering =>
      this == ConnectionPhase.waiting || this == ConnectionPhase.reconnecting;
}

/// How long to wait before the next attempt, and when to stop growing it.
///
/// Exponential with jitter, capped. Each piece earns its place:
///
/// - **Exponential** — a server that is down stays down for seconds or
///   minutes, so retrying every 500ms for two minutes is 240 useless
///   connections per client.
/// - **Capped** — without a cap the delay grows past the point of usefulness;
///   somebody who walks back into wifi after ten minutes should not wait
///   another ten to notice.
/// - **Jittered** — this is the one that is easy to skip and expensive to
///   skip. Without it, every client that dropped at the same moment retries
///   at the same moment, forever: the wifi blip becomes a thundering herd
///   that lands on the server in perfectly synchronised waves. Jitter smears
///   them out.
///
/// The jitter here is "equal jitter": half the computed delay, plus a random
/// amount up to the other half. That keeps a hard lower bound (so a retry
/// storm can never collapse back to zero delay) while still spreading clients
/// across the window — full jitter, `random(0, delay)`, spreads better but
/// lets an unlucky client hammer.
class ReconnectPolicy {
  /// Creates a policy.
  ///
  /// [random] is injectable so the jitter is testable; nothing else should
  /// pass it.
  ReconnectPolicy({
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 20),
    this.multiplier = 2.0,
    Random? random,
  }) : _random = random ?? Random();

  /// The delay after the first failure, before any growth.
  final Duration initialDelay;

  /// The ceiling the delay grows to and stops at.
  final Duration maxDelay;

  /// How much the delay grows per consecutive failure.
  final double multiplier;

  final Random _random;

  /// Returns the delay to wait before attempt number [attempt].
  ///
  /// [attempt] is 1 for the first retry after a drop, and counts up while
  /// retries keep failing. Anything below 1 is treated as 1 rather than
  /// throwing — a caller that has lost count should still wait.
  Duration delayFor(int attempt) {
    final steps = (attempt < 1 ? 1 : attempt) - 1;
    final grown =
        initialDelay.inMicroseconds * pow(multiplier, steps).toDouble();
    final capped = grown.clamp(
      initialDelay.inMicroseconds.toDouble(),
      maxDelay.inMicroseconds.toDouble(),
    );

    final half = capped / 2;
    return Duration(microseconds: (half + _random.nextDouble() * half).round());
  }

  /// The largest delay [delayFor] can return for [attempt], jitter included.
  ///
  /// Exposed so tests can assert the bounds without reaching into the
  /// randomness, and so a caller can reason about worst-case recovery time.
  Duration ceilingFor(int attempt) {
    final steps = (attempt < 1 ? 1 : attempt) - 1;
    final grown =
        initialDelay.inMicroseconds * pow(multiplier, steps).toDouble();
    return Duration(
      microseconds: grown
          .clamp(
            initialDelay.inMicroseconds.toDouble(),
            maxDelay.inMicroseconds.toDouble(),
          )
          .round(),
    );
  }
}

/// The reconnection state machine: what happened, and what to do next.
///
/// Deliberately pure. It owns no socket, starts no timer, and awaits nothing,
/// which is what lets a drop-fail-fail-succeed sequence be tested in
/// microseconds instead of being reproduced against a real server. The class
/// that owns the plumbing calls these methods and does what they say.
class ReconnectionMachine {
  /// Creates a machine in [ConnectionPhase.idle].
  ReconnectionMachine({ReconnectPolicy? policy})
    : policy = policy ?? ReconnectPolicy();

  /// How long each wait lasts.
  final ReconnectPolicy policy;

  ConnectionPhase _phase = ConnectionPhase.idle;
  int _attempt = 0;
  bool _hasConnected = false;

  /// The current phase.
  ConnectionPhase get phase => _phase;

  /// How many consecutive failures have happened since the last success.
  int get attempt => _attempt;

  /// Whether this machine has ever had an open socket.
  ///
  /// The difference between "connecting for the first time" and
  /// "reconnecting", which is the difference between a lobby spinner and a
  /// quiet indicator over a world the player is still standing in.
  bool get hasConnected => _hasConnected;

  /// Records that an attempt is now in flight, and returns the phase.
  ConnectionPhase beginAttempt() => _phase = _hasConnected || _attempt > 0
      ? ConnectionPhase.reconnecting
      : ConnectionPhase.connecting;

  /// Records a socket that opened successfully.
  ///
  /// Resets the backoff: the next drop starts again at the policy's initial
  /// delay, which is what makes a long session with occasional blips recover
  /// quickly each time instead of inheriting the previous outage's
  /// twenty-second delay.
  void onConnected() {
    _phase = ConnectionPhase.connected;
    _attempt = 0;
    _hasConnected = true;
  }

  /// Records that the socket dropped or an attempt failed, and returns how
  /// long to wait before trying again.
  Duration onDropped() {
    _attempt++;
    _phase = ConnectionPhase.waiting;
    return policy.delayFor(_attempt);
  }

  /// Returns the machine to [ConnectionPhase.idle], forgetting the backoff.
  ///
  /// Used when the client deliberately disconnects — leaving the world is not
  /// a failure and must not leave a retry armed.
  void reset() {
    _phase = ConnectionPhase.idle;
    _attempt = 0;
  }
}
