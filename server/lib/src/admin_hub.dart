import 'dart:async';

import 'package:protocol/protocol.dart';
import 'package:server/src/config_store.dart';
import 'package:server/src/log.dart';
import 'package:server/src/map_relays.dart';
import 'package:server/src/relay.dart';
import 'package:server/src/token_bucket.dart';

/// How often a connected admin is pushed a fresh player list.
///
/// Once a second, not fifteen times: an admin list is read by a human with a
/// thumb, and a list that reorders under that thumb is worse than one that is
/// a second stale. It is also the one uncalled, whole-world message in the
/// server, so its cost is `admins × players` — cheap only because there is
/// one admin, and it stays cheap because this number is low.
const Duration defaultAdminListInterval = Duration(seconds: 1);

/// How many wrong tokens one admin socket may present before it is closed.
///
/// The constant-time compare in `AdminHub._isValidToken` is correct and stops
/// the secret leaking through timing. What it cannot do is stop somebody
/// *guessing*, and before Phase 13 nothing counted the guesses: a socket could
/// present tokens for as long as it stayed open.
///
/// Five, because the number only has to be low enough that guessing over a
/// socket is pointless — closing the socket costs an attacker a full TCP and
/// WebSocket handshake per five attempts, and the socket cap limits how many
/// they can have open at once. It is not a lockout: reconnecting is allowed,
/// deliberately, because the alternative locks out the one moderator at the
/// worst possible moment.
///
/// Token *length* is still the only entropy rule the server can enforce
/// (`minAdminTokenLength` is 16, so sixteen a's passes). This is what makes
/// that survivable. Generating a genuinely random token is a deploy-time
/// instruction, not something code can check.
const int maxAdminAuthFailures = 5;

/// The most admin sockets this server will hold open at once.
///
/// **The admin route is deliberately not behind `ConnectionGate`, and that is
/// what makes this necessary.** `buildHandler` lets an admin upgrade through
/// even when the player cap is full, because the moment the world is full is
/// the moment a moderator most needs to get in — a defence that locks out the
/// person who came to stop the flood is a defence that disarms itself. The
/// cost of that bypass is that the admin path had no ceiling of its own, so
/// the same idle sockets the player cap refuses could be pointed at `/admin`
/// without limit.
///
/// Five, because the honest number is one. There is one moderator at this
/// event; the spare four exist only so a phone, a laptop and a reconnect that
/// has not timed out yet can coexist without anybody being locked out by
/// their own second tab.
const int maxAdminSockets = 5;

/// How many admin sockets may be *unauthenticated* at once.
///
/// One below [maxAdminSockets], and the gap is the whole point: it is a seat
/// held back for a moderator who can prove who they are. Without it a flood
/// of five silent sockets would fill the admin cap and the refusal would land
/// on the one person the endpoint exists for.
///
/// The reservation is enforced by *eviction*, not refusal — see
/// `AdminHub.open`. Refusing the newcomer would be the wrong way round: the
/// newcomer might be the moderator, and the sockets already sitting there
/// silently are the ones that have proved nothing.
const int maxUnauthenticatedAdminSockets = maxAdminSockets - 1;

/// How long an admin socket may sit unauthenticated before it is closed.
///
/// The same reasoning as `Relay.defaultJoinDeadline`, against the same
/// attack: a cap decides who is refused next, and only a deadline gives a
/// slot back. [maxAdminSockets] bounds how many idle admin sockets can exist;
/// this is what stops them existing indefinitely.
///
/// Fifteen seconds is generous for a screen where the token is pasted, not
/// typed — the client sends `adminAuth` as soon as it has one — and a
/// moderator who is locked out by it only has to reconnect, which the client
/// does for them.
const Duration adminAuthDeadline = Duration(seconds: 15);

/// The largest inbound frame an *admin* socket may send, in bytes.
///
/// Sixteen times the player ceiling, because an admin frame has to carry a
/// whole config document. Kept deliberately above [maxConfigDocumentBytes] so
/// that a too-large paste is answered by the config store with a sentence
/// rather than dropped in silence by this guard.
const int maxAdminFrameBytes = 64 * 1024;

