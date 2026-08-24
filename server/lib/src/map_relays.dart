import 'package:protocol/protocol.dart';
import 'package:server/src/audit_log.dart';
import 'package:server/src/config_store.dart';
import 'package:server/src/connection_gate.dart';
import 'package:server/src/log.dart';
import 'package:server/src/metrics.dart';
import 'package:server/src/metrics_csv.dart';
import 'package:server/src/moderation.dart';
import 'package:server/src/player_registry.dart';
import 'package:server/src/relay.dart';
import 'package:server/src/spatial_grid.dart';

/// Every world this server is running: one [Relay] per [MapId].
///
/// The golden decision is untouched. A relay is still a relay — this does not
/// simulate anything, arbitrate anything or know what a position means. There
/// are simply two relays now, and this is the thing that owns both, routes a
/// socket to one of them, and answers the two questions that are genuinely
/// about *the server* rather than about one world: how many people are here
/// in total, and where is this session standing.
///
/// Three things are deliberately shared and one is deliberately not:
///
/// - **One [ModerationState] for both maps.** A ban is a ban everywhere; a
///   map is not a hiding place. Sharing the object is what makes that
///   structurally true rather than something two code paths have to remember.
/// - **One [AuditLog], one [MetricsRecorder].** They describe the process,
///   not a room.
/// - **A registry, a grid and a `MapSpec` per map.** This is what makes
///   cross-map visibility *impossible* rather than filtered: a beach client's
///   interest grid contains only beach players, so there is no code path in
///   which a conference bean could be culled *in*.
class MapRelays {
  /// Builds a relay for every map.
  ///
  /// Every knob is the same knob for both worlds, which is the honest default
  /// for a server this size: two independently tuned tick rates would be two
  /// things to reason about and one of them would be wrong.
  MapRelays({
    LogSink log = logLine,
    ConfigStore? config,
    ConnectionGate? gate,
    ModerationState? moderation,
    AuditLog? audit,
    MetricsRecorder? recorder,
    double cellSize = SpatialGrid.defaultCellSize,
    Duration sessionLinger = defaultSessionLinger,
    int neighbourCap = Relay.defaultNeighbourCap,
    Duration tickInterval = Relay.defaultTickInterval,
    Duration joinDeadline = Relay.defaultJoinDeadline,
  }) : moderation = moderation ?? ModerationState(),
       config = config ?? ConfigStore.inMemory(),
       gate = gate ?? ConnectionGate(),
       // Built here rather than left to each relay's own default, so the
       // "one audit log" in the class comment above is structurally true
       // instead of only true when a caller remembers to pass one.
       audit = audit ?? AuditLog(path: null, log: log) {
    for (final id in MapId.values) {
      relays[id] = Relay(
        map: id,
        log: log,
        audit: this.audit,
        recorder: recorder,
        neighbourCap: neighbourCap,
        tickInterval: tickInterval,
        joinDeadline: joinDeadline,
        registry: PlayerRegistry(
          spec: MapSpec.of(id),
          cellSize: cellSize,
          linger: sessionLinger,
          // The same instance in every registry. Not a copy, not a snapshot:
          // a ban recorded by whichever relay the player happened to be on
          // has to be visible to the other one on its very next join.
          moderation: this.moderation,
        ),
        // Joining one map means leaving the other. Wired here rather than
        // inside `Relay`, so the relay never learns that a second world
        // exists.
        onSeated: (sessionId) => evictElsewhere(sessionId, keep: id),
        // Every arrival is handed the event's config right behind their
        // welcome. Encoded here, per join, rather than cached: a moderator
        // can change it between two people walking in.
        joinFrame: () => encodeMessage(this.config.message),
        // Read per join rather than captured, so a window opened while the
        // server is running shuts the door on the very next arrival.
        maintenanceUntil: () => this.config.config.maintenanceUntil,
        // Asked per join, and asked against the count across *every* map. A
        // relay cannot answer this itself: it only knows its own registry,
        // and two half-full worlds are one full event. Wired here for the
        // same reason `onSeated` is — the relay never learns that a second
        // world, or a gate, exists.
        isWorldFull: () => this.gate.isAtPlayerCap(playerCount),
        // The other half of the gate's bookkeeping. The upgrade took the
        // slot; this gives it back, once, from the relay's single teardown
        // funnel.
        onSocketClosed: this.gate.release,
      );
    }
  }

