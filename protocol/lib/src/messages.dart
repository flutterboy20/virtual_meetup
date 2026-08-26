import 'package:meta/meta.dart';
import 'package:protocol/src/admin.dart';
import 'package:protocol/src/app_config.dart';
import 'package:protocol/src/emote.dart';
import 'package:protocol/src/join_rejection.dart';
import 'package:protocol/src/json_reader.dart';
import 'package:protocol/src/map_id.dart';
import 'package:protocol/src/message_type.dart';
import 'package:protocol/src/player_position.dart';
import 'package:protocol/src/player_state.dart';
import 'package:protocol/src/protocol_version.dart';

part 'admin_messages.dart';

/// Base class of everything that crosses the WebSocket.
///
/// Sealed on purpose: a `switch` over a received message is checked by the
/// compiler, so adding a message type in a later phase breaks every handler
/// that forgot about it instead of silently doing nothing at runtime.
sealed class ProtocolMessage {
  /// Creates a message.
  const ProtocolMessage();

  /// The tag written into the message's `type` field.
  MessageType get type;

  /// Returns the JSON form of this message, tag and version included.
  Map<String, Object?> toJson();

  /// The envelope every message carries: what it is, and which protocol
  /// version wrote it.
  Map<String, Object?> envelope() => {
    'type': type.wireName,
    'version': protocolVersion,
  };
}

/// Client to server: "let me in, here is how I look."
///
/// Carries no player id and no position: the server assigns both, so a client
/// cannot choose to be somebody else.
///
/// It does carry a [sessionId], and that is a different thing from a player
/// id. The player id names a *seat in the world* and is the server's to give;
/// the session id names a *device* and is the client's to keep. When a socket
/// dies and the client comes back, the session id is the only thing that lets
/// the server say "this is the same person" instead of seating them twice.
@immutable
class JoinMessage extends ProtocolMessage {
  /// Creates a join.
  const JoinMessage({
    required this.sessionId,
    required this.name,
    required this.color,
    required this.cosmetic,
  });

  /// Reads a join from its JSON form.
  ///
  /// A join with no `sessionId` reads as an empty one rather than throwing:
  /// the server has a typed rejection for that, and answering "you are not
  /// allowed in, here is why" is more useful to whoever wrote that client
  /// than the message silently becoming an unknown and being dropped.
  factory JoinMessage.fromJson(Map<String, Object?> json) => JoinMessage(
    sessionId: json.containsKey('sessionId')
        ? readString(json, 'sessionId')
        : '',
    name: readString(json, 'name'),
    color: readInt(json, 'color'),
    cosmetic: PlayerCosmetic.fromWireName(readString(json, 'cosmetic')),
  );

  /// The device's own identity, generated once and persisted locally.
  final String sessionId;

  /// The display name the player asked for.
  final String name;

  /// The bean's body colour as a 32-bit ARGB value.
  final int color;

  /// The cosmetic worn on the bean's head.
  final PlayerCosmetic cosmetic;

  @override
  MessageType get type => MessageType.join;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'sessionId': sessionId,
    'name': name,
    'color': color,
    'cosmetic': cosmetic.wireName,
  };

  @override
  bool operator ==(Object other) =>
      other is JoinMessage &&
      other.sessionId == sessionId &&
      other.name == name &&
      other.color == color &&
      other.cosmetic == cosmetic;

  @override
  int get hashCode => Object.hash(type, sessionId, name, color, cosmetic);

  @override
  String toString() => 'JoinMessage($name)';
}

/// Server to client: no, and here is which rule you broke.
///
/// The client's name filter is UX; this is the actual rule, so this message
/// exists for the case where the two disagree — a client that skipped the
/// check, a client built against older rules, or one that somebody else
/// wrote. The socket is closed straight after it is sent.
///
/// Deliberately *not* an [UnknownMessage] or a silent close: a player staring
/// at a lobby that will not let them in, with nothing on screen, is the worst
/// version of this. [detail] is a sentence to put in front of them.
@immutable
class JoinRejectedMessage extends ProtocolMessage {
  /// Creates a rejection.
  const JoinRejectedMessage({required this.reason, required this.detail});

  /// Reads a rejection from its JSON form.
  factory JoinRejectedMessage.fromJson(Map<String, Object?> json) =>
      JoinRejectedMessage(
        reason: JoinRejection.fromWireName(readString(json, 'reason')),
        detail: readString(json, 'detail'),
      );

  /// Which rule the join broke.
  final JoinRejection reason;

  /// A sentence the client can show as-is.
  final String detail;

