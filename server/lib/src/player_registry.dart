import 'dart:math';

import 'package:protocol/protocol.dart';
import 'package:server/src/moderation.dart';
import 'package:server/src/spatial_grid.dart';

/// How long a player's seat is held after their socket dies.
///
/// This is the whole reason a wifi blip is survivable. Without it, the
/// sequence "socket dies, player removed, client reconnects" hands somebody a
/// brand-new bean at a random spawn point on the far side of the map — which
/// is technically a working reconnect and feels exactly like being kicked.
///
/// Ninety seconds is a judgement call: long enough to cover a lift, a tunnel,
/// or a phone that locked itself, short enough that somebody who genuinely
/// left is not still holding a seat when the room turns over.
const Duration defaultSessionLinger = Duration(seconds: 90);

/// How a join was satisfied.
///
/// The distinction is not cosmetic — it is what the relay logs, what the
/// tests assert on, and the difference between a working reconnect and a
/// world quietly filling up with abandoned duplicate beans.
enum SeatKind {
  /// A session the server has never seen: a new player, new id, new spawn.
  fresh,

  /// A session that is *still live* — the client came back before the server
  /// noticed the old socket had died. The seat is kept and the socket under
  /// it is swapped. This is the re-seat race, and on a flaky network it is
  /// the common case rather than the exotic one.
  reseated,

  /// A session whose socket had already been reaped, returning inside the
  /// linger window. Same id, same position, same bean.
  resumed,
}

/// What [PlayerRegistry.seat] did.
typedef Seat = ({
  /// The player occupying the seat, after the join was applied.
  PlayerState player,

  /// How the join was satisfied.
  SeatKind kind,

  /// Whether the name, colour or cosmetic changed as a result.
  ///
  /// Only ever true on a re-seat or a resume, and it matters because a
  /// neighbour is told a player's metadata exactly once — when they appear.
  /// Somebody who reconnects under a new name would otherwise keep their old
  /// one on every screen but their own.
  bool appearanceChanged,
});

/// Returns a display name that is safe to hand to other clients.
///
/// Only normalisation lives here now. The rules that *reject* a name — length,
/// character whitelist, wordlist — are [validateName] in `protocol/`, run by
/// the relay before a join ever reaches this class, so the client and the
/// server cannot enforce two different ideas of an acceptable name.
String sanitizeName(String raw) => normalizeName(raw);

/// Returns an opaque 32-bit ARGB colour.
///
/// A client can put any int on the wire, including a negative one or one with
/// a zero alpha channel — an invisible bean would be a free invisibility
/// cloak. Masking to 32 bits and forcing full alpha closes both.
int sanitizeColor(int raw) => (raw & 0xFFFFFF) | 0xFF000000;

/// Who is currently in the world.
///
/// Deliberately free of sockets, shelf and JSON: this is the state machine
/// that decides who exists and where they are, and it is unit-tested on its
/// own. The relay layer above it owns the plumbing.
///
/// The registry stores positions but never *computes* them — the server is a
/// relay, not a simulator. It only clamps what a client reports into the
/// world bounds.
///
/// It also owns the [SpatialGrid] index over those positions. The grid could
/// have lived a layer up, but then two structures would have to be kept in
/// step by hand and a single missed update would silently make somebody
/// invisible. Here there is one write path, so they cannot drift.
class PlayerRegistry {
  /// Creates an empty registry.
  ///
  /// [random] is injectable so tests get deterministic spawn points.
  /// [cellSize] is the interest grid's cell edge, in world units.
  /// [now] is injectable so the linger window can be tested without waiting.
  /// [moderation] is what decides whether a session may sit down at all and
  /// what name it sits down under; an empty one is created when omitted.
  /// [spec] is the map this registry seats people into: it decides where
  /// spawn is and what a position is clamped to. [idPrefix] keeps player ids
  /// unique **across** registries — two registries each counting from `p1`
  /// would hand two different people the same id, and the admin roster is a
  /// union of both.
  PlayerRegistry({
    Random? random,
    double cellSize = SpatialGrid.defaultCellSize,
    this.linger = defaultSessionLinger,
    DateTime Function() now = DateTime.now,
    ModerationState? moderation,
    this.spec = MapSpec.conference,
    String? idPrefix,
  }) : idPrefix = idPrefix ?? defaultIdPrefix(spec.id),
       _random = random ?? Random(),
       moderation = moderation ?? ModerationState(),
       // A named parameter cannot be private, so this cannot be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _now = now,
       grid = SpatialGrid(cellSize: cellSize);

  /// The default id prefix for [map]'s registry.
  ///
  /// The conference keeps the bare `p` it has always had, so every id in
  /// every log, test and audit line from before Phase 10 still reads the
  /// same. A second map cannot do that, because ids have to be unique across
  /// the whole server.
  static String defaultIdPrefix(MapId map) =>
      map == MapId.conference ? 'p' : '${map.id[0]}p';

  /// Which map this registry seats people into.
  final MapSpec spec;

  /// What every player id created here starts with.
  final String idPrefix;

  /// The interest index over [players]. Read-only as far as callers go —
  /// every write goes through [seat], [move] and [remove].
  final SpatialGrid grid;

