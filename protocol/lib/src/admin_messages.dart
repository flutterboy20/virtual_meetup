// The privileged half of the protocol.
//
// A part of `messages.dart` rather than a library of its own, because
// `ProtocolMessage` is sealed and a sealed hierarchy cannot be extended from
// outside its own library. That seal is worth keeping: it is what makes a
// `switch` over an inbound message exhaustive, so adding a message type
// breaks every handler that forgot about it at compile time instead of
// silently doing nothing in production.
part of 'messages.dart';

/// Admin to server: "here is the token, let me moderate."
///
/// The first message on an admin socket, and nothing else on that socket does
/// anything until the server has answered it. The token is a shared secret
/// from the server's environment — it is never generated here, never stored
/// here, and never written into the client's source.
@immutable
class AdminAuthMessage extends ProtocolMessage {
  /// Creates an auth request.
  const AdminAuthMessage({required this.token});

  /// Reads an auth request from its JSON form.
  factory AdminAuthMessage.fromJson(Map<String, Object?> json) =>
      AdminAuthMessage(token: readString(json, 'token'));

  /// The shared secret, typed in by whoever is moderating.
  final String token;

  @override
  MessageType get type => MessageType.adminAuth;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'token': token};

  @override
  bool operator ==(Object other) =>
      other is AdminAuthMessage && other.token == token;

  @override
  int get hashCode => Object.hash(type, token);

  /// Deliberately does not print the token.
  ///
  /// `toString` ends up in log lines and in test failure output, and a secret
  /// that leaks into a log is leaked whether or not anybody meant it to be.
  @override
  String toString() => 'AdminAuthMessage(token hidden)';
}

/// Server to admin: yes or no.
///
/// A message rather than a silent close, because the admin screen has a token
/// field in front of a person who has to know whether to retype it.
@immutable
class AdminAuthResultMessage extends ProtocolMessage {
  /// Creates an auth result.
  const AdminAuthResultMessage({
    required this.authorized,
    required this.detail,
  });

  /// Reads an auth result from its JSON form.
  factory AdminAuthResultMessage.fromJson(Map<String, Object?> json) =>
      AdminAuthResultMessage(
        authorized: readBool(json, 'authorized'),
        detail: readString(json, 'detail'),
      );

  /// Whether this connection may now moderate.
  final bool authorized;

  /// A sentence the admin screen can show as-is.
  final String detail;

  @override
  MessageType get type => MessageType.adminAuthResult;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'authorized': authorized,
    'detail': detail,
  };

  @override
  bool operator ==(Object other) =>
      other is AdminAuthResultMessage &&
      other.authorized == authorized &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(type, authorized, detail);

  @override
  String toString() => 'AdminAuthResultMessage($authorized: $detail)';
}

/// Server to admin: everybody in the world, right now.
///
/// The one message in the protocol that is deliberately *not* culled by
/// interest. Moderation is the exact case where "only what is near you" is
/// wrong — the person you have been told about is, by definition, somewhere
/// you are not.
///
/// Pushed on a slow timer rather than requested, so a moderator watching the
/// list sees somebody arrive without tapping anything.
@immutable
class AdminPlayerListMessage extends ProtocolMessage {
  /// Creates a player list.
  const AdminPlayerListMessage({
    required this.players,
    required this.online,
    this.onlineByMap = const {},
  });

  /// Reads a player list from its JSON form.
  factory AdminPlayerListMessage.fromJson(Map<String, Object?> json) =>
      AdminPlayerListMessage(
        players: readObjectList(
          json,
          'players',
        ).map(AdminPlayerSummary.fromJson).toList(growable: false),
        online: readInt(json, 'online'),
        onlineByMap: _readCounts(json['onlineByMap']),
      );

  /// Everybody in the world, on every map.
  final List<AdminPlayerSummary> players;

  /// How many there are in total, so the screen has a number before it has a
  /// list.
  ///
  /// Still the **grand total** since Phase 10, so nothing reading it has to
  /// change; [onlineByMap] is the breakdown beside it.
  final int online;

  /// How many people are on each map.
  ///
  /// Sent as its own field rather than counted from [players], because the
  /// screen shows these numbers on filter chips and a chip whose count
  /// disagreed with the server's would be worse than no chip. An absent or
  /// unreadable value is an empty map, and the screen falls back to counting
  /// rows — an old server should still be moderatable.
  final Map<MapId, int> onlineByMap;

  static Map<MapId, int> _readCounts(Object? value) {
    if (value is! Map) return const {};
    final counts = <MapId, int>{};
    for (final entry in value.entries) {
      final map = MapId.tryFromId(entry.key as String?);
      final count = entry.value;
      if (map != null && count is int && count >= 0) counts[map] = count;
    }
    return counts;
  }