/// The privileged endpoint: everything that can moderate the world.
///
/// Deliberately a **separate hub on a separate path** from the player relay,
/// rather than a flag on a player session. Two reasons, and the second is the
/// one that matters:
///
/// - The relay stays a relay. It has no concept of an admin, so no future
///   change to the tick loop can accidentally grant one.
/// - A player socket has no code path that could act on an admin message, so
///   the interesting attack — "send a kick down the socket I already have" —
///   is not defended against, it is *absent*. Defence you cannot forget to
///   apply beats defence you have to remember.
///
/// Authorization is checked in exactly one place, `AdminSession._handle`, on
/// every single message, every time. Not once at connect, and never inferred
/// from the fact that a socket got this far.
class AdminHub {
  /// Creates a hub over every relay in [relays].
  ///
  /// Takes the whole [MapRelays] rather than one [Relay] because **moderation
  /// is global**. A moderator watching a roster is watching the event, not a
  /// room; a person who moves to the beach to get away from one has not got
  /// away from anything. The roster is therefore the union across maps, and
  /// every action searches every map for its target.
  ///
  /// That search is safe precisely because of the evict-on-join rule in
  /// [MapRelays]: a session is seated in exactly one registry at a time, so
  /// "find the player with this id" has exactly one answer.
  ///
  /// [token] is the shared secret from the server's environment. A `null`
  /// token means admin is **switched off**: every message on every admin
  /// socket is refused. That is the safe default for a deployment that forgot
  /// to set the variable — no moderation is a bad day, unauthenticated
  /// moderation is a much worse one.
  AdminHub({
    required MapRelays relays,
    required String? token,
    LogSink log = logLine,
    SecurityLog? securityLog,
    this.listInterval = defaultAdminListInterval,
    this.authDeadline = adminAuthDeadline,
  }) : // Wraps the same sink the operational lines go to, so a test that
       // captures `log` still sees these — just no longer without limit.
       _security = securityLog ?? SecurityLog(log: log),
       // Named parameters cannot be private, so none of these can be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _relays = relays,
       // A named parameter cannot be private.
       // ignore: prefer_initializing_formals
       _token = token,
       // A named parameter cannot be private. No ignore needed here any more:
       // `log` now feeds two fields, so the lint does not fire.
       _log = log;

  final MapRelays _relays;
  final String? _token;
  final LogSink _log;

  /// Where every line an *unauthenticated* socket can trigger goes.
  ///
  /// The admin endpoint needs this more than the player one, not less: these
  /// frames are handled before the token is checked, so anybody who can reach
  /// the port can drive these lines. See [SecurityLog].
  final SecurityLog _security;

  /// How often connected admins are pushed a fresh player list.
  final Duration listInterval;

  /// How long a socket has to authenticate before it is closed.
  final Duration authDeadline;

  final Set<AdminSession> _sessions = {};

  Timer? _listTimer;

  /// Whether a token was configured at all.
  ///
  /// Exposed so startup can say so out loud. It reveals nothing: that a
  /// server has moderation is not a secret, the token is.
  bool get isEnabled => _token != null;

  /// How many admin sockets are currently authorised.
  int get authorizedCount =>
      _sessions.where((session) => session.isAuthorized).length;

  /// How many admin sockets are open, authorised or not.
  int get socketCount => _sessions.length;

  /// How many admin sockets have not proved anything yet.
  int get unauthorizedCount => _sessions.length - authorizedCount;

  /// Starts pushing player lists to authorised admins.
  void start() {
    _listTimer ??= Timer.periodic(listInterval, (_) {
      broadcastPlayerList();
      broadcastBanList();
    });
  }

  /// Stops pushing player lists. Sockets stay open.
  void stop() {
    _listTimer?.cancel();
    _listTimer = null;
  }