  @override
  MessageType get type => MessageType.joinRejected;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'reason': reason.wireName,
    'detail': detail,
  };

  @override
  bool operator ==(Object other) =>
      other is JoinRejectedMessage &&
      other.reason == reason &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(type, reason, detail);

  @override
  String toString() => 'JoinRejectedMessage(${reason.wireName}: $detail)';
}

/// Client to server: "my bean is here now."
///
/// Sent at a throttled rate (~10Hz), never per frame — 60Hz per client is
/// what melts the server at conference scale.
@immutable
class MoveMessage extends ProtocolMessage {
  /// Creates a move.
  const MoveMessage({required this.x, required this.y});

  /// Reads a move from its JSON form.
  factory MoveMessage.fromJson(Map<String, Object?> json) =>
      MoveMessage(x: readDouble(json, 'x'), y: readDouble(json, 'y'));

  /// Position along the world's x axis, in world units.
  final double x;

  /// Position along the world's y axis, in world units.
  final double y;

  @override
  MessageType get type => MessageType.move;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      other is MoveMessage && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(type, x, y);

  @override
  String toString() => 'MoveMessage($x, $y)';
}

/// Server to client: your id.
///
/// Deliberately *only* the id. Before Phase 3 this also carried every player
/// already in the world, which is exactly the thing interest management
/// exists to stop: at 300 attendees that is 300 players' worth of metadata
/// handed to somebody who can see nine of them. The first snapshot says who
/// is actually nearby, one tick later.
@immutable
class WelcomeMessage extends ProtocolMessage {
  /// Creates a welcome.
  const WelcomeMessage({required this.yourId});

  /// Reads a welcome from its JSON form.
  factory WelcomeMessage.fromJson(Map<String, Object?> json) =>
      WelcomeMessage(yourId: readString(json, 'yourId'));

  /// The id the server assigned to this connection.
  final String yourId;

  @override
  MessageType get type => MessageType.welcome;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'yourId': yourId};

  @override
  bool operator ==(Object other) =>
      other is WelcomeMessage && other.yourId == yourId;

  @override
  int get hashCode => Object.hash(type, yourId);

  @override
  String toString() => 'WelcomeMessage($yourId)';
}

/// Server to client: everyone near you, as of this tick.
///
/// Sent on a fixed ~15Hz timer rather than in reaction to inbound moves, so
/// the rate a client *receives* at is decoupled from the rate everybody else
/// *sends* at. One player walking fast cannot raise anyone else's bill.
///
/// The three lists answer three different questions, which is why they are
/// three lists and not one:
///
/// - [appeared] — players who just entered your interest range. Full
///   metadata, sent exactly once per appearance.
/// - [positions] — where everyone in range is now. An id and two numbers.
/// - [outOfRange] — players who were in range last tick and are not now.
///   They still exist; they just walked far enough away that you stop paying
///   for them.
@immutable
class SnapshotMessage extends ProtocolMessage {
  /// Creates a snapshot.
  const SnapshotMessage({
    this.appeared = const [],
    this.positions = const [],
    this.outOfRange = const [],
  });

  /// Reads a snapshot from its JSON form.
  factory SnapshotMessage.fromJson(Map<String, Object?> json) =>
      SnapshotMessage(
        appeared: readObjectList(
          json,
          'appeared',
        ).map(PlayerState.fromJson).toList(growable: false),
        positions: readObjectList(
          json,
          'positions',
        ).map(PlayerPosition.fromJson).toList(growable: false),
        outOfRange: readStringList(json, 'outOfRange'),
      );

  /// Players who just entered interest range, with everything needed to draw
  /// them. Anyone in here is in [positions] too.
  final List<PlayerState> appeared;

  /// Where every in-range player is right now.
  final List<PlayerPosition> positions;

  /// Ids that left interest range since the previous snapshot.
  final List<String> outOfRange;

  /// Whether this snapshot says nothing at all.
  ///
  /// The server never sends these: somebody standing alone in a corner of the
  /// world should cost zero bandwidth, not fifteen empty messages a second.
  bool get isEmpty =>
      appeared.isEmpty && positions.isEmpty && outOfRange.isEmpty;

  @override
  MessageType get type => MessageType.snapshot;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'appeared': appeared
        .map((player) => player.toJson())
        .toList(growable: false),
    'positions': positions
        .map((position) => position.toJson())
        .toList(growable: false),
    'outOfRange': outOfRange,
  };

  @override
  bool operator ==(Object other) =>
      other is SnapshotMessage &&
      _sameList(other.appeared, appeared) &&
      _sameList(other.positions, positions) &&
      _sameList(other.outOfRange, outOfRange);

  @override
  int get hashCode => Object.hash(
    type,
    Object.hashAll(appeared),
    Object.hashAll(positions),
    Object.hashAll(outOfRange),
  );

  @override
  String toString() =>
      'SnapshotMessage(${positions.length} near, '
      '${appeared.length} new, ${outOfRange.length} gone)';

  static bool _sameList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Server to client: somebody else left the world.