  /// How long a departed session's seat is held for its return.
  final Duration linger;

  /// Every moderation decision taken against the world.
  ///
  /// The registry owns it rather than the relay because this is the layer
  /// that *writes names into the world*. Putting the mute anywhere else would
  /// mean a second place that has to remember to apply it, and the join path
  /// that forgets is the one where a muted name comes back.
  final ModerationState moderation;

  final Random _random;
  final DateTime Function() _now;
  final Map<String, PlayerState> _players = {};

  /// Session id to player id, for everybody currently in the world.
  final Map<String, String> _seatOfSession = {};

  /// Player id back to session id, so a departure knows what to hold.
  final Map<String, String> _sessionOfSeat = {};

  /// Seats held for a session whose socket has died but may come back.
  final Map<String, _HeldSeat> _held = {};

  int _nextId = 0;

  /// How many players are currently in the world.
  int get count => _players.length;

  /// Everyone currently in the world, in join order.
  List<PlayerState> get players => List.unmodifiable(_players.values);

  /// The player with [id], or `null` if they are not (or no longer) here.
  PlayerState? operator [](String id) => _players[id];

  /// How many seats are being held for sessions that may come back.
  int get heldSeatCount => _held.length;

  /// The player id currently seated for [sessionId], if any.
  String? seatOfSession(String sessionId) => _seatOfSession[sessionId];

  /// The session id behind player [id], if they are seated.
  ///
  /// The bridge moderation needs and nothing else uses: an admin names a
  /// player id, and every moderation decision is stored against the session
  /// id so that it outlives the socket. The mapping stays inside the server —
  /// the id itself is a bearer token and never goes on the wire.
  String? sessionOf(String id) => _sessionOfSeat[id];

  /// Renames the seated player [id], returning their new state.
  ///
  /// Returns `null` when they are not here. Used only by moderation: a
  /// player cannot rename themselves without rejoining, which is what makes
  /// this a safe thing to expose.
  PlayerState? rename(String id, String name) {
    final player = _players[id];
    if (player == null) return null;
    final renamed = PlayerState(
      id: player.id,
      name: name,
      color: player.color,
      cosmetic: player.cosmetic,
      x: player.x,
      y: player.y,
      hasBoard: player.hasBoard,
    );
    _players[id] = renamed;
    return renamed;
  }

  /// Records that [id] is or is not carrying a board, returning their state.
  ///
  /// Returns `null` when [id] is not in the registry — a board message from a
  /// connection that never joined, or one that has already left. Same shape
  /// as [move], and for the same reason: the caller has to be able to tell
  /// "recorded" from "there is nobody here to record it against".
  ///
  /// The server has no idea what a board *is*. It stores a bool against a
  /// player and repeats it to their neighbours, which is the whole of the
  /// relay's involvement in the feature.
  PlayerState? setBoard(String id, {required bool hasBoard}) {
    final player = _players[id];
    if (player == null) return null;
    if (player.hasBoard == hasBoard) return player;
    final updated = PlayerState(
      id: player.id,
      name: player.name,
      color: player.color,
      cosmetic: player.cosmetic,
      x: player.x,
      y: player.y,
      hasBoard: hasBoard,
    );
    _players[id] = updated;
    return updated;
  }

  /// Drops any seat being held for [sessionId].
  ///
  /// Called when a session is banned. Without it a ban would remove the
  /// player and then the linger window would hold their seat, their position
  /// and their name warm for ninety seconds — for somebody who is not
  /// allowed to come back and use it.
  void forgetSession(String sessionId) => _held.remove(sessionId);

  /// Seats a join, creating, re-seating or resuming as the session demands.
  ///
  /// The player id and the spawn point are assigned here, never taken from
  /// the client: a client that picked its own id could impersonate somebody.
  /// The *session* id does come from the client, and that is the point — it
  /// is how a returning device says "I was already here", and the worst it
  /// buys a liar is somebody else's bean at a conference.
  ///
  /// Position is never re-randomised for a returning session. Walking back
  /// from a two-second wifi drop to find yourself across the map is exactly
  /// what this mechanism exists to prevent.
  Seat seat(JoinMessage join) {
    _sweepHeldSeats();

    // The one funnel every display name goes through. A muted session gets
    // the placeholder here, on every join, reconnect and resume alike — so a
    // mute survives a wifi drop without any code path having to reapply it.
    final name = moderation.effectiveName(
      join.sessionId,
      sanitizeName(join.name),
    );
    final color = sanitizeColor(join.color);

    final liveId = _seatOfSession[join.sessionId];
    if (liveId != null) {
      final existing = _players[liveId]!;
      final updated = PlayerState(
        id: liveId,
        name: name,
        color: color,
        cosmetic: join.cosmetic,
        x: existing.x,
        y: existing.y,
        // The board survives a re-seat for the same reason the position
        // does: this is the same person, mid-session. The client
        // re-announces it after every welcome anyway, so this only closes
        // the window between the two.
        hasBoard: existing.hasBoard,
      );
      _players[liveId] = updated;
      return (
        player: updated,
        kind: SeatKind.reseated,
        appearanceChanged: _looksDifferent(existing, updated),
      );
    }

    final held = _held.remove(join.sessionId);
    if (held != null) {
      final was = held.player;
      final resumed = PlayerState(
        id: was.id,
        name: name,
        color: color,
        cosmetic: join.cosmetic,
        x: was.x,
        y: was.y,
        hasBoard: was.hasBoard,
      );
      _players[resumed.id] = resumed;
      _seatOfSession[join.sessionId] = resumed.id;
      _sessionOfSeat[resumed.id] = join.sessionId;
      grid.upsert(resumed.id, resumed.x, resumed.y);
      return (
        player: resumed,
        kind: SeatKind.resumed,
        appearanceChanged: _looksDifferent(was, resumed),
      );
    }

    final id = '$idPrefix${++_nextId}';
    final spawn = _spawnOnRing();
    final player = PlayerState(
      id: id,
      name: name,
      color: color,
      cosmetic: join.cosmetic,
      x: spawn.x,
      y: spawn.y,
    );
    _players[id] = player;
    _seatOfSession[join.sessionId] = id;
    _sessionOfSeat[id] = join.sessionId;
    grid.upsert(id, player.x, player.y);
    return (player: player, kind: SeatKind.fresh, appearanceChanged: false);
  }