  /// Starts a session for a freshly opened admin socket.
  ///
  /// The socket is *not* privileged yet, and will not be until an
  /// [AdminAuthMessage] with the right token arrives on it.
  AdminSession open(PlayerConnection connection) {
    final session = AdminSession(this, connection);
    if (!_makeRoom()) {
      // Every seat is held by somebody who proved who they are, so there is
      // nobody to evict and no reservation left to honour. Told in words
      // rather than dropped, because the only person who can reach this is a
      // moderator with the token open on a sixth screen.
      _log('refused an admin socket: $maxAdminSockets authorised already');
      session._refuse(
        'This server already has $maxAdminSockets moderator sessions open. '
        'Close one and try again.',
      );
      return session;
    }
    _sessions.add(session);
    _log('admin socket opened (${_sessions.length} open)');
    return session;
  }

  /// Frees a place for one incoming socket, answering whether there is one.
  ///
  /// **Evicts rather than refuses, and evicts the oldest silent socket.**
  /// Every socket arrives unauthenticated, so a plain "refuse when full"
  /// would hand the refusal to whoever knocked last — and at the only moment
  /// this matters, that is the moderator arriving to find five silent sockets
  /// squatting the endpoint. Turning it around costs an attacker their oldest
  /// connection for every new one they open, and costs a moderator nothing.
  ///
  /// Terminating an authorised session is never on the table: those are real
  /// people, and the sixth of them is refused instead.
  bool _makeRoom() {
    // Both ceilings, because they answer different questions: the first is
    // how much of this server the admin route may occupy at all, the second
    // is how much of it may be occupied by strangers.
    while (_sessions.length >= maxAdminSockets ||
        unauthorizedCount >= maxUnauthenticatedAdminSockets) {
      final oldest = _oldestUnauthorized();
      if (oldest == null) return false;
      _log('evicted the oldest unauthenticated admin socket to make room');
      // Removes itself from `_sessions` on the way out, through `_forget`,
      // which is what lets this loop terminate.
      oldest._terminate();
    }
    return true;
  }

  /// The unauthenticated session that has been sitting here longest.
  ///
  /// Insertion order, which `_sessions` keeps because a Dart `Set` literal is
  /// a `LinkedHashSet`. Oldest-first is the half of the rule that makes the
  /// eviction fair: a socket that has been silent for fourteen seconds is a
  /// better guess at "not a moderator" than one that arrived a moment ago.
  AdminSession? _oldestUnauthorized() {
    for (final session in _sessions) {
      if (!session.isAuthorized) return session;
    }
    return null;
  }

  /// Sends every authorised admin the current player list.
  ///
  /// Public so tests can step it without a timer.
  void broadcastPlayerList() {
    if (_sessions.isEmpty) return;
    final authorized = _sessions
        .where((session) => session.isAuthorized)
        .toList(growable: false);
    if (authorized.isEmpty) return;

    final players = _relays.adminPlayerList();
    final encoded = encodeMessage(
      AdminPlayerListMessage(
        players: players,
        online: players.length,
        onlineByMap: {
          for (final entry in _relays.countsByMap.entries)
            entry.key: entry.value,
        },
      ),
    );
    for (final session in authorized) {
      session._sendRaw(encoded);
    }
  }

  /// Sends every authorised admin every ban in force.
  ///
  /// Its own broadcast rather than a field on the player list, for the same
  /// reason the config is: the two answer opposite questions. That one is who
  /// is *in* the world, and a banned person is by definition not.
  ///
  /// Public so tests can step it without a timer, like the list beside it.
  void broadcastBanList() {
    final encoded = encodeMessage(
      AdminBanListMessage(bans: _relays.moderation.bans),
    );
    for (final session in _sessions) {
      if (session.isAuthorized) session._sendRaw(encoded);
    }
  }

  /// Sends every authorised admin the current config.
  ///
  /// Its own broadcast rather than a field on the player list, because the
  /// two change on completely different schedules: the list is pushed every
  /// second and this is pushed when somebody edits it.
  void broadcastConfig() {
    final encoded = encodeMessage(_relays.config.message);
    for (final session in _sessions) {
      if (session.isAuthorized) session._sendRaw(encoded);
    }
  }