  @override
  MessageType get type => MessageType.adminPlayerList;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'players': players.map((player) => player.toJson()).toList(growable: false),
    'online': online,
    'onlineByMap': {
      for (final entry in onlineByMap.entries) entry.key.id: entry.value,
    },
  };

  @override
  bool operator ==(Object other) {
    if (other is! AdminPlayerListMessage) return false;
    if (other.online != online) return false;
    if (other.players.length != players.length) return false;
    if (other.onlineByMap.length != onlineByMap.length) return false;
    for (final entry in onlineByMap.entries) {
      if (other.onlineByMap[entry.key] != entry.value) return false;
    }
    for (var i = 0; i < players.length; i++) {
      if (other.players[i] != players[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    type,
    Object.hashAll(players),
    online,
    Object.hashAll(onlineByMap.entries.map((e) => Object.hash(e.key, e.value))),
  );

  @override
  String toString() => 'AdminPlayerListMessage($online online)';
}

/// Admin to server: disconnect this player.
///
/// They can come straight back. This is the mild end of the scale, for
/// somebody who needs to notice that a human is watching.
@immutable
class AdminKickMessage extends ProtocolMessage {
  /// Creates a kick.
  const AdminKickMessage({required this.playerId});

  /// Reads a kick from its JSON form.
  factory AdminKickMessage.fromJson(Map<String, Object?> json) =>
      AdminKickMessage(playerId: readString(json, 'playerId'));

  /// Who to disconnect.
  final String playerId;

  @override
  MessageType get type => MessageType.adminKick;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'playerId': playerId};

  @override
  bool operator ==(Object other) =>
      other is AdminKickMessage && other.playerId == playerId;

  @override
  int get hashCode => Object.hash(type, playerId);

  @override
  String toString() => 'AdminKickMessage($playerId)';
}

/// Admin to server: disconnect this player and keep them out.
///
/// The block is on their session id, which the server already knows — the
/// admin never sees it and never sends it. A determined person can clear
/// their storage and come back with a new one, and that is accepted: this is
/// a tool for removing a disruption in ten seconds, not an access control
/// system.
@immutable
class AdminBanMessage extends ProtocolMessage {
  /// Creates a ban.
  const AdminBanMessage({required this.playerId});

  /// Reads a ban from its JSON form.
  factory AdminBanMessage.fromJson(Map<String, Object?> json) =>
      AdminBanMessage(playerId: readString(json, 'playerId'));

  /// Who to remove.
  final String playerId;

  @override
  MessageType get type => MessageType.adminBan;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'playerId': playerId};

  @override
  bool operator ==(Object other) =>
      other is AdminBanMessage && other.playerId == playerId;

  @override
  int get hashCode => Object.hash(type, playerId);

  @override
  String toString() => 'AdminBanMessage($playerId)';
}

/// Server to admin: every ban currently in force.
///
/// Pushed on the same slow timer as the player list, and again the moment a
/// ban is taken or lifted, so a moderator watching the tab sees their own
/// action land without tapping anything.
///
/// Carries **handles, not session ids** — see [BannedSession]. The list is
/// short by nature: bans are the rarest thing a moderator does, and an event
/// with a hundred of them has a problem no tool fixes.
@immutable
class AdminBanListMessage extends ProtocolMessage {
  /// Creates a ban list.
  const AdminBanListMessage({required this.bans});

  /// Reads a ban list from its JSON form.
  factory AdminBanListMessage.fromJson(Map<String, Object?> json) =>
      AdminBanListMessage(
        bans: readObjectList(
          json,
          'bans',
        ).map(BannedSession.fromJson).toList(growable: false),
      );

  /// Every ban in force, newest first.
  final List<BannedSession> bans;