///
/// Not the same as walking out of your interest range, which arrives in a
/// snapshot instead. Both end up removing a bean, but only one of them can
/// come back by walking towards you — and only this one means the socket is
/// gone, which is what a future reconnect flow has to reason about.
@immutable
class PlayerLeftMessage extends ProtocolMessage {
  /// Creates a player-left.
  const PlayerLeftMessage({required this.id});

  /// Reads a player-left from its JSON form.
  factory PlayerLeftMessage.fromJson(Map<String, Object?> json) =>
      PlayerLeftMessage(id: readString(json, 'id'));

  /// Who left.
  final String id;

  @override
  MessageType get type => MessageType.playerLeft;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'id': id};

  @override
  bool operator ==(Object other) =>
      other is PlayerLeftMessage && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => 'PlayerLeftMessage($id)';
}

/// Anything this build could not read: an unknown type, malformed JSON, or a
/// field of the wrong shape.
///
/// Decoding produces this instead of throwing. Receivers drop it (and log
/// it); nobody crashes. That is the whole forward-compatibility story — a new
/// message type can be deployed to one side before the other.
@immutable
class UnknownMessage extends ProtocolMessage {
  /// Creates an unknown message.
  const UnknownMessage({required this.reason, this.rawType});

  /// Reads an unknown from its JSON form.
  factory UnknownMessage.fromJson(Map<String, Object?> json) {
    final rawType = json['rawType'];
    return UnknownMessage(
      reason: readString(json, 'reason'),
      rawType: rawType is String ? rawType : null,
    );
  }

  /// Why the message could not be read, for the log line.
  final String reason;

  /// The `type` tag that was on the message, when there was one.
  final String? rawType;

  @override
  MessageType get type => MessageType.unknown;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'reason': reason,
    if (rawType != null) 'rawType': rawType,
  };

  @override
  bool operator ==(Object other) =>
      other is UnknownMessage &&
      other.reason == reason &&
      other.rawType == rawType;

  @override
  int get hashCode => Object.hash(type, reason, rawType);

  /// The most of one field that ever reaches a log line.
  ///
  /// Both fields are attacker-controlled. `rawType` is whatever string a
  /// client put in its `type` tag, and `reason` is read straight off the wire
  /// whenever the tag says `unknown` — so either can be as long as the frame
  /// limit allows, on a path a hostile client drives thousands of times a
  /// second. Sixty-four characters identifies any honest unknown tag and caps
  /// the line at a size a log pipeline can survive.
  static const int maxLoggedFieldLength = 64;

  @override
  String toString() =>
      'UnknownMessage(${_forLog(rawType) ?? '?'}: ${_forLog(reason)})';
}

/// Clips [value] and strips what could forge a log line out of it.
///
/// Two jobs, both about the fact that the caller is a log line and the value
/// is a stranger's. Length, so one frame cannot become a kilobyte of disk;
/// and control characters, because a newline in a logged value is how one
/// event becomes two and an attacker writes their own entries.
String? _forLog(String? value) {
  if (value == null) return null;
  var clipped = value;
  if (clipped.length > UnknownMessage.maxLoggedFieldLength) {
    clipped = clipped.substring(0, UnknownMessage.maxLoggedFieldLength);
    // Cutting at a fixed offset can land between the halves of a surrogate
    // pair. Dropping the orphan is cheaper than counting runes on a hot path.
    final last = clipped.codeUnitAt(clipped.length - 1);
    if (last >= 0xd800 && last <= 0xdbff) {
      clipped = clipped.substring(0, clipped.length - 1);
    }
    clipped = '$clipped…';
  }
  return clipped.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '.');
}

/// Client to server: "I just reacted."
///
/// The smallest message in the protocol, and deliberately so: it carries no
/// id (the server knows whose socket it arrived on), no position (the server
/// knows where that player is), and no timestamp (it is ephemeral — if it
/// arrives late, it is late, and nothing replays it).
@immutable
class EmoteMessage extends ProtocolMessage {
  /// Creates an emote.
  const EmoteMessage({required this.emote});