  /// Whether [candidate] is the configured token.
  ///
  /// Compares every character even after a mismatch. A short-circuiting
  /// comparison leaks the length of the matching prefix through timing, which
  /// over a lot of attempts is enough to recover a secret one character at a
  /// time. The cost of not leaking it is a loop over ~32 characters.
  bool _isValidToken(String candidate) {
    final token = _token;
    if (token == null) return false;
    if (candidate.length != token.length) return false;

    var difference = 0;
    for (var i = 0; i < token.length; i++) {
      difference |= token.codeUnitAt(i) ^ candidate.codeUnitAt(i);
    }
    return difference == 0;
  }

  /// Runs [act] against whichever relay [playerId] is standing on.
  ///
  /// `null` when nobody anywhere has that id, which the caller turns into
  /// `unknownPlayer` — normally a row that was tapped a second after its
  /// player left, and now also a row that was tapped while they were mid
  /// map-switch.
  ModerationOutcome? _act(
    String playerId,
    ModerationOutcome? Function(Relay relay) act,
  ) {
    final relay = _relays.relayOf(playerId);
    return relay == null ? null : act(relay);
  }

  void _forget(AdminSession session) {
    if (!_sessions.remove(session)) return;
    _log('admin socket closed (${_sessions.length} open)');
  }
}

/// One admin socket, and whether it has proved it may moderate.
class AdminSession {
  /// Creates a session, and starts the clock on its `adminAuth`.
  ///
  /// Armed here rather than on the first frame, because the socket this
  /// exists to close is one that never sends a frame at all.
  AdminSession(this._hub, this._connection) {
    _authTimer = Timer(_hub.authDeadline, _authDeadlinePassed);
  }

  final AdminHub _hub;
  final PlayerConnection _connection;

  bool _authorized = false;
  bool _closed = false;

  /// Closes this socket if it is still anonymous when the deadline is up.
  ///
  /// Cancelled on a successful auth and on close, so an authorised moderator
  /// never carries a live timer for the rest of their session.
  Timer? _authTimer;

  /// How many wrong tokens this socket has presented.
  ///
  /// Per socket, not per hub: a shared counter would let one attacker's
  /// guesses lock out the moderator, which is the failure this throttle must
  /// not create.
  int _authFailures = 0;

  /// Whether this socket has presented the right token.
  bool get isAuthorized => _authorized;

  /// This socket's share of the server's inbound budget.
  ///
  /// The same guard the player sockets got, at the same burst and refill. An
  /// admin socket is behind a token, but the frames arrive *before* the token
  /// is checked — an unauthenticated socket can send as fast as it likes —
  /// so the rate limit has to sit in front of the auth, not behind it.
  final TokenBucket _inbound = TokenBucket(
    burst: Relay.defaultInboundBurst,
    refill: Relay.defaultInboundRefill,
  );

  /// Handles one inbound frame. Never throws.
  void handleData(Object? data) {
    if (_closed) return;
    if (data is! String) {
      _hub._security.write('dropped a non-text frame on an admin socket');
      return;
    }

    // Size, then rate, then decode — the same order, and for the same reason,
    // as `RelaySession.handleData`.
    //
    // Sixteen times the player ceiling because an admin frame has to carry a
    // whole config document. That document is capped at
    // [maxConfigDocumentBytes], which is *below* this on purpose: a paste
    // that is merely too big gets a sentence from the config store, and only
    // something far beyond any plausible document is dropped in silence here.
    if (data.length > maxAdminFrameBytes) {
      _hub._security.write('dropped an oversized frame on an admin socket');
      return;
    }
    if (!_inbound.allow()) return;

    _handle(decodeMessage(data));
  }

  /// Handles the socket closing, cleanly or abruptly.
  void close() {
    if (_closed) return;
    _closed = true;
    _authorized = false;
    _cancelAuthDeadline();
    _hub._forget(this);
  }

