import 'package:meta/meta.dart';
import 'package:protocol/src/json_reader.dart';
import 'package:protocol/src/map_id.dart';

/// The name a muted player is shown under, to everybody.
///
/// Lives in `protocol/` rather than in the server because both ends need to
/// agree on what it means: the server writes it into the world, and the admin
/// screen has to be able to say "this person is currently showing as Guest"
/// without guessing at the server's placeholder.
///
/// Deliberately not unique per player. Two muted people both reading "Guest"
/// is the point — the muted name is meant to carry no information at all.
const String mutedDisplayName = 'Guest';

/// Something an admin can do to one player.
///
/// A closed set, like every other decision in `protocol/`: the admin screen
/// renders a different confirmation per action and the audit log records
/// which one happened, and neither should be pattern-matching a string.
enum AdminAction {
  /// Disconnect them. They may rejoin — a warning shot, not a removal.
  kick('kick'),

  /// Disconnect them and refuse the session for the rest of the event.
  ban('ban'),

  /// Replace their displayed name with [mutedDisplayName], without
  /// disconnecting them.
  muteName('muteName'),

  /// Give a muted player their chosen name back.
  ///
  /// Present because the most likely moderation mistake is muting the wrong
  /// row on a phone, and a mute with no way back turns a fat finger into a
  /// permanent one.
  unmuteName('unmuteName'),

  /// Close the event to attendees until a stated moment.
  maintenanceOn('maintenanceOn'),

  /// Open it again, before the stated moment has arrived.
  maintenanceOff('maintenanceOff'),

  /// Take a ban off, letting somebody back in.
  ///
  /// The only action here that names a **ban** rather than a player: by the
  /// time it is taken the person is not in the world, which is the whole
  /// point of the ban being on.
  unban('unban');

  const AdminAction(this.wireName);

  /// The string this action travels as.
  final String wireName;

  /// Returns the action named by [wireName], or `null` if it is not one.
  static AdminAction? fromWireName(String? wireName) {
    for (final action in AdminAction.values) {
      if (action.wireName == wireName) return action;
    }
    return null;
  }
}

/// Why the server refused an admin message.
///
/// Separate from [AdminAction] because these are answers, not requests, and
/// the admin screen shows a different thing for each: a wrong token sends you
/// back to the token field, a stale row just needs the list to refresh.
enum AdminError {
  /// No token, or the wrong one. The only error a non-admin should ever see.
  unauthorized('unauthorized'),

  /// The target is not in the world any more — usually a stale row that was
  /// tapped a second after the player left.
  unknownPlayer('unknownPlayer'),

  /// The message did not carry what it needed to.
  badRequest('badRequest');

  const AdminError(this.wireName);

  /// The string this reason travels as.
  final String wireName;

  /// Returns the error named by [wireName], or [AdminError.badRequest].
  static AdminError fromWireName(String? wireName) {
    for (final error in AdminError.values) {
      if (error.wireName == wireName) return error;
    }
    return AdminError.badRequest;
  }
}

/// One row of the admin's ban list.
///
/// Deliberately **not** carrying the session id, exactly like
/// [AdminPlayerSummary]. A session id is a bearer token — anybody holding one
/// can walk into that player's bean — so it does not leave the server even to
/// an admin who is already trusted. [id] here is a one-way handle derived
/// from it: stable across restarts, so a ban loaded from disk can still be
/// lifted, and useless to anybody who obtains it.
@immutable
class BannedSession {
  /// Creates a ban row.
  const BannedSession({required this.id, this.name = '', this.bannedAt});

  /// Reads a ban row from its JSON form.
  factory BannedSession.fromJson(Map<String, Object?> json) => BannedSession(
    id: readString(json, 'id'),
    // Absent reads as "we no longer know", which is a real state: see [name].
    name: json['name'] is String ? json['name']! as String : '',
    bannedAt: DateTime.tryParse(
      json['bannedAt'] is String ? json['bannedAt']! as String : '',
    )?.toUtc(),
  );

