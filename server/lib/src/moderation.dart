import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:protocol/protocol.dart';

/// The file bans are written to when nothing overrides it.
const String defaultBanFilePath = 'bans.json';

/// How long a kicked session is refused when nothing overrides it.
///
/// Thirty seconds: long enough that the moderator watches the disruption
/// actually leave the room, short enough that it still reads as a warning
/// shot rather than the ban that exists next to it.
const Duration defaultKickCooldown = Duration(seconds: 30);

/// Where a ban list is kept between restarts.
///
/// An interface, and a tiny one, so the moderation rules can be unit-tested
/// with nothing on disk. The real implementation is a single JSON file: at
/// this scale a database would be more moving parts than the problem has, and
/// a file that can be read with `cat` during an incident is worth something.
abstract class BanStorage {
  /// Reads the banned session ids, or an empty set if there are none.
  ///
  /// Never throws: a missing, empty or corrupt file must not stop the server
  /// from starting. An event with no bans loaded is far better than an event
  /// with no server.
  Set<String> load();

  /// Writes [sessionIds] as the whole ban list.
  ///
  /// Never throws, for the same reason: a read-only disk must not turn a
  /// moderation action into a crash. It degrades to "bans work until the next
  /// restart", which is still a working kill switch.
  void save(Set<String> sessionIds);
}

/// A [BanStorage] that keeps nothing. The default in tests.
class InMemoryBanStorage implements BanStorage {
  /// Creates an empty storage.
  InMemoryBanStorage([Set<String>? initial]) : _bans = {...?initial};

  Set<String> _bans;

  /// What was last saved, for tests to assert on.
  Set<String> get saved => Set.unmodifiable(_bans);

  @override
  Set<String> load() => {..._bans};

  @override
  void save(Set<String> sessionIds) => _bans = {...sessionIds};
}

/// A [BanStorage] backed by one small JSON file.
class FileBanStorage implements BanStorage {
  /// Creates a storage over the file at [path].
  FileBanStorage({this.path = defaultBanFilePath, this.onError});

  /// Where the list is kept.
  final String path;

  /// Called with a one-line description when a read or a write fails.
  final void Function(String message)? onError;

  @override
  Set<String> load() {
    try {
      final file = File(path);
      if (!file.existsSync()) return {};
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! List) return {};
      return decoded.whereType<String>().where(isValidSessionId).toSet();
    } on Object catch (error) {
      onError?.call('could not read the ban list at $path: $error');
      return {};
    }
  }

  @override
  void save(Set<String> sessionIds) {
    try {
      File(path).writeAsStringSync(jsonEncode(sessionIds.toList()));
    } on Object catch (error) {
      onError?.call('could not write the ban list at $path: $error');
    }
  }
}