  /// Stops the auth deadline, whether or not it was ever going to fire.
  void _cancelAuthDeadline() {
    _authTimer?.cancel();
    _authTimer = null;
  }

  /// Closes a socket that connected to the admin route and never said who it
  /// was.
  ///
  /// Re-checks rather than trusting the timer, for the same reason
  /// `RelaySession._joinDeadlinePassed` does: the token may have landed
  /// between the timer firing and this running, and closing a moderator's
  /// socket one millisecond after they authenticated would be a worse bug
  /// than the one this closes.
  void _authDeadlinePassed() {
    _authTimer = null;
    if (_closed || _authorized) return;
    _hub._log(
      'closed an admin socket that never authenticated after '
      '${_hub.authDeadline.inSeconds}s',
    );
    _terminate();
  }

  /// Turns this socket away before it is ever put on the hub's books.
  ///
  /// Says why first, then closes. A socket refused here was never added to
  /// `_sessions`, so the `_forget` behind [close] finds nothing to remove and
  /// logs nothing — which is right: nothing was ever opened.
  void _refuse(String detail) {
    _send(AdminAuthResultMessage(authorized: false, detail: detail));
    _terminate();
  }

  /// The one authorization gate in the server.
  ///
  /// Every privileged branch re-reads [_authorized]. That looks repetitive
  /// next to a single check at the top, and the repetition is the point: a
  /// later message type added below cannot inherit a check it never ran, and
  /// there is no "we already validated this connection" state anywhere for a
  /// bug to leave set.
  void _handle(ProtocolMessage message) {
    switch (message) {
      case AdminAuthMessage():
        _handleAuth(message);

      case AdminKickMessage():
        if (!_requireAuthorized(message)) return;
        _report(
          AdminAction.kick,
          message.playerId,
          (id) => _hub._act(id, (relay) => relay.kick(id)),
        );

      case AdminBanMessage():
        if (!_requireAuthorized(message)) return;
        _report(
          AdminAction.ban,
          message.playerId,
          (id) => _hub._act(id, (relay) => relay.ban(id)),
        );
        // The list the moderator is looking at just grew a row.
        _hub.broadcastBanList();

      case AdminUnbanMessage():
        if (!_requireAuthorized(message)) return;
        _handleUnban(message);

      case AdminSetConfigMessage():
        if (!_requireAuthorized(message)) return;
        _handleSetConfig(message);

      case AdminSetMaintenanceMessage():
        if (!_requireAuthorized(message)) return;
        _handleSetMaintenance(message);

      case AdminMuteNameMessage():
        if (!_requireAuthorized(message)) return;
        _report(
          message.muted ? AdminAction.muteName : AdminAction.unmuteName,
          message.playerId,
          (id) => _hub._act(
            id,
            (relay) => relay.setNameMuted(id, muted: message.muted),
          ),
        );

      case UnknownMessage():
        // Clipped by `UnknownMessage.toString` and capped by the sink: this
        // line carries a stranger's text, and on this endpoint the stranger
        // has not authenticated yet.
        _hub._security.write('dropped an unreadable admin message: $message');

      case JoinMessage():
      case MoveMessage():
      case EmoteMessage():
      case BoardMessage():
      case PlayerBoardMessage():
      case PlayerRenamedMessage():
      case WelcomeMessage():
      case SnapshotMessage():
      case PlayerLeftMessage():
      case JoinRejectedMessage():
      case PlayerEmotedMessage():
      case WorldStatsMessage():
      case AdminAuthResultMessage():
      case AdminPlayerListMessage():
      case AdminBanListMessage():
      case AdminActionResultMessage():
      case AdminErrorMessage():
      case ConfigMessage():
        // Not an admin request. This endpoint moderates and does nothing
        // else — an admin socket is not a second way into the world, so a
        // `join` here is refused rather than quietly seating somebody
        // outside the relay's accounting.
        _send(
          const AdminErrorMessage(
            reason: AdminError.badRequest,
            detail: 'That is not an admin request.',
          ),
        );
    }
  }