  @override
  MessageType get type => MessageType.adminBanList;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'bans': bans.map((ban) => ban.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) {
    if (other is! AdminBanListMessage) return false;
    if (other.bans.length != bans.length) return false;
    for (var i = 0; i < bans.length; i++) {
      if (other.bans[i] != bans[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(type, Object.hashAll(bans));

  @override
  String toString() => 'AdminBanListMessage(${bans.length} banned)';
}

/// Admin to server: lift this ban.
///
/// Names a **ban handle** rather than a player id, because by the time this
/// is sent there is no player: the ban is what is left of them. The handle is
/// one-way — the server maps it back to a session id it never sent out.
///
/// No token re-check, unlike closing the event. Unbanning is the *safe*
/// direction: the cost of a mis-tap is one person back in a party, and the
/// undo for it is the ban button they were just removed with.
@immutable
class AdminUnbanMessage extends ProtocolMessage {
  /// Creates an unban.
  const AdminUnbanMessage({required this.banId});

  /// Reads an unban from its JSON form.
  factory AdminUnbanMessage.fromJson(Map<String, Object?> json) =>
      AdminUnbanMessage(banId: readString(json, 'banId'));

  /// Which ban to lift, by its handle.
  final String banId;

  @override
  MessageType get type => MessageType.adminUnban;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'banId': banId};

  @override
  bool operator ==(Object other) =>
      other is AdminUnbanMessage && other.banId == banId;

  @override
  int get hashCode => Object.hash(type, banId);

  @override
  String toString() => 'AdminUnbanMessage($banId)';
}

/// Admin to server: take this player's name away, or give it back.
///
/// The action the design expects to use most. A bad *name* is the likely
/// incident in a world with no chat, and disconnecting somebody over a word
/// is a bigger hammer than the problem needs — this fixes the actual problem
/// and leaves them in the room.
@immutable
class AdminMuteNameMessage extends ProtocolMessage {
  /// Creates a mute (or an unmute, when [muted] is false).
  const AdminMuteNameMessage({required this.playerId, required this.muted});

  /// Reads a mute from its JSON form.
  factory AdminMuteNameMessage.fromJson(Map<String, Object?> json) =>
      AdminMuteNameMessage(
        playerId: readString(json, 'playerId'),
        muted: readBool(json, 'muted'),
      );

  /// Whose name.
  final String playerId;

  /// True to replace it with [mutedDisplayName], false to restore it.
  final bool muted;

  @override
  MessageType get type => MessageType.adminMuteName;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'playerId': playerId,
    'muted': muted,
  };

  @override
  bool operator ==(Object other) =>
      other is AdminMuteNameMessage &&
      other.playerId == playerId &&
      other.muted == muted;

  @override
  int get hashCode => Object.hash(type, playerId, muted);

  @override
  String toString() => 'AdminMuteNameMessage($playerId, muted: $muted)';
}

/// Server to admin: that worked, and here is what it did.
///
/// Carries the target's name as well as their id because the admin tapped a
/// row, not an id, and "Kicked p47" is not a sentence anybody can check
/// against what they meant to do.
@immutable
class AdminActionResultMessage extends ProtocolMessage {
  /// Creates a result.
  const AdminActionResultMessage({
    required this.action,
    required this.targetId,
    required this.targetName,
  });

  /// Reads a result from its JSON form.
  ///
  /// Throws a [FormatException] on an action this build does not know, so it
  /// decodes as an [UnknownMessage] and is dropped rather than being reported
  /// to a moderator as some other action they did not take.
  factory AdminActionResultMessage.fromJson(Map<String, Object?> json) {
    final action = AdminAction.fromWireName(readString(json, 'action'));
    if (action == null) {
      throw FormatException('unknown admin action: ${json['action']}');
    }
    return AdminActionResultMessage(
      action: action,
      targetId: readString(json, 'targetId'),
      targetName: readString(json, 'targetName'),
    );
  }

  /// What was done.
  final AdminAction action;

  /// Who it was done to.
  final String targetId;

  /// The name they were going by when it happened.
  final String targetName;

  @override
  MessageType get type => MessageType.adminActionResult;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'action': action.wireName,
    'targetId': targetId,
    'targetName': targetName,
  };

  @override
  bool operator ==(Object other) =>
      other is AdminActionResultMessage &&
      other.action == action &&
      other.targetId == targetId &&
      other.targetName == targetName;

  @override
  int get hashCode => Object.hash(type, action, targetId, targetName);

  @override
  String toString() => 'AdminActionResultMessage(${action.wireName} $targetId)';
}

/// Server to admin: no, and why.
///
/// The [AdminError.unauthorized] case is the important one: it is what an
/// unauthenticated socket gets for *every* admin message, which is how the
/// "hiding the UI is not security" rule shows up on the wire.
@immutable
class AdminErrorMessage extends ProtocolMessage {
  /// Creates an error.
  const AdminErrorMessage({required this.reason, required this.detail});

  /// Reads an error from its JSON form.
  factory AdminErrorMessage.fromJson(Map<String, Object?> json) =>
      AdminErrorMessage(
        reason: AdminError.fromWireName(readString(json, 'reason')),
        detail: readString(json, 'detail'),
      );

  /// Which rule the message broke.
  final AdminError reason;

  /// A sentence the admin screen can show as-is.
  final String detail;

  @override
  MessageType get type => MessageType.adminError;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'reason': reason.wireName,
    'detail': detail,
  };

  @override
  bool operator ==(Object other) =>
      other is AdminErrorMessage &&
      other.reason == reason &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(type, reason, detail);

  @override
  String toString() => 'AdminErrorMessage(${reason.wireName}: $detail)';
}

