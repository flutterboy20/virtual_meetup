/// Every message kind that can cross the wire.
///
/// The tag is the single source of truth for "what is this message": the
/// decoder switches on it once, in one place, and hands back a typed object.
/// Nothing downstream compares raw strings.
enum MessageType {
  /// Client → server: "let me in, here is how I look".
  join('join'),

  /// Client → server: "my bean is here now", sent at a throttled rate.
  move('move'),

  /// Server → client: your id.
  welcome('welcome'),

  /// Server → client: everyone near you, once per server tick.
  ///
  /// This replaced the per-message `playerJoined` / `playerMoved` broadcast
  /// in Phase 3. Those grew as `players² × send rate`; a snapshot's size
  /// depends on your *neighbours*, which is what makes 200+ attendees
  /// affordable.
  snapshot('snapshot'),

  /// Server → client: somebody else left the world entirely.
  ///
  /// Distinct from a player merely walking out of your interest range, which
  /// arrives in a snapshot's out-of-range list — same visual result, different
  /// fact about the world.
  playerLeft('playerLeft'),

  /// Server → client: the join was refused, with a typed reason.
  ///
  /// Only ever sent in answer to a `join`, and always followed by the server
  /// closing the socket. Its existence is the "never trust the client" rule
  /// made visible: the client validates the name so the player gets a message
  /// while typing, and the server validates it again because the client's
  /// check is advice and this one is the rule.
  joinRejected('joinRejected'),

  /// Client → server: "I just reacted", with which reaction.
  ///
  /// Carries no player id: the server knows whose socket this arrived on,
  /// and a client that could name the emoter could put a reaction over
  /// somebody else's head.
  emote('emote'),

  /// Server → client: somebody nearby reacted.
  ///
  /// Sent the moment it happens rather than folded into the next snapshot.
  /// Emotes are ephemeral — never stored, never replayed to a late joiner —
  /// so a snapshot, which describes *state*, is the wrong carrier for them.
  playerEmoted('playerEmoted'),

  /// Client → server: "I picked up a board", or "I put it down".
  ///
  /// Carries no player id, for the same reason [emote] does not: the server
  /// knows whose socket it arrived on, and a client that could name the owner
  /// could hand somebody else a board they never found.
  ///
  /// An event rather than a field on [move]. The board changes twice in a
  /// session; a position changes fifteen times a second. Folding one into the
  /// other would pay for the rare thing at the rate of the common one.
  board('board'),

  /// Server → client: somebody nearby picked up or put down a board.
  ///
  /// Only the *change* is sent this way. The state itself rides in
  /// `PlayerState.hasBoard`, inside a snapshot's appeared list, so a player
  /// who walks into range of somebody already carrying a board learns about
  /// it without anybody re-announcing anything.
  playerBoard('playerBoard'),

  /// Server → client: how the world as a whole is doing, about once a second.
  ///
  /// Separate from a snapshot because the two answer different questions at
  /// different rates. A snapshot is "who is near you", fifteen times a
  /// second, and is the server's whole bandwidth bill; this is "how many
  /// people are here", once a second, and is the one number that is *not*
  /// culled. Folding it into a snapshot would repeat it fifteen times a
  /// second, per client, to say the same thing.
  worldStats('worldStats'),

  /// Server → client: the event's editable copy, and how big its crowd is.
  ///
  /// Pushed, not requested, and pushed **again** every time a moderator
  /// changes it — which is the whole point. The alternative was a client that
  /// only read config at startup, which makes the fix for a typo on the
  /// projector "ask two hundred people to refresh".
  ///
  /// Neither culled nor throttled, because it is neither positional nor
  /// frequent: it arrives once on join and then only when a human edits it.
  config('config'),

  // ── Admin ──────────────────────────────────────────────────────────────
  //
  // Every admin tag is namespaced `admin.*` on the wire, and every admin
  // message is defined in its own file. Two reasons, and the second is the
  // one that matters: it is obvious at a glance in a log which messages are
  // privileged, and a `switch` over inbound player messages that accidentally
  // grew an admin case is visible in review rather than invisible in
  // production.

  /// Admin → server: "here is the token."
  adminAuth('admin.auth'),

  /// Server → admin: whether that token was the right one.
  adminAuthResult('admin.authResult'),

  /// Server → admin: everybody in the world, uncalled, on a slow timer.
  adminPlayerList('admin.players'),

  /// Admin → server: disconnect this player. They may rejoin.
  adminKick('admin.kick'),

  /// Admin → server: disconnect this player and refuse their session.
  adminBan('admin.ban'),

  /// Admin → server: replace this player's name, or give it back.
  adminMuteName('admin.muteName'),

  /// Admin → server: replace the event's config with this document.
  ///
  /// Carries the **raw text** a moderator typed rather than a parsed object,
  /// so the server does the parsing and the server is the one that gets to
  /// say no. A client that parsed first would have to decide what to do with
  /// a document it could not read, and every answer to that is worse than
  /// handing the text over and being told.
  adminSetConfig('admin.setConfig'),

  /// Admin → server: close the event until this moment, or open it again.
  ///
  /// Carries the token a second time, and that is the whole reason it is its
  /// own message rather than a config push with one more key in it. Every
  /// other admin action removes one person; this one removes everybody, and
  /// the socket having been authorised ten minutes ago is a weaker claim than
  /// somebody typing the token again now.
  adminSetMaintenance('admin.setMaintenance'),

  /// Server → admin: an action went through.
  adminActionResult('admin.result'),

  /// Server → admin: an action did not, and why.
  adminError('admin.error'),

  /// Anything this build does not recognise, or could not parse.
  ///
  /// Decoding never throws: a message we cannot read becomes this, and the
  /// receiver drops it. That is what lets a client and a server be deployed
  /// slightly out of step without a hard break.
  unknown('unknown');

  const MessageType(this.wireName);

  /// The string written into the message's `type` field.
  final String wireName;

  /// Returns the type named by [wireName], or [MessageType.unknown].
  static MessageType fromWireName(String? wireName) {
    for (final type in MessageType.values) {
      if (type.wireName == wireName) return type;
    }
    return MessageType.unknown;
  }
}