  /// The handle this ban is lifted by. Not the session id; see the class doc.
  final String id;

  /// The name they were banned under, or `''` if this server no longer knows.
  ///
  /// Empty is the normal state for a ban that was made **before the current
  /// process started**. The ban list on disk holds ids and nothing else, on
  /// purpose: a file of the names people were removed for is a document
  /// somebody then has to own, and it would outlive the event that needed it.
  /// Names are held in memory for the run that took the ban, which is the run
  /// in which somebody is going to change their mind about it.
  final String name;

  /// When the ban was taken, or `null` if this server no longer knows.
  final DateTime? bannedAt;

  /// Whether this server still remembers who this ban was for.
  bool get isRemembered => name.isNotEmpty;

  /// Returns the JSON form of this row.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'bannedAt': bannedAt?.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is BannedSession &&
      other.id == id &&
      other.name == name &&
      other.bannedAt == bannedAt;

  @override
  int get hashCode => Object.hash(id, name, bannedAt);

  @override
  String toString() => 'BannedSession($id, ${isRemembered ? name : "unknown"})';
}

/// One row of the admin's live player list.
///
/// Deliberately *not* a `PlayerState` and deliberately missing the session
/// id. The session id is a bearer token — anybody holding one can walk into
/// that player's bean — so it never leaves the server, not even to an admin
/// who is already trusted. The server bans by session id internally; the
/// admin screen only ever names a player id.
@immutable
class AdminPlayerSummary {
  /// Creates a summary.
  const AdminPlayerSummary({
    required this.id,
    required this.name,
    required this.isNameMuted,
    required this.x,
    required this.y,
    this.map = MapId.conference,
  });

  /// Reads a summary from its JSON form.
  factory AdminPlayerSummary.fromJson(Map<String, Object?> json) =>
      AdminPlayerSummary(
        id: readString(json, 'id'),
        name: readString(json, 'name'),
        isNameMuted: readBool(json, 'isNameMuted'),
        x: readDouble(json, 'x'),
        y: readDouble(json, 'y'),
        // Absent reads as the conference, which is what every summary
        // written before Phase 10 meant. A roster is the last place to
        // start refusing rows over a missing field.
        map: MapId.fromId(json['map'] as String?),
      );

  /// The server-assigned player id, and the only handle an admin action uses.
  final String id;

  /// The name this player *chose*, muted or not.
  ///
  /// The chosen name rather than the displayed one on purpose: an admin
  /// looking at a muted row still needs to see what they muted, both to
  /// judge whether the mute was right and to find the person again.
  final String name;

  /// Whether everybody else currently sees them as [mutedDisplayName].
  final bool isNameMuted;

  /// Where they are standing, so an admin can find them in the room.
  final double x;

  /// Where they are standing, so an admin can find them in the room.
  final double y;

  /// Which map they are standing on.
  ///
  /// The coordinates above are only meaningful next to this: the two maps are
  /// separate coordinate spaces, so "600, 310" is the middle of the beach's
  /// sand and also a spot in the conference's food court.
  final MapId map;

  /// The name everybody else in the world currently sees above this bean.
  String get displayName => isNameMuted ? mutedDisplayName : name;

  /// Returns the JSON form of this summary.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'isNameMuted': isNameMuted,
    'x': x,
    'y': y,
    'map': map.id,
  };

  @override
  bool operator ==(Object other) =>
      other is AdminPlayerSummary &&
      other.id == id &&
      other.name == name &&
      other.isNameMuted == isNameMuted &&
      other.x == x &&
      other.y == y &&
      other.map == map;

  @override
  int get hashCode => Object.hash(id, name, isNameMuted, x, y, map);

  @override
  String toString() => 'AdminPlayerSummary($id, $displayName, ${map.id})';
}