  /// Every moderation decision taken against this server, on any map.
  final ModerationState moderation;

  /// Where every privileged action taken against this server is recorded.
  ///
  /// One log for the process, not one per room: an action against the event
  /// itself — closing it for maintenance — belongs to no map at all.
  final AuditLog audit;

  /// The two ceilings on how much of this server one crowd may occupy.
  ///
  /// One gate for the process, not one per map, for the same reason there is
  /// one [ModerationState]: both ceilings are about *the server*. A per-map
  /// cap would let two half-full worlds add up to twice the crowd the box was
  /// sized for, which is the arithmetic a cap exists to prevent.
  final ConnectionGate gate;

  /// The event's editable content, shared by every world.
  ///
  /// One store, not one per map, for the same reason there is one
  /// [ModerationState]: it describes the *event*, and a beach with its own
  /// tagline would be a second event.
  final ConfigStore config;

  /// Hands every player on every map the config, now.
  ///
  /// Called after a moderator changes it. Uncalled and unthrottled, because
  /// it happens at the rate a human types into a text box.
  void broadcastConfig() {
    final message = config.message;
    for (final relay in all) {
      relay.broadcast(message);
    }
  }

  /// Closes every socket on every map, and answers how many there were.
  ///
  /// The maintenance primitive, and deliberately a blunt one. It records
  /// nothing against anybody: the door is shut by the config, not by a
  /// decision about a person, and the gate on the way back in reads the same
  /// config rather than any state this left behind.
  int disconnectAll() =>
      all.fold(0, (closed, relay) => closed + relay.terminateAll());

  /// The relay for each map.
  final Map<MapId, Relay> relays = {};

  /// The relay for [map].
  ///
  /// Total, because [MapId] is a closed set and every one of them is built in
  /// the constructor. A caller with a *string* should go through
  /// [MapId.fromId], which decides what an unknown map means.
  Relay relayFor(MapId map) => relays[map]!;

  /// Every relay, in map order.
  Iterable<Relay> get all => MapId.values.map(relayFor);

  /// How many people are in the whole server.
  int get playerCount =>
      all.fold(0, (total, relay) => total + relay.playerCount);

  /// How many people are on each map.
  Map<MapId, int> get countsByMap => {
    for (final map in MapId.values) map: relayFor(map).playerCount,
  };

  /// Which map [playerId] is standing on, or `null` if nobody is.
  ///
  /// A linear search over two relays. It stays a linear search because the
  /// number of maps is two and the callers are moderation actions taken by a
  /// human with a thumb, not anything on the tick path.
  MapId? mapOf(String playerId) {
    for (final relay in all) {
      if (relay.registry[playerId] != null) return relay.map;
    }
    return null;
  }

  /// The relay [playerId] is standing on, or `null`.
  Relay? relayOf(String playerId) {
    final map = mapOf(playerId);
    return map == null ? null : relayFor(map);
  }

  /// Everybody on every map, as the admin screen needs to see them.
  List<AdminPlayerSummary> adminPlayerList() => [
    for (final relay in all) ...relay.adminPlayerList(),
  ];

  /// Removes [sessionId] from every map except [keep].
  ///
  /// This is what makes switching maps a *move* rather than a duplication.
  /// It is also the invariant every moderation action leans on: after this
  /// runs, a session is seated in exactly one registry, so "find the player
  /// with this id" has exactly one answer.
  void evictElsewhere(String sessionId, {required MapId keep}) {
    for (final relay in all) {
      if (relay.map == keep) continue;
      relay.evictSession(sessionId);
    }
  }

  /// Starts every relay's tick loop.
  void start() {
    for (final relay in all) {
      relay.start();
    }
  }

  /// Stops every relay's tick loop. Sockets stay open.
  void stop() {
    for (final relay in all) {
      relay.stop();
    }
  }

  /// The body of the public `/metrics` route.
  ///
  /// `players` stays the **grand total** so that everything already reading
  /// this route — the welcome screen's head count, the load test's summary —
  /// keeps meaning what it meant. `byMap` is the new part, and it is what
  /// feeds the two head-counts on the front door: people follow people, and a
  /// map picker without counts sends half the crowd to an empty beach.
  Map<String, Object?> metricsJson() => {
    ...ServerMetrics.mergeJson(all.map((relay) => relay.metrics)),
    'byMap': {
      for (final entry in countsByMap.entries) entry.key.id: entry.value,
    },
  };
}