  void _handleAuth(AdminAuthMessage auth) {
    if (!_hub.isEnabled) {
      // Said plainly, because the person typing is the operator and a
      // silent refusal would send them hunting for a typo in a token the
      // server was never given. It tells an attacker only that moderation
      // is off, which does not help them do anything.
      _authorized = false;
      // Security sink: unlike a wrong token, this path never increments
      // `_authFailures`, so nothing closes the socket and nothing else caps
      // how often an unauthenticated stranger can ask.
      _hub._security.write(
        'an admin tried to authenticate but no token is configured',
      );
      _send(
        const AdminAuthResultMessage(
          authorized: false,
          detail: 'Moderation is not configured on this server.',
        ),
      );
      return;
    }

    if (!_hub._isValidToken(auth.token)) {
      // The flag is cleared, not left alone: a wrong token on an already
      // authorised socket drops it back out. There is no way to *lose*
      // privilege by accident, so there must be no way to keep it by
      // accident either.
      _authorized = false;
      _authFailures++;
      // Never the token, not even a prefix of it, and not the length.
      _hub._log(
        'an admin presented the wrong token '
        '($_authFailures of $maxAdminAuthFailures)',
      );
      // Answered before the socket goes, so a moderator who genuinely
      // fat-fingered it five times sees why their screen went blank rather
      // than watching the connection die with no explanation.
      _send(
        const AdminAuthResultMessage(
          authorized: false,
          detail: 'That token was not accepted.',
        ),
      );
      if (_authFailures >= maxAdminAuthFailures) {
        _hub._log('closed an admin socket after $_authFailures bad tokens');
        _terminate();
      }
      return;
    }

    // Reset on success, so a moderator who mistypes twice and then gets it
    // right does not carry two strikes for the life of the socket.
    _authFailures = 0;
    _authorized = true;
    // Proved, so the deadline that exists to close strangers is done.
    _cancelAuthDeadline();
    _hub._log('an admin authenticated (${_hub.authorizedCount} authorised)');
    _send(
      const AdminAuthResultMessage(
        authorized: true,
        detail: 'Authenticated.',
      ),
    );
    _hub
      // Straight away rather than at the next tick: the screen behind this
      // is a list, and a second of blankness after typing a token reads as a
      // failure.
      ..broadcastPlayerList()
      // And the config, so the editor opens on what is live rather than on
      // an empty box somebody might mistake for an empty config.
      ..broadcastConfig()
      // And the bans, for the same reason: a tab that reads "nobody is
      // banned" until the first timer tick is a tab that has lied.
      ..broadcastBanList();
  }

  /// Replaces the event's config, or explains why it did not.
  ///
  /// The **only** message in the protocol that changes what everybody sees at
  /// once, so it is the only one where being told "no" matters more than
  /// being told "yes": a moderator whose paste had a trailing comma in it
  /// needs to know that in the next second, not from the room.
  ///
  /// On success every player on every map is handed the new config
  /// immediately, and so is every connected admin — including this one, which
  /// is how the editor ends up showing what the server actually parsed rather
  /// than what was typed at it.
  void _handleSetConfig(AdminSetConfigMessage message) {
    // Asked here as well as inside the store, and the duplication is on
    // purpose. `ConfigStore.apply` is the *enforcer* — it refuses an
    // oversized document however it arrives — but it answers with a bare
    // `null`, which is also what "that is not JSON" looks like. This is the
    // screen where somebody is standing there waiting to be told what they
    // did wrong, so the two refusals get two different sentences.
    if (message.document.length > maxConfigDocumentBytes) {
      _hub._log('an admin pushed a config document that is too large');
      _send(
        AdminErrorMessage(
          reason: AdminError.badRequest,
          detail:
              'That document is ${message.document.length} characters; the '
              'limit is $maxConfigDocumentBytes. Nothing was changed.',
        ),
      );
      return;
    }

    final applied = _hub._relays.config.apply(message.document);
    if (applied == null) {
      _hub._log('an admin pushed a config that is not JSON');
      _send(
        const AdminErrorMessage(
          reason: AdminError.badRequest,
          detail: 'That is not a JSON object. Nothing was changed.',
        ),
      );
      return;
    }

    _hub._log('an admin replaced the event config');
    _hub._relays.broadcastConfig();
    _hub.broadcastConfig();
    // A document may close the event as surely as the maintenance card does
    // — the field is right there in the editor. Enforcement therefore hangs
    // off the *state* the config is now in, not off which message put it
    // there, so the two routes cannot drift apart.
    _enforceMaintenance(applied);
  }

