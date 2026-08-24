/// The two ceilings on how much of this server one crowd may occupy.
///
/// Pure by design: no IO, no clock, no relay, no socket. It holds two limits
/// and a counter, and it answers questions. That is what makes it testable
/// with two integers instead of a running world, and a cap that needs two
/// relays built before it can be exercised is a cap nobody exercises.
///
/// **Two ceilings, because there are two different questions.** The central
/// fact this class exists for is that a player count cannot see a flood:
///
/// - A flood is sockets that connect and never send a `join`. Each one holds
///   a session object, a neighbour buffer and a slot in the tick walk, and
///   the player count reads zero throughout. So admission has to count
///   **sockets**, on its own, which is [maxSockets] and [tryAdmit].
/// - A full event is people who *did* join. That is [maxPlayers] and
///   [isAtPlayerCap], and it is answered at the join rather than at the
///   upgrade precisely so the person can be told why in words their client
///   can render.
///
/// The hard cap is the one an attacker meets and it refuses *before a socket
/// is allocated*, which is the only refusal that costs nothing. The soft cap
/// is the one a person meets, and it costs a socket on purpose.
///
/// Both defaults sit far above the 200–300 attendees this event expects.
/// Neither should ever fire on the day. That is the intended outcome, not a
/// sign they are pointless: a backstop that engages during normal play is set
/// wrong.
///
/// **There is deliberately no per-IP cap here, and there must not be one.**
/// FlutterCon India is a physical venue and its attendees will share one NAT
/// egress address. A per-IP limit is the one defence that would reliably lock
/// out the entire conference while leaving a distributed attacker untouched.
/// Its absence is a decision, not an oversight.
class ConnectionGate {
  /// Creates a gate.
  ///
  /// Both caps must be at least one. A cap of zero would refuse everybody,
  /// which is a configuration mistake that looks exactly like a broken
  /// server — the same reasoning `resolveNeighbourCap` already applies.
  ConnectionGate({
    this.maxSockets = defaultMaxSockets,
    this.maxPlayers = defaultMaxPlayers,
  }) {
    if (maxSockets < 1) {
      throw ArgumentError.value(maxSockets, 'maxSockets', 'must be >= 1');
    }
    if (maxPlayers < 1) {
      throw ArgumentError.value(maxPlayers, 'maxPlayers', 'must be >= 1');
    }
  }

  /// The most sockets this server will hold open at once.
  ///
  /// Eight hundred is roughly two and a half times the largest crowd the
  /// master spec plans for, which leaves room for the reconnect storm a bad
  /// wifi minute produces without ever refusing a real attendee.
  static const int defaultMaxSockets = 800;

  /// The most players this server will seat at once.
  ///
  /// Four hundred, which is above the 200–300 the event expects and below
  /// [defaultMaxSockets] — a socket exists before its player does, so the
  /// soft cap has to be reachable while sockets are still being admitted.
  static const int defaultMaxPlayers = 400;

  /// The hard cap: sockets, joined or not.
  final int maxSockets;

  /// The soft cap: seated players.
  final int maxPlayers;

  int _openSockets = 0;

  /// How many sockets are open right now.
  int get openSockets => _openSockets;

  /// Takes a socket slot if there is one, answering whether it got one.
  ///
  /// Asking is taking: there is no separate `admit`, for the same reason
  /// `EmoteLimiter.allow` has none. A caller that could check without
  /// claiming would eventually check twice and admit two.
  bool tryAdmit() {
    if (_openSockets >= maxSockets) return false;
    _openSockets++;
    return true;
  }

  /// Gives a socket slot back.
  ///
  /// Floors at zero rather than going negative. A counter that can go below
  /// zero is a counter that silently grants free slots after one stray
  /// double-release, and the cap would then be off by that much for the rest
  /// of the process — a failure mode far worse than the double-release it
  /// came from.
  void release() {
    if (_openSockets <= 0) return;
    _openSockets--;
  }

  /// Whether [players] is at or past the soft cap.
  ///
  /// **Takes** the count rather than reaching for it. That is what keeps this
  /// class pure: it never holds a relay and never asks a registry anything.
  /// Every caller already has the count in hand.
  bool isAtPlayerCap(int players) => players >= maxPlayers;
}