  /// Everyone whose bean is near ([x], [y]), excluding [exceptId].
  ///
  /// This is the query the tick loop runs once per connected client, so it
  /// returns states rather than ids: the caller needs positions anyway, and
  /// a second map lookup per neighbour per tick is real money at 200 players
  /// × 15Hz.
  List<PlayerState> near(double x, double y, {String? exceptId}) {
    final result = <PlayerState>[];
    for (final id in grid.near(x, y)) {
      if (id == exceptId) continue;
      final player = _players[id];
      if (player != null) result.add(player);
    }
    return result;
  }

  /// Records a reported position for [id] and returns the updated state.
  ///
  /// Returns `null` when [id] is not in the registry — a move from a
  /// connection that never joined, or one that has already left. The position
  /// is clamped into the world rather than rejected: a client whose clamp
  /// maths differs by a pixel should not be dropped.
  PlayerState? move(String id, double x, double y) {
    final player = _players[id];
    if (player == null) return null;
    final moved = player.movedTo(spec.clampX(x), spec.clampY(y));
    _players[id] = moved;
    grid.upsert(id, moved.x, moved.y);
    return moved;
  }

  /// Removes [id] from the world and returns their last state.
  ///
  /// Returns `null` if they were not here — normal, not an error: a socket
  /// can die before its join ever arrived.
  ///
  /// The player leaves the world *immediately*, because everybody else is
  /// looking at their bean and it must not stand there as a ghost. Their seat
  /// is held separately for [linger], which costs nobody anything: a held
  /// seat is a map entry, not a player, so it is not in the grid, not in a
  /// snapshot, and not on anybody's screen.
  PlayerState? remove(String id) {
    grid.remove(id);
    final player = _players.remove(id);
    final sessionId = _sessionOfSeat.remove(id);
    if (sessionId != null) {
      _seatOfSession.remove(sessionId);
      if (player != null) {
        _held[sessionId] = _HeldSeat(
          player: player,
          expiresAt: _now().add(linger),
        );
      }
    }
    _sweepHeldSeats();
    return player;
  }

  /// Drops held seats whose window has closed.
  ///
  /// Swept on join and on leave rather than on a timer: those are the only
  /// two moments the map can grow or matter, and a 15Hz tick has better
  /// things to do than walk a map of people who are not here.
  void _sweepHeldSeats() {
    if (_held.isEmpty) return;
    final now = _now();
    _held.removeWhere((_, seat) => !seat.expiresAt.isAfter(now));
  }

  static bool _looksDifferent(PlayerState before, PlayerState after) =>
      before.name != after.name ||
      before.color != after.color ||
      before.cosmetic != after.cosmetic;

  /// Picks a point on this map's spawn ring.
  ///
  /// Everybody arrives in the atrium, because the whole social premise is
  /// that the first thing you see is other people — spawning at a random
  /// point in a 1600×1200 world would mean most arrivals see an empty room
  /// and conclude nobody came.
  ///
  /// A ring rather than a point, for two reasons: the credit pillar stands at
  /// the exact centre, and a hundred people arriving at once should not land
  /// in one pile. The radius is jittered slightly so the ring reads as a
  /// crowd rather than as a summoning circle.
  ({double x, double y}) _spawnOnRing() {
    final angle = _random.nextDouble() * 2 * pi;
    final radius = spec.spawnRingRadius * (0.75 + _random.nextDouble() * 0.25);
    return (
      x: spec.spawnCenterX + cos(angle) * radius,
      y: spec.spawnCenterY + sin(angle) * radius,
    );
  }
}

/// A seat kept warm for a session whose socket died.
class _HeldSeat {
  _HeldSeat({required this.player, required this.expiresAt});

  /// Who sat here, including where they were standing.
  final PlayerState player;

  /// When this seat stops being theirs.
  final DateTime expiresAt;
}