  /// Closes the event until a stated moment, or opens it again.
  ///
  /// **Re-checks the token**, on a socket that is already authorised. That is
  /// not belt and braces: it is the difference between "this socket was
  /// authorised once" and "the person holding this phone, right now, meant
  /// to close the event". Every other admin action costs one attendee their
  /// connection; this one costs all of them, and a phone left unlocked on a
  /// table is a much likelier attacker than anybody on the network.
  ///
  /// A failed re-check does **not** drop the socket's privilege, unlike a
  /// failed [AdminAuthMessage]. Mistyping a password into a confirmation
  /// dialog is an ordinary slip, and throwing a moderator back to the token
  /// screen mid-incident would punish the wrong thing.
  void _handleSetMaintenance(AdminSetMaintenanceMessage message) {
    if (!_hub._isValidToken(message.token)) {
      // **Deliberately not counted against [maxAdminAuthFailures].** This
      // check and the one in `_handleAuth` call the same function and are
      // answering different questions, and without this comment the next
      // reader will "fix" the inconsistency.
      //
      // The doc above argues — correctly — that mistyping a password into a
      // confirmation dialog is an ordinary slip, and that throwing a
      // moderator back to the token screen mid-incident punishes the wrong
      // thing. Throttling it would be worse still: it would end the session
      // outright, during the one action a moderator takes when something has
      // already gone wrong. A socket that reaches this line has *already*
      // proved it holds the token, so there is no guessing to throttle.
      _hub._log('an admin failed the maintenance token re-check');
      _send(
        const AdminErrorMessage(
          reason: AdminError.unauthorized,
          detail: 'That token was not accepted. Nothing was changed.',
        ),
      );
      return;
    }

    final until = message.until;
    if (until != null && !until.isAfter(DateTime.now().toUtc())) {
      // Refused rather than clamped. "Closed until a moment that has already
      // gone" is not a window, and quietly turning it into "not closed at
      // all" would answer a tap with the opposite of what it asked for.
      _send(
        const AdminErrorMessage(
          reason: AdminError.badRequest,
          detail: 'That time has already passed. Nothing was changed.',
        ),
      );
      return;
    }

    final applied = _hub._relays.config.setMaintenanceUntil(
      until,
      message: message.message,
      showTimer: message.showTimer,
    );
    _hub._log(
      until == null
          ? 'an admin reopened the event'
          : 'an admin closed the event until ${until.toIso8601String()}',
    );
    // Told before they are disconnected, so a client that is listening knows
    // *why* its socket is about to die rather than treating it as a blip and
    // reconnecting into a refusal it has no words for.
    _hub._relays.broadcastConfig();
    _hub.broadcastConfig();
    _enforceMaintenance(applied);

    final action = until == null
        ? AdminAction.maintenanceOff
        : AdminAction.maintenanceOn;
    // The audit trail's "target" is the event itself. An id and a name are
    // the wrong shape for an action that has no victim, and inventing a
    // player-looking id for it would be worse than saying so plainly.
    _hub._relays.audit.record(
      action: action,
      targetId: 'event',
      targetName: until?.toIso8601String() ?? 'open',
    );
    _send(
      AdminActionResultMessage(
        action: action,
        targetId: 'event',
        targetName: until?.toIso8601String() ?? 'open',
      ),
    );
  }