  /// Reads an emote from its JSON form.
  ///
  /// Throws a [FormatException] on a reaction this build has never heard of,
  /// so it decodes as an [UnknownMessage] and is dropped. Guessing a default
  /// would put a reaction somebody did not choose over their head.
  factory EmoteMessage.fromJson(Map<String, Object?> json) {
    final kind = EmoteKind.fromWireName(readString(json, 'emote'));
    if (kind == null) {
      throw FormatException('unknown emote: ${json['emote']}');
    }
    return EmoteMessage(emote: kind);
  }

  /// Which reaction.
  final EmoteKind emote;

  @override
  MessageType get type => MessageType.emote;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'emote': emote.wireName};

  @override
  bool operator ==(Object other) =>
      other is EmoteMessage && other.emote == emote;

  @override
  int get hashCode => Object.hash(type, emote);

  @override
  String toString() => 'EmoteMessage(${emote.wireName})';
}

/// Server to client: somebody near you reacted.
///
/// Relayed only to the players who can currently see the emoter, on the same
/// interest rule as everything else — a reaction thrown in the lounge costs
/// nothing to somebody standing in the conference hall.
@immutable
class PlayerEmotedMessage extends ProtocolMessage {
  /// Creates a relayed emote.
  const PlayerEmotedMessage({required this.id, required this.emote});

  /// Reads a relayed emote from its JSON form.
  factory PlayerEmotedMessage.fromJson(Map<String, Object?> json) {
    final kind = EmoteKind.fromWireName(readString(json, 'emote'));
    if (kind == null) {
      throw FormatException('unknown emote: ${json['emote']}');
    }
    return PlayerEmotedMessage(id: readString(json, 'id'), emote: kind);
  }

  /// Who reacted. Assigned by the server, never by the sender.
  final String id;

  /// Which reaction.
  final EmoteKind emote;

  @override
  MessageType get type => MessageType.playerEmoted;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'id': id,
    'emote': emote.wireName,
  };

  @override
  bool operator ==(Object other) =>
      other is PlayerEmotedMessage && other.id == id && other.emote == emote;

  @override
  int get hashCode => Object.hash(type, id, emote);

  @override
  String toString() => 'PlayerEmotedMessage($id: ${emote.wireName})';
}

/// Client to server: "I have a board now", or "I have put it down".
///
/// As small as an emote and for the same reasons: no id (the server knows
/// whose socket this is), no position (the server knows where they are), no
/// timestamp (there is nothing to replay). One bool.
///
/// Sent on a toggle, and once more after every welcome by a client that is
/// already carrying one — a reconnect gives the player a fresh appearance to
/// everybody around them, and the board has to be part of it. Deliberately
/// *not* folded into [JoinMessage]: the join belongs to the connection
/// supervisor, and threading a game-layer fact through it would put two
/// layers in the one path that must never send twice.
@immutable
class BoardMessage extends ProtocolMessage {
  /// Creates a board announcement.
  const BoardMessage({required this.hasBoard});

  /// Reads a board announcement from its JSON form.
  ///
  /// The flag is read leniently: a message that says nothing readable about
  /// the board is saying "no board", which is the safe reading. It cannot
  /// silently *grant* one.
  factory BoardMessage.fromJson(Map<String, Object?> json) =>
      BoardMessage(hasBoard: readOptionalBool(json, 'hasBoard'));

  /// Whether the sender is carrying a board.
  final bool hasBoard;

  @override
  MessageType get type => MessageType.board;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'hasBoard': hasBoard};

  @override
  bool operator ==(Object other) =>
      other is BoardMessage && other.hasBoard == hasBoard;

  @override
  int get hashCode => Object.hash(type, hasBoard);

  @override
  String toString() => 'BoardMessage($hasBoard)';
}

/// Server to client: somebody near you picked up or put down a board.
///
/// Relayed on the same interest rule as an emote — only to the people who can
/// currently see them — and for the same reason: a board found at the far end
/// of the beach is not an event in the boardwalk.
///
/// This message carries only the *edge*. Steady state travels in
/// `PlayerState.hasBoard`, which is sent once per appearance, so a player
/// walking into range of a surfer sees the board without this message ever
/// being involved.
@immutable
class PlayerBoardMessage extends ProtocolMessage {
  /// Creates a relayed board change.
  const PlayerBoardMessage({required this.id, required this.hasBoard});

  /// Reads a relayed board change from its JSON form.
  factory PlayerBoardMessage.fromJson(Map<String, Object?> json) =>
      PlayerBoardMessage(
        id: readString(json, 'id'),
        hasBoard: readOptionalBool(json, 'hasBoard'),
      );

  /// Whose board it is. Assigned by the server, never by the sender.
  final String id;

  /// Whether they are carrying it now.
  final bool hasBoard;