/// Admin to server: replace the event's config with this document.
///
/// The one admin message that changes what *every* attendee sees rather than
/// what happens to one of them, which is why it carries raw text and not a
/// parsed [AppConfig]: the server is the only place a document is allowed to
/// be judged, and a moderator typing at nine in the morning has to be told
/// when their JSON has a trailing comma in it.
@immutable
class AdminSetConfigMessage extends ProtocolMessage {
  /// Creates a config push.
  const AdminSetConfigMessage({required this.document});

  /// Reads a config push from its JSON form.
  factory AdminSetConfigMessage.fromJson(Map<String, Object?> json) =>
      AdminSetConfigMessage(document: readString(json, 'document'));

  /// The JSON document, exactly as it was typed.
  final String document;

  @override
  MessageType get type => MessageType.adminSetConfig;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'document': document};

  @override
  bool operator ==(Object other) =>
      other is AdminSetConfigMessage && other.document == document;

  @override
  int get hashCode => Object.hash(type, document);

  /// Deliberately prints the length rather than the document.
  ///
  /// `toString` ends up in log lines, and a whole config document per push
  /// would turn the server log into a copy of the config file.
  @override
  String toString() => 'AdminSetConfigMessage(${document.length} chars)';
}

/// Admin to server: close the event until [until], or open it again.
///
/// The one admin message that carries the token **after** authentication.
/// Every other action here removes one person from a room; this one removes
/// the whole room, and a socket that proved itself when the moderator sat
/// down is a weaker claim than that same person typing the token again
/// deliberately, ten minutes later, in front of a dialog that says what is
/// about to happen.
///
/// It is not a second gate in front of the first — the server still refuses
/// this from an unauthorised socket exactly as it refuses a kick. It is the
/// same gate, asked twice, for the action where the cost of a mis-tap is
/// everybody.
@immutable
class AdminSetMaintenanceMessage extends ProtocolMessage {
  /// Creates a maintenance change.
  const AdminSetMaintenanceMessage({
    required this.token,
    this.until,
    this.message = '',
    this.showTimer = true,
  });

  /// Reads a maintenance change from its JSON form.
  ///
  /// Strict about [until], unlike the config document's own reader: a client
  /// that sent a timestamp the server cannot read meant *something*, and
  /// quietly turning that into "open the event" would be the exact opposite
  /// of what the person tapping the button asked for. An unreadable value
  /// throws, so the message decodes as unknown and is dropped.
  factory AdminSetMaintenanceMessage.fromJson(Map<String, Object?> json) {
    // Read before the early return, so reopening the event can still carry a
    // sentence — "we are back, the keynote starts in five" is exactly the
    // thing somebody wants to say at the moment they open the doors.
    final message = json['message'];
    final showTimer = json['showTimer'];
    final raw = json['until'];
    if (raw == null) {
      return AdminSetMaintenanceMessage(
        token: readString(json, 'token'),
        message: message is String ? message.trim() : '',
        showTimer: showTimer is! bool || showTimer,
      );
    }
    if (raw is! String) {
      throw FormatException('"until" must be a string, got ${raw.runtimeType}');
    }
    final until = DateTime.tryParse(raw);
    if (until == null) {
      throw FormatException('"until" is not an ISO-8601 instant: $raw');
    }
    return AdminSetMaintenanceMessage(
      token: readString(json, 'token'),
      until: until.toUtc(),
      message: message is String ? message.trim() : '',
      showTimer: showTimer is! bool || showTimer,
    );
  }

  /// The shared secret, typed again by whoever is closing the event.
  final String token;

  /// When the event opens again, or `null` to open it now.
  final DateTime? until;

  /// What to tell the people who are locked out, or `''` for the built-in
  /// sentence.
  ///
  /// Deliberately *not* validated here beyond a trim. This is a sentence a
  /// human wrote for other humans; the only thing the protocol has an opinion
  /// about is that it is a string, and the server caps its length the same
  /// way it caps the config document it ends up inside.
  final String message;

  /// Whether the pause screen should count down to [until].
  ///
  /// Sent alongside the moment rather than left in the config document,
  /// because it is part of the same decision: a moderator closing the event
  /// for "about an hour" wants the sentence and not the clock, and having to
  /// make that choice in two places is how the two end up disagreeing.
  final bool showTimer;

  @override
  MessageType get type => MessageType.adminSetMaintenance;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'token': token,
    'until': until?.toUtc().toIso8601String(),
    'message': message,
    'showTimer': showTimer,
  };

  @override
  bool operator ==(Object other) =>
      other is AdminSetMaintenanceMessage &&
      other.token == token &&
      other.until == until &&
      other.message == message &&
      other.showTimer == showTimer;

  @override
  int get hashCode => Object.hash(type, token, until, message, showTimer);

  /// Deliberately does not print the token, like [AdminAuthMessage].
  @override
  String toString() =>
      'AdminSetMaintenanceMessage(until: ${until?.toIso8601String() ?? 'now'},'
      ' token hidden)';
}