  /// Empties the world when [config] says it is closed.
  ///
  /// Derived from the config rather than from the message that changed it,
  /// which is what makes hand-editing `maintenanceUntil` in the document
  /// editor behave exactly like tapping the maintenance card.
  void _enforceMaintenance(AppConfig config) {
    if (!config.isUnderMaintenanceAt(DateTime.now())) return;
    final closed = _hub._relays.disconnectAll();
    if (closed > 0) _hub._log('maintenance closed $closed player sockets');
    // The roster is now empty, and a moderator watching a list of people who
    // are no longer there would reasonably conclude the button did nothing.
    _hub.broadcastPlayerList();
  }

  /// Refuses [message] unless this socket has proved itself.
  bool _requireAuthorized(ProtocolMessage message) {
    if (_authorized) return true;
    // The *tag*, not the message. `AdminKickMessage.toString` prints the
    // `playerId` the client sent, which on an unauthenticated socket is just
    // a stranger's string — as long as the frame allows and repeatable as
    // fast as the inbound budget allows. The tag is ours and says everything
    // an operator needs: somebody is probing the moderation surface.
    _hub._security.write(
      'refused an unauthorised admin message: ${message.type.wireName}',
    );
    _send(
      const AdminErrorMessage(
        reason: AdminError.unauthorized,
        detail: 'Not authorised.',
      ),
    );
    return false;
  }

  /// Lifts a ban and tells the moderator which one went.
  ///
  /// Not routed through [_report] like the other three, because those all
  /// name a player who has to be *found* — and the whole point of a ban is
  /// that there is no player to find. The failure here is a different one: a
  /// row tapped a second after somebody else lifted it.
  ///
  /// No token re-check. Unbanning is the safe direction, and a dialog in
  /// front of a fix is a dialog somebody has to read while a room waits — the
  /// same argument the reopen path already makes.
  void _handleUnban(AdminUnbanMessage message) {
    final name = _hub._relays.moderation.unbanByHandle(message.banId);
    if (name == null) {
      _send(
        const AdminErrorMessage(
          reason: AdminError.unknownPlayer,
          detail: 'That ban is no longer on the list.',
        ),
      );
      return;
    }

    // The handle stands in for the target here. It is the only name this
    // action ever had — a lifted ban whose owner this run has forgotten is
    // still a real thing that happened, and the log has to be able to say so.
    final target = name.isEmpty ? message.banId : name;
    _hub._relays.audit.record(
      action: AdminAction.unban,
      targetId: message.banId,
      targetName: target,
    );
    _send(
      AdminActionResultMessage(
        action: AdminAction.unban,
        targetId: message.banId,
        targetName: target,
      ),
    );
    _hub.broadcastBanList();
  }

  /// Runs [act] against [playerId] and answers with a result or an error.
  void _report(
    AdminAction action,
    String playerId,
    ModerationOutcome? Function(String playerId) act,
  ) {
    final outcome = act(playerId);
    if (outcome == null) {
      _send(
        const AdminErrorMessage(
          reason: AdminError.unknownPlayer,
          detail: 'That player is no longer in the world.',
        ),
      );
      return;
    }
    _send(
      AdminActionResultMessage(
        action: action,
        targetId: outcome.targetId,
        targetName: outcome.targetName,
      ),
    );
    // The world just changed; do not make the moderator wait up to a second
    // to see whether the thing they tapped worked.
    _hub.broadcastPlayerList();
  }

  /// Tears this socket down from the server's side.
  ///
  /// [close] first, then the socket, matching `RelaySession.terminate`: the
  /// close does the bookkeeping and marks the session closed, so the second
  /// close the transport triggers returns immediately.
  void _terminate() {
    close();
    try {
      _connection.close();
    } on Object catch (error) {
      _hub._log('closing a throttled admin socket failed: $error');
    }
  }

  void _send(ProtocolMessage message) => _sendRaw(encodeMessage(message));

  void _sendRaw(String data) {
    if (_closed) return;
    try {
      _connection.send(data);
    } on Object catch (error) {
      _hub._log('send to an admin failed: $error');
    }
  }
}