  @override
  MessageType get type => MessageType.playerBoard;

  @override
  Map<String, Object?> toJson() => {
    ...envelope(),
    'id': id,
    'hasBoard': hasBoard,
  };

  @override
  bool operator ==(Object other) =>
      other is PlayerBoardMessage &&
      other.id == id &&
      other.hasBoard == hasBoard;

  @override
  int get hashCode => Object.hash(type, id, hasBoard);

  @override
  String toString() => 'PlayerBoardMessage($id: $hasBoard)';
}

/// Server to a client: this player is showing under a different name now.
///
/// The one thing a snapshot cannot say. Metadata travels **once**, when a
/// player appears, which is what makes interest management cheap — and it is
/// also why a moderator taking somebody's name away had, until this message,
/// no way of reaching the screens that were already drawing it. The old
/// answer was to make every client forget the player so the next tick
/// re-announced them; that works, but it rides on the neighbour cap keeping
/// its slot for somebody it has just been told is a stranger, which in a
/// packed atrium is exactly when it will not.
///
/// So the rename is now stated outright, to everybody who can see them **and
/// to the player themselves**. The last part is the visible half: a muted
/// person who still sees their own name over their own bean has no idea
/// anything happened, and cannot tell the difference between a mute and a
/// bug.
///
/// Carries the name the world should *show*, not the one they chose. The
/// chosen name never leaves the server once it has been taken away.
@immutable
class PlayerRenamedMessage extends ProtocolMessage {
  /// Creates a rename.
  const PlayerRenamedMessage({required this.id, required this.name});

  /// Reads a rename from its JSON form.
  factory PlayerRenamedMessage.fromJson(Map<String, Object?> json) =>
      PlayerRenamedMessage(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
      );

  /// Whose name changed. The server's id, so a client can match it to a bean
  /// it is already drawing — or to itself.
  final String id;

  /// The name to show from now on.
  final String name;

  @override
  MessageType get type => MessageType.playerRenamed;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is PlayerRenamedMessage && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(type, id, name);

  @override
  String toString() => 'PlayerRenamedMessage($id: $name)';
}

/// Server to client: the numbers about the world nobody can see for
/// themselves.
///
/// [online] is the one figure interest management deliberately hides. A
/// player can see nine beans and has no way to know whether the event has
/// twelve people in it or three hundred — and "three hundred people are
/// here" is most of why walking into a busy room feels good. So the server
/// says it out loud, once a second, at a cost of about thirty bytes.
@immutable
class WorldStatsMessage extends ProtocolMessage {
  /// Creates a stats message.
  const WorldStatsMessage({required this.online});

  /// Reads a stats message from its JSON form.
  factory WorldStatsMessage.fromJson(Map<String, Object?> json) =>
      WorldStatsMessage(online: readInt(json, 'online'));

  /// How many players are joined to the world right now, everywhere.
  final int online;

  @override
  MessageType get type => MessageType.worldStats;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'online': online};

  @override
  bool operator ==(Object other) =>
      other is WorldStatsMessage && other.online == online;

  @override
  int get hashCode => Object.hash(type, online);

  @override
  String toString() => 'WorldStatsMessage($online online)';
}

/// Server to client: the event's config, now.
///
/// Sent to a player the moment they join and to everybody the moment a
/// moderator changes it. Also sent to an admin socket on authentication, so
/// the editor opens showing what is actually live rather than a blank box.
///
/// Carries the parsed config rather than the raw document, because by the
/// time it is going *out* the question of whether it is readable has already
/// been settled — by the server, once, on the way in.
@immutable
class ConfigMessage extends ProtocolMessage {
  /// Creates a config push.
  const ConfigMessage({required this.config});

  /// Reads a config push from its JSON form.
  factory ConfigMessage.fromJson(Map<String, Object?> json) {
    final value = json['config'];
    return ConfigMessage(
      // Falls back to the defaults rather than throwing, which is this
      // type's whole personality: a client that dropped this message would
      // show a blank front door, and a blank front door is worse than a
      // generic one.
      config: value is Map<String, Object?>
          ? AppConfig.fromJson(value)
          : AppConfig.defaults,
    );
  }

  /// What the event currently says it is.
  final AppConfig config;

  @override
  MessageType get type => MessageType.config;

  @override
  Map<String, Object?> toJson() => {...envelope(), 'config': config.toJson()};

  @override
  bool operator ==(Object other) =>
      other is ConfigMessage && other.config == config;

  @override
  int get hashCode => Object.hash(type, config);

  @override
  String toString() => 'ConfigMessage(${config.worldName})';
}