/// Every moderation decision that has been taken, in one place.
///
/// The point of this class is that it is the *only* place. Moderation state
/// keyed off a player id would have to be re-applied by hand at every join,
/// every reconnect and every rename, and the version that gets missed is the
/// one where a banned person walks back in. Everything here keys on the
/// **session id** instead, which is the one identity that survives a socket
/// dying — so a ban and a mute both outlive a reconnect without anybody
/// remembering to re-apply them.
///
/// Keying on a session id is defeatable: clearing browser storage produces a
/// new one. That is accepted and stated in the phase spec — this is a tool
/// for removing a disruption in ten seconds, not an access control system.
class ModerationState {
  /// Creates the state, loading any bans [storage] already holds.
  ///
  /// [now] is injectable so the kick cooldown can be tested without waiting
  /// thirty seconds. [kickCooldown] is how long a kicked session is kept out.
  ModerationState({
    BanStorage? storage,
    DateTime Function() now = DateTime.now,
    this.kickCooldown = defaultKickCooldown,
  }) : _storage = storage ?? InMemoryBanStorage(),
       // A named parameter cannot be private, so this cannot be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _now = now {
    _banned.addAll(_storage.load());
  }

  /// How long a kicked session is refused before it may come back.
  ///
  /// Not persisted, and deliberately not a ban: it exists to outlive the
  /// client's own reconnect backoff, which is measured in hundreds of
  /// milliseconds. Without it a kick disconnects a socket that reconnects
  /// under the same session id before anybody notices, and the only visible
  /// effect on a neighbour's screen is a bean blinking.
  final Duration kickCooldown;

  final BanStorage _storage;
  final DateTime Function() _now;
  final Set<String> _banned = {};

  /// Kicked sessions, mapped to the moment they may come back.
  final Map<String, DateTime> _kickedUntil = {};

  /// Kicked sessions, mapped to the names they may not wear again.
  ///
  /// Normalised on the way in, because "Ada", " ada " and "ADA" are one name
  /// to everybody looking at a bean and would otherwise be three ways round
  /// this.
  final Map<String, Set<String>> _blockedNames = {};

  /// Banned sessions, mapped to the name they were banned under.
  ///
  /// **In memory only, on purpose.** The list on disk holds session ids and
  /// nothing else: a file of the names people were removed for is a document
  /// somebody then has to own, and it would outlive the event that needed it.
  /// A ban taken during this run is labelled in the admin list; one loaded
  /// from disk is a handle and a date the server no longer knows.
  ///
  /// That is the right trade because of *when* unbans happen. A moderator
  /// changes their mind about a ban minutes after taking it, in the same run,
  /// while the room is still going.
  final Map<String, String> _bannedNames = {};

  /// Banned sessions, mapped to when the ban was taken. In memory, as above.
  final Map<String, DateTime> _bannedAt = {};

  /// Muted sessions, mapped to the name they chose.
  ///
  /// The chosen name is kept so an unmute can give it back, and so the admin
  /// list can go on showing what was muted rather than a wall of "Guest".
  final Map<String, String> _mutedNames = {};

  /// How many sessions are banned.
  int get bannedCount => _banned.length;

  /// How many sessions have had their name taken away.
  int get mutedCount => _mutedNames.length;

  /// How many kick cooldowns are being remembered, expired ones included.
  int get cooldownCount => _kickedUntil.length;

  /// How many sessions have at least one name taken off them.
  int get blockedNameCount => _blockedNames.length;

  /// Whether [sessionId] may not join.
  bool isBanned(String sessionId) => _banned.contains(sessionId);

  /// Whether [sessionId] is currently showing as [mutedDisplayName].
  bool isNameMuted(String sessionId) => _mutedNames.containsKey(sessionId);

  /// The name [sessionId] chose, muted or not, or `null` if not muted.
  String? chosenNameOf(String sessionId) => _mutedNames[sessionId];

  /// Refuses [sessionId] for [kickCooldown], starting now.
  ///
  /// Kept here rather than on the socket for the same reason bans and mutes
  /// are: the socket is the one thing a kick destroys, so anything remembered
  /// on it is forgotten by the client's next connection attempt.
  ///
  /// A zero cooldown records nothing, which makes "kick with no cooling-off
  /// period" a supported configuration rather than a special case downstream.
  void recordKick(String sessionId) {
    if (kickCooldown <= Duration.zero) return;
    final now = _now();
    // Swept here rather than on a timer. Kicks are rare and the map is small,
    // so the cheapest place to keep it from growing for the length of the
    // event is the write that grows it.
    _kickedUntil.removeWhere((_, until) => !until.isAfter(now));
    _kickedUntil[sessionId] = now.add(kickCooldown);
  }

  /// How long until [sessionId] may rejoin, or `null` if it may right now.
  ///
  /// Never returns zero or a negative duration: an expired entry is dropped
  /// and read as "come in", so callers get one question answered, not two.
  Duration? kickCooldownLeft(String sessionId) {
    final until = _kickedUntil[sessionId];
    if (until == null) return null;

    final left = until.difference(_now());
    if (left <= Duration.zero) {
      _kickedUntil.remove(sessionId);
      return null;
    }
    return left;
  }

  /// Stops [sessionId] wearing [name] again for the rest of this run.
  ///
  /// The other half of a kick, and the half that makes it worth doing. A
  /// cooldown alone means the person is back in thirty seconds under the
  /// name they were removed for, which answers nothing — kicks in a world
  /// with no chat are almost always about a name.
  ///
  /// Deliberately *not* persisted, unlike a ban. A ban is a decision about a
  /// person and has to survive a restart; this is a decision about a string,
  /// it expires with the event, and a file of them would be a list of slurs
  /// on disk that somebody has to own.
  void blockName(String sessionId, String name) {
    final normalized = normalizeName(name).toLowerCase();
    if (normalized.isEmpty) return;
    _blockedNames.putIfAbsent(sessionId, () => <String>{}).add(normalized);
  }

  /// Whether [sessionId] has been told it may not use [name].
  ///
  /// Compared normalised, so changing the spacing or the capitals is not a
  /// way round it. Anything more — leetspeak, lookalike characters — is a
  /// content-moderation arms race this project is explicitly not in; the
  /// moderator can kick again, and the second kick blocks the new spelling
  /// too.
  bool isNameBlocked(String sessionId, String name) =>
      _blockedNames[sessionId]?.contains(
        normalizeName(name).toLowerCase(),
      ) ??
      false;

  /// Bans [sessionId] and persists the list.
  ///
  /// Persisted on the way out rather than on a timer: a ban that is lost
  /// because the server restarted forty seconds later is a ban that did not
  /// happen, and the person it was for is back in the room.
  ///
  /// [name] labels the ban in the admin list and is kept **in memory only**;
  /// see [_bannedNames].
  void ban(String sessionId, {String name = ''}) {
    if (!_banned.add(sessionId)) return;
    if (name.isNotEmpty) _bannedNames[sessionId] = name;
    _bannedAt[sessionId] = _now();
    _storage.save(_banned);
  }

  /// Lifts a ban on [sessionId] and persists the list.
  ///
  /// Reachable from the admin screen through [unbanByHandle], which is the
  /// only form that can be reached from *outside* the server: this one takes
  /// the session id, and a session id never goes on the wire.
  void unban(String sessionId) {
    if (!_banned.remove(sessionId)) return;
    _bannedNames.remove(sessionId);
    _bannedAt.remove(sessionId);
    _storage.save(_banned);
  }

  /// The handle [sessionId]'s ban is shown and lifted by.
  ///
  /// A truncated SHA-256, which buys three things at once. It is **one-way**,
  /// so the admin screen can name a ban without ever holding the bearer token
  /// behind it. It is **deterministic**, so a ban read back off disk after a
  /// restart has the same handle it had before — without that, a persisted
  /// ban could never be lifted from the screen. And it needs **nothing
  /// stored**, so the ban file keeps the shape it has always had and there is
  /// no migration.
  ///
  /// Sixteen hex characters. Collisions would have to be found across the
  /// handful of bans one event takes, and the worst a collision could do is
  /// lift the wrong ban — for an authorised moderator who can ban again in
  /// one tap.
  static String banHandleFor(String sessionId) =>
      sha256.convert(utf8.encode(sessionId)).toString().substring(0, 16);

  /// Every ban in force, newest first, as the admin screen needs to see them.
  ///
  /// Bans this run knows about come first, most recent first; the ones it has
  /// forgotten — loaded from disk on start — sort after them by handle, so
  /// the order is stable between two pushes a second apart.
  List<BannedSession> get bans {
    final remembered = <BannedSession>[];
    final forgotten = <BannedSession>[];
    for (final sessionId in _banned) {
      final row = BannedSession(
        id: banHandleFor(sessionId),
        name: _bannedNames[sessionId] ?? '',
        bannedAt: _bannedAt[sessionId],
      );
      (row.bannedAt == null ? forgotten : remembered).add(row);
    }
    remembered.sort((a, b) => b.bannedAt!.compareTo(a.bannedAt!));
    forgotten.sort((a, b) => a.id.compareTo(b.id));
    return [...remembered, ...forgotten];
  }

  /// Lifts the ban named by [handle], reporting the name it was under.
  ///
  /// Returns `null` when no ban answers to that handle — a row tapped a
  /// moment after somebody else lifted it, or a handle that was never one.
  /// The empty string is a real answer: the ban was lifted and this server
  /// no longer remembers whose it was.
  String? unbanByHandle(String handle) {
    for (final sessionId in _banned) {
      if (banHandleFor(sessionId) != handle) continue;
      final name = _bannedNames[sessionId] ?? '';
      unban(sessionId);
      return name;
    }
    return null;
  }

  /// Takes [sessionId]'s name away, remembering [chosenName] for the unmute.
  ///
  /// Muting an already-muted session does nothing, which matters: without the
  /// guard, a second mute would record [mutedDisplayName] as the chosen name
  /// and the unmute would hand it back as their real one.
  void muteName(String sessionId, String chosenName) {
    _mutedNames.putIfAbsent(sessionId, () => chosenName);
  }

  /// Gives [sessionId] their name back, returning it, or `null` if not muted.
  String? unmuteName(String sessionId) => _mutedNames.remove(sessionId);

  /// The name the world should see for [sessionId], who asked for [chosen].
  ///
  /// The single funnel every name goes through. The registry calls this when
  /// it seats a join, which is what makes a mute survive a reconnect: a muted
  /// player who comes back under a brand-new name is still a Guest, and the
  /// new name quietly replaces the one held for the unmute.
  String effectiveName(String sessionId, String chosen) {
    if (!_mutedNames.containsKey(sessionId)) return chosen;
    _mutedNames[sessionId] = chosen;
    return mutedDisplayName;
  }
}
