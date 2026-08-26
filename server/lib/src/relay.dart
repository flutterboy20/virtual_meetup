import 'dart:async';

import 'package:protocol/protocol.dart';
import 'package:server/src/audit_log.dart';
import 'package:server/src/emote_limiter.dart';
import 'package:server/src/log.dart';
import 'package:server/src/metrics.dart';
import 'package:server/src/metrics_csv.dart';
import 'package:server/src/moderation.dart';
import 'package:server/src/nearest.dart';
import 'package:server/src/player_registry.dart';
import 'package:server/src/token_bucket.dart';

/// What a moderation command did: who it hit, and what they were called.
///
/// The name is carried out of the command rather than looked up afterwards,
/// because by the time a kick returns the player is gone from the registry
/// and there is nothing left to look up.
typedef ModerationOutcome = ({String targetId, String targetName});

/// One client's socket, reduced to the two things the relay needs.
///
/// The relay is written against this instead of `WebSocketChannel` so the
/// join/tick/leave logic can be tested with a fake in a plain unit test — no
/// HTTP server, no ports, no timing.
abstract class PlayerConnection {
  /// Sends one already-encoded message to this client.
  void send(String data);

  /// Closes this socket.
  void close();
}

/// The relay: it forwards state between clients and never simulates any.
///
/// The whole server is this class plus a registry. Clients own their own
/// positions; this only records what they report and repeats it to the people
/// near them. There is no physics, no prediction, and no authority here —
/// that is the project's central architecture decision, not an omission.
///
/// Since Phase 3 the outbound side is a **fixed tick**, not a reaction to
/// inbound messages. Every [tickInterval] the relay walks its sessions and
/// sends each one a snapshot of the players near it. Two consequences, both
/// deliberate:
///
/// - **Inbound rate stops driving outbound rate.** Somebody sending moves
///   twice as fast costs the server twice as much to *receive* and nothing
///   extra to send. Under the old broadcast their extra sends multiplied
///   across every other client.
/// - **Sends coalesce.** A player who moved four times between two ticks is
///   sent once, at their latest position. The intermediate positions were
///   never going to be drawn.
class Relay {
  /// Creates a relay.
  Relay({
    PlayerRegistry? registry,
    LogSink log = logLine,
    ServerMetrics? metrics,
    EmoteLimiter? emoteLimiter,
    EmoteLimiter? boardLimiter,
    AuditLog? audit,
    MetricsRecorder? recorder,
    this.map = MapId.conference,
    this.onSeated,
    this.joinFrame,
    this.maintenanceUntil,
    this.isWorldFull,
    this.onSocketClosed,
    this.newInboundBucket,
    this.neighbourCap = defaultNeighbourCap,
    this.joinDeadline = defaultJoinDeadline,
    Duration tickInterval = defaultTickInterval,
    this.reportInterval = defaultReportInterval,
    this.statsInterval = defaultStatsInterval,
    Duration sessionLinger = defaultSessionLinger,
    SecurityLog? securityLog,
  }) : tickInterval = tickInterval,
       // Wraps the same sink the operational lines go to, so a test that
       // captures `log` still sees these — just no longer without limit.
       _security = securityLog ?? SecurityLog(log: log),
       registry =
           registry ??
           PlayerRegistry(linger: sessionLinger, spec: MapSpec.of(map)),
       // The budget the metrics judge an overrun against is this relay's own
       // tick interval, not a constant. Phase 7 sweeps the tick rate, and a
       // hardcoded 66ms would quietly report every tick of a 30Hz run as
       // fine and every tick of a 10Hz run as an overrun.
       metrics = metrics ?? ServerMetrics(tickBudget: tickInterval),
       recorder = recorder ?? MetricsRecorder(path: null),
       emotes = emoteLimiter ?? EmoteLimiter(),
       // The same token bucket, tuned harder. A board toggle is exactly what
       // this class is for — a cheap client message that fans out to every
       // neighbour — but unlike applause there is no honest reason to flip it
       // twice in a second, so the burst is smaller and the refill slower.
       boards =
           boardLimiter ??
           EmoteLimiter(
             burst: defaultBoardBurst,
             refill: defaultBoardRefill,
           ),
       // No file by default: a relay built in a test should not scribble an
       // audit log into whatever directory the test happened to run in. The
       // real one is passed in from `bin/server.dart`.
       audit = audit ?? AuditLog(path: null, log: log),
       // A named parameter cannot be private, so this cannot be an
       // initializing formal.
       _log = log;

  /// The gap between snapshots: ~15Hz.
  ///
  /// Fast enough that 100ms of client-side interpolation always has two
  /// samples to work between, slow enough that the outbound cost is a
  /// quarter of what per-move broadcasting was. Phase 7 tunes it against
  /// real numbers; this is a starting value, not a truth.
  static const Duration defaultTickInterval = Duration(milliseconds: 66);

  /// The largest inbound frame a *player* socket may send, in bytes.
  ///
  /// The biggest legitimate client frame is a `join`, at roughly 300 bytes.
  /// Four kibibytes is more than ten times that, so no honest client is ever
  /// near it, and it is small enough that a frame designed to be expensive is
  /// refused before it is looked at.
  ///
  /// **The second of two guards at this number, and the weaker one.** By the
  /// time application code sees a frame the allocation has already happened,
  /// so this can never be better than a report: it converts "one frame OOMs
  /// the process" into "one frame was wasted work, and here is a log line
  /// naming it".
  ///
  /// The guard that actually stops the frame is `webSocketUpgrade`, which
  /// hands this same number to `dart:io` as `maxPayloadLength`. That check
  /// runs when the frame's length *header* is read, before any payload is
  /// buffered. This one used to be the only one — the note that used to sit
  /// here said no such parameter existed, which was true of
  /// `package:shelf_web_socket` and false of `dart:io` underneath it.
  ///
  /// Both are kept, and they must stay the same number. A frame this logs is
  /// one the upgrade would have refused had it been a byte larger; if these
  /// two ever disagree, one of them is lying about what the ceiling is.
  static const int maxInboundFrameBytes = 4 * 1024;

  /// How many frames one socket may send back to back.
  ///
  /// Sixty absorbs a reconnect's join plus a genuine burst of taps.
  static const int defaultInboundBurst = 60;

  /// How long one spent inbound-frame token takes to come back.
  ///
  /// One per 33ms is ~30 frames a second sustained. The client's real worst
  /// case is about *fifteen*: position is throttled to exactly 10Hz, emotes
  /// are already bucketed at 3 burst / 800ms, and a board toggle is a rare
  /// tap. Thirty is twice that — deliberate headroom, because a limit that
  /// fires on a real attendee at 09:30 is worse than no limit at all, being
  /// indistinguishable from a broken server with nobody there to explain it.
  ///
  /// Against a flood it is still a reduction of two orders of magnitude, and
  /// the drop happens before the decode, so the frames it refuses are nearly
  /// free. Do not tighten these two numbers.
  static const Duration defaultInboundRefill = Duration(milliseconds: 33);

  /// How often the metrics line is logged.
  static const Duration defaultReportInterval = Duration(seconds: 5);

  /// How long a socket may sit without joining before it is closed.
  ///
  /// **The hole the socket cap on its own cannot close.** `ConnectionGate`
  /// counts sockets rather than players precisely because a flood is sockets
  /// that never join — but counting them only decides who gets refused *next*.
  /// Nothing gave a slot back, so a few hundred sockets that connect, answer
  /// the ping and stay silent hold every slot on the server for as long as
  /// their owner leaves them open, and the refusal the gate hands the real
  /// attendees behind them is permanent. The cap limits the blast radius; this
  /// is what recovers from it.
  ///
  /// Fifteen seconds, which is the width of the gap between the two things
  /// this has to tell apart. A real client sends its `join` in the same
  /// millisecond the socket opens — it has the name and the character in hand
  /// before it dials — so even a phone on bad conference wifi is inside a
  /// second or two, and anything still silent at fifteen is not a slow client,
  /// it is a client that is never going to speak.
  ///
  /// It is deliberately not shorter. The failure mode of too tight a deadline
  /// is disconnecting somebody who did nothing wrong, at an event where the
  /// wifi is the least reliable thing in the building.
  static const Duration defaultJoinDeadline = Duration(seconds: 15);

  /// The most neighbours one snapshot may carry.
  ///
  /// The grid alone is not enough, and the crowded load test is what proves
  /// it. A 3×3 block of 320-unit cells is 960 units across; the atrium is 400
  /// across. So when everybody piles into the atrium — which is what a real
  /// event does at 09:30 — every single person is inside every other person's
  /// interest block and the culling buys exactly nothing. Measured at 120
  /// bots clustered at spawn: 115 players per snapshot, 56KiB/s per client,
  /// on conference wifi.
  ///
  /// Shrinking the cells does not fix it: the interest area has to stay wider
  /// than the screen (a laptop sees ~875 world units across) or players pop
  /// into existence at the edge of the view. So the cap is a second, harder
  /// limit on top of the grid — the nearest N, and everybody else is simply
  /// not sent.
  ///
  /// Forty, because in a crowd that dense the beans overlap anyway: a player
  /// cannot tell 40 beans from 115 without walking through them, and the
  /// nametags have already capped themselves at ten for the same reason.
  static const int defaultNeighbourCap = 40;

  /// How often the world-wide counters are pushed to every client.
  ///
  /// A hundredth of the snapshot rate. The online count is the one number
  /// interest management deliberately hides from a player, so it has to be
  /// sent explicitly — but it changes slowly and nobody is watching it tick,
  /// so once a second is generous.
  static const Duration defaultStatsInterval = Duration(seconds: 1);

  /// Which map this relay is the relay *for*.
  ///
  /// A relay is still a relay — this changes nothing about what it does. It
  /// is here so the log line, the metrics and the admin roster can say which
  /// of the two worlds a number or a player belongs to.
  final MapId map;

  /// Called with a session id the moment it takes a seat here.
  ///
  /// The hook the hub hangs "evict this session from every other map" on.
  /// A hook rather than the relay knowing about its siblings: the relay is
  /// deliberately ignorant of there being more than one world, and a
  /// `MapRelays` reference in here would be the first crack in that.
  final void Function(String sessionId)? onSeated;

  /// Who is in the world, and where.
  final PlayerRegistry registry;

  /// What the server knows about its own load.
  final ServerMetrics metrics;

  /// The gap between snapshots.
  final Duration tickInterval;

  /// The gap between logged metrics lines.
  final Duration reportInterval;

  /// The gap between world-stats broadcasts.
  final Duration statsInterval;

  /// The most neighbours one snapshot may carry.
  final int neighbourCap;

  /// How long a socket has to send its `join` before it is closed.
  final Duration joinDeadline;

  /// How many board toggles a player may fire back to back.
  static const int defaultBoardBurst = 2;

  /// How long one spent board token takes to come back.
  static const Duration defaultBoardRefill = Duration(seconds: 2);

  /// How often each player is allowed to emote.
  final EmoteLimiter emotes;

  /// How often each player is allowed to pick up or put down a board.
  ///
  /// A second [EmoteLimiter] rather than a new class: the mechanism is
  /// identical and only the numbers differ, and a `BoardLimiter` that was a
  /// copy of this one would be a second place to fix the next bug in it.
  final EmoteLimiter boards;

  /// Where every privileged action is recorded.
  final AuditLog audit;

  /// Where each window of metrics is appended for charting afterwards.
  final MetricsRecorder recorder;

  final LogSink _log;

  /// Where every line a *client* can trigger goes.
  ///
  /// Separate from [_log] on purpose. [_log] is the server talking about
  /// itself and its rate is the server's own; this is the server talking
  /// about a stranger, and a stranger sets that rate. See [SecurityLog].
  final SecurityLog _security;

  /// Live sessions by player id. Only joined players are in here.
  final Map<String, RelaySession> _sessions = {};

  Timer? _tickTimer;
  Timer? _reportTimer;
  Timer? _statsTimer;

  /// The map this relay serves, as a value.
  MapSpec get spec => registry.spec;

  /// How many players are currently connected and joined.
  int get playerCount => registry.count;

  /// Every moderation decision taken against this world.
  ModerationState get moderation => registry.moderation;

  /// Whether the tick loop is running.
  bool get isRunning => _tickTimer != null;

  /// Starts the snapshot tick and the metrics report.
  ///
  /// Separate from the constructor so tests can drive [tick] by hand and get
  /// exact, timing-free assertions about what each client was sent.
  void start() {
    if (_tickTimer != null) return;
    _tickTimer = Timer.periodic(tickInterval, (_) => tick());
    _reportTimer = Timer.periodic(reportInterval, (_) {
      _log(metrics.summary);
      // Recorded before the reset, because the row describes the window that
      // just closed and the reset is what closes it.
      recorder.record(metrics);
      metrics.resetWindow();
    });
    _statsTimer = Timer.periodic(statsInterval, (_) => broadcastStats());
    _log(
      'tick loop started at '
      '${(1000 / tickInterval.inMilliseconds).toStringAsFixed(1)}Hz',
    );
  }

  /// Stops the tick loop. Sockets stay open.
  void stop() {
    _tickTimer?.cancel();
    _reportTimer?.cancel();
    _statsTimer?.cancel();
    _tickTimer = null;
    _reportTimer = null;
    _statsTimer = null;
  }

  /// Starts a session for a freshly opened socket.
  ///
  /// A socket exists before its player does: the player is created when the
  /// `join` message arrives.
  RelaySession open(PlayerConnection connection) {
    _log('socket opened on ${map.id} (${registry.count} players)');
    return RelaySession(this, connection);
  }

  /// Runs one snapshot pass over every joined client.
  ///
  /// This is the hot loop of the whole server: it runs 15 times a second and
  /// its cost is `players × neighbours`, not `players²`. Public so tests can
  /// step it deterministically.
  void tick() {
    final stopwatch = Stopwatch()..start();

    var snapshots = 0;
    var playersInSnapshots = 0;
    // A copy: a send that fails can close a socket, and mutating `_sessions`
    // while iterating it would throw.
    for (final session in _sessions.values.toList(growable: false)) {
      final sent = session.sendSnapshot();
      if (sent < 0) continue;
      snapshots++;
      playersInSnapshots += sent;
    }

    stopwatch.stop();
    metrics.recordTick(
      duration: stopwatch.elapsed,
      players: registry.count,
      snapshots: snapshots,
      playersInSnapshots: playersInSnapshots,
      busiestCell: registry.grid.busiestCellCount,
    );
  }

  /// Tells every joined client how many people are in the world.
  ///
  /// The only message in the protocol that is *not* culled, and the only one
  /// whose cost is `players`, not `players × neighbours`. At 300 attendees
  /// that is 300 messages of about 40 bytes once a second — 12KB/s for the
  /// whole server — which buys the thing culling otherwise takes away: some
  /// sense of how big the room is. Public so tests can step it.
  void broadcastStats() {
    if (_sessions.isEmpty) return;
    final message = encodeMessage(WorldStatsMessage(online: registry.count));
    for (final session in _sessions.values.toList(growable: false)) {
      _sendRaw(session._connection, message, session.playerId ?? '?');
    }
  }

  /// An extra already-encoded frame to send to every arrival, if there is one.
  ///
  /// Deliberately a *frame* and not a message: the relay does not know what
  /// is in it, cannot be given a reason to look, and therefore cannot grow an
  /// opinion about it. Today it carries the event's config, which is the
  /// server's business and not this world's.
  ///
  /// A function rather than a string, because the thing it describes changes
  /// while the server is running and a copy taken at construction would be
  /// the config as it was when the process started.
  final String Function()? joinFrame;

  /// When the event reopens, asked fresh on every join, or `null` when it is
  /// open.
  ///
  /// A callback for the same reason [joinFrame] is one: the answer changes
  /// while the server runs, and a value read at construction would be the
  /// answer as it was when the process booted. It is deliberately *not* a
  /// `ConfigStore` — the relay is handed the one fact it has to act on and
  /// cannot grow an opinion about the document that fact came from.
  final DateTime? Function()? maintenanceUntil;

  /// Whether every seat this server hands out is taken, asked at every join.
  ///
  /// A callback for the same reason [maintenanceUntil] is one, and it takes
  /// the same shape deliberately: the relay is handed the one fact it has to
  /// act on and cannot grow an opinion about where the fact came from. It
  /// does not hold a `ConnectionGate`, does not know the cap, and cannot
  /// count anything server-wide — the count is across *every* map and this
  /// class only knows its own.
  ///
  /// `null` means "never full", which is what a relay built in a test gets.
  final bool Function()? isWorldFull;

  /// Builds the inbound rate bucket for one socket, or `null` for the
  /// default.
  ///
  /// A **factory**, not a bucket: every socket needs its own, because the
  /// limit is per socket. Injectable only so a test can hand its sessions a
  /// bucket over a clock it drives — the alternative is a rate-limit test
  /// that sleeps, which is a rate-limit test that is flaky on a loaded CI
  /// box.
  ///
  /// Keyed by nothing at all, deliberately. A socket that never sent a `join`
  /// has no player id to key on, and those are exactly the sockets a flood is
  /// made of — which is why [EmoteLimiter]'s per-id map is the wrong shape
  /// here and [TokenBucket] was pulled out of it.
  final TokenBucket Function()? newInboundBucket;

  /// Called once when a socket on this relay is torn down, whatever killed
  /// it.
  ///
  /// The gate's `release()` reaches the relay through this rather than the
  /// relay reaching for the gate. There is exactly one call site —
  /// [RelaySession.close], which is the single funnel every teardown path
  /// already lands in — because a second decrement site is how the counter
  /// leaks on whichever path somebody forgets.
  final void Function()? onSocketClosed;

  /// Sends [message] to every player in this world.
  ///
  /// The uncalled broadcast, used for the handful of facts that are about the
  /// event rather than about where anybody is standing. Everything positional
  /// goes through the tick and the interest grid instead; this is for things
  /// a human changed, which happen at human rate.
  void broadcast(ProtocolMessage message) {
    if (_sessions.isEmpty) return;
    final encoded = encodeMessage(message);
    for (final session in _sessions.values.toList(growable: false)) {
      _sendRaw(session._connection, encoded, session.playerId ?? '?');
    }
  }

  /// Removes [sessionId] from this world entirely, if it is in it.
  ///
  /// The switch-maps primitive. Without it, walking from the conference to
  /// the beach leaves a bean standing in the atrium for the whole
  /// `sessionLinger` window: the client's old socket may not have finished
  /// dying, and even once it has, the held seat would resume it.
  ///
  /// Goes through exactly the teardown a tab close goes through, for the same
  /// reason [kick] does — a second removal path is how a ghost gets left in
  /// the interest grid. The held seat is dropped too, because a seat kept
  /// warm on a map the player has *left on purpose* is not a kindness.
  ///
  /// Returns whether anybody was actually here.
  bool evictSession(String sessionId) {
    final playerId = registry.seatOfSession(sessionId);
    if (playerId == null) {
      // No live seat, but there may still be a held one from a socket that
      // died a moment ago. Dropping it is the point.
      registry.forgetSession(sessionId);
      return false;
    }

    final session = _sessions[playerId];
    if (session != null) {
      session.terminate();
    } else {
      // Seated with no live socket: the join arrived and the socket died
      // between then and now. Still has to leave the world.
      if (registry.remove(playerId) != null) _announceDeparture(playerId);
    }
    registry.forgetSession(sessionId);
    _log('$playerId left ${map.id} for another map');
    return true;
  }

  /// Closes every socket in this world, as a maintenance window does.
  ///
  /// Goes through [RelaySession.terminate], which is the same teardown a tab
  /// close and a kick both use — one removal path, so nobody is left standing
  /// in the interest grid with no socket behind them.
  ///
  /// Deliberately **not** a kick of everybody. No cooldown is recorded and no
  /// name is blocked: nobody here did anything wrong, and a room full of
  /// thirty-second cooldowns would make the reopening worse than the closure.
  /// The seats are left held by the linger window, so anybody who was
  /// standing somewhere is still standing there when they come back.
  ///
  /// Returns how many sockets were closed.
  int terminateAll() {
    final sessions = _sessions.values.toList(growable: false);
    for (final session in sessions) {
      session.terminate();
    }
    return sessions.length;
  }

  // ── Moderation ─────────────────────────────────────────────────────────
  //
  // Three commands, and every one of them returns the player it acted on or
  // `null`. The caller — the admin hub — turns that into a typed result or a
  // typed error, so the authorization check and the "did it work" check stay
  // separate things. None of these methods checks a token: this class has no
  // idea what an admin is, which is deliberate. Authorization lives at the
  // one door that admin messages come through.

  /// Everybody in the world, as the admin screen needs to see them.
  ///
  /// Uncalled by interest, unlike every other read in this class. A moderator
  /// has to be able to act on somebody standing on the far side of the map —
  /// that is the whole situation moderation exists for.
  List<AdminPlayerSummary> adminPlayerList() {
    final summaries = <AdminPlayerSummary>[];
    for (final player in registry.players) {
      final sessionId = registry.sessionOf(player.id);
      // The name they *chose*, not the one the world sees. A list of
      // identical Guests is a list nobody can moderate.
      final chosenName = sessionId == null
          ? null
          : moderation.chosenNameOf(sessionId);
      summaries.add(
        AdminPlayerSummary(
          id: player.id,
          name: chosenName ?? player.name,
          isNameMuted: chosenName != null,
          x: player.x.roundToDouble(),
          y: player.y.roundToDouble(),
          map: map,
        ),
      );
    }
    return summaries;
  }

  /// Disconnects [playerId], returning what happened, or `null` if nobody.
  ///
  /// Goes through exactly the same teardown as a tab closing: registry entry
  /// gone, grid entry gone, departure announced to everybody who could see
  /// them. That sameness is the point — a second removal path is how a ghost
  /// gets left standing in the interest grid, visible to neighbours and
  /// unreachable by anything.
  ///
  /// The cooldown is recorded *before* the socket dies, and it is what makes
  /// a kick a kick. A client cannot tell a moderator's close from a tunnel
  /// dropping, so it does the only sensible thing and reconnects — within
  /// half a second, under the same session id, into a seat the linger window
  /// is still holding. Without the cooldown the whole action is a bean
  /// blinking on the neighbours' screens.
  ModerationOutcome? kick(String playerId) {
    final player = registry[playerId];
    final session = _sessions[playerId];
    if (player == null || session == null) return null;

    final sessionId = registry.sessionOf(playerId);
    if (sessionId != null) {
      moderation
        ..recordKick(sessionId)
        // The name they were kicked *under*, which is the chosen one — a
        // player who was muted first is walking around as "Guest", and
        // blocking that would take the placeholder off them and leave the
        // name the moderator actually objected to free.
        ..blockName(
          sessionId,
          moderation.chosenNameOf(sessionId) ?? player.name,
        );
    }
    session.terminate();
    return _record(AdminAction.kick, playerId, player.name);
  }

  /// Bans the session behind [playerId] and disconnects them.
  ///
  /// Banned *then* kicked, in that order. The other way round leaves a window
  /// — however short — in which the client's automatic reconnect can land on
  /// a server that has not been told yet, and the person you just removed is
  /// back before you have looked up from the phone.
  ModerationOutcome? ban(String playerId) {
    final player = registry[playerId];
    final sessionId = registry.sessionOf(playerId);
    if (player == null || sessionId == null) return null;

    // The name they were banned *under*, kept in memory so the admin's ban
    // list is a list of people rather than a list of hashes. It never reaches
    // the ban file; see `ModerationState`.
    moderation.ban(sessionId, name: player.name);
    _sessions[playerId]?.terminate();
    // The linger window would otherwise hold their seat, name and position
    // warm for ninety seconds, for somebody who is not coming back.
    registry.forgetSession(sessionId);
    return _record(AdminAction.ban, playerId, player.name);
  }

  /// Takes [playerId]'s name away, or gives it back, without disconnecting.
  ///
  /// The preferred tool: a bad name is the likely incident in a world with no
  /// chat, and this fixes exactly that while leaving the person in the room.
  ///
  /// Propagation is the interesting part, and it is done twice on purpose.
  ///
  /// A [PlayerRenamedMessage] goes out **immediately**, to everybody who can
  /// currently see them and to the muted player themselves. That second half
  /// is the one a re-appearance can never cover — your own bean is never in
  /// your own snapshot — and without it a muted person goes on reading their
  /// own name over their own head and cannot tell a mute from a bug.
  ///
  /// [_forgetEverywhere] still runs behind it, so the next tick re-sends the
  /// full metadata through the appearance path. That is the belt to the
  /// message's braces: the immediate message reaches the neighbours the
  /// interest cap is currently holding, and the re-appearance catches anybody
  /// the cap drops and re-admits in the same breath.
  ModerationOutcome? setNameMuted(String playerId, {required bool muted}) {
    final player = registry[playerId];
    final sessionId = registry.sessionOf(playerId);
    if (player == null || sessionId == null) return null;

    final action = muted ? AdminAction.muteName : AdminAction.unmuteName;
    // Whichever way it goes, the *chosen* name is what gets reported and
    // audited. "Muted Guest" tells a later reader — and the moderator who
    // tapped the row a second ago — nothing at all about what happened.
    final String chosenName;
    final String newName;
    if (muted) {
      // Already muted: report it as done rather than muting a second time,
      // which would record the placeholder as the name they chose.
      if (moderation.isNameMuted(sessionId)) {
        return (
          targetId: playerId,
          targetName: moderation.chosenNameOf(sessionId) ?? player.name,
        );
      }
      moderation.muteName(sessionId, player.name);
      chosenName = player.name;
      newName = mutedDisplayName;
    } else {
      final chosen = moderation.unmuteName(sessionId);
      // Not muted in the first place: nothing to undo, nothing to announce.
      if (chosen == null) {
        return (targetId: playerId, targetName: player.name);
      }
      chosenName = chosen;
      newName = chosen;
    }

    registry.rename(playerId, newName);
    final renamed = PlayerRenamedMessage(id: playerId, name: newName);
    _relayToNeighbours(playerId, renamed);
    // The target is skipped by `_relayToNeighbours` — it is written for
    // emotes, where the sender already drew their own — so they are told
    // here, explicitly. They are the whole point of this message.
    final session = _sessions[playerId];
    if (session != null) {
      _sendRaw(session._connection, encodeMessage(renamed), playerId);
    }
    _forgetEverywhere(playerId);
    return _record(action, playerId, chosenName);
  }

  /// Audits [action] against [targetId] and returns it for the caller to
  /// report back to the admin.
  ///
  /// One helper so the audit line and the moderator's confirmation can never
  /// disagree about what just happened — they are built from the same two
  /// values, in the same place.
  ModerationOutcome _record(
    AdminAction action,
    String targetId,
    String targetName,
  ) {
    audit.record(
      action: action,
      targetId: targetId,
      targetName: targetName,
    );
    return (targetId: targetId, targetName: targetName);
  }

  /// Relays [message] to everybody who can currently see [from], and to
  /// nobody else.
  ///
  /// Same interest rule as a snapshot, and for the same reason: a reaction
  /// thrown in the lounge is not an event in the conference hall. It is sent
  /// straight away rather than queued for the next tick — an emote is a
  /// *moment*, and a moment that arrives 66ms late in a batch reads as lag,
  /// not as a reaction.
  ///
  /// The sender is skipped. Their own client drew the reaction the instant
  /// they tapped, because the client owns its own state — waiting for the
  /// server to hand it back would put a round trip between a tap and a
  /// response for no gain at all.
  void _relayToNeighbours(String from, ProtocolMessage message) {
    final origin = registry[from];
    if (origin == null) return;
    final encoded = encodeMessage(message);
    for (final neighbour in registry.near(origin.x, origin.y, exceptId: from)) {
      final session = _sessions[neighbour.id];
      if (session == null) continue;
      _sendRaw(session._connection, encoded, neighbour.id);
    }
  }

  /// Tells everyone who can currently see [id] that they are gone for good.
  ///
  /// Sent the moment the socket dies rather than waiting for the next tick to
  /// notice, and only to the handful of clients with that player in view —
  /// which is the same set that was being sent their position.
  ///
  /// It is a different message from "walked out of your interest range" on
  /// purpose: both remove a bean, but only this one means the player is not
  /// coming back by walking towards you.
  void _announceDeparture(String id) {
    final message = encodeMessage(PlayerLeftMessage(id: id));
    for (final session in _sessions.values) {
      if (!session._forget(id)) continue;
      _sendRaw(session._connection, message, session.playerId ?? '?');
    }
  }

  /// Makes every client forget [id], so the next tick re-sends their details.
  ///
  /// Metadata travels once, when a player appears. That is most of what
  /// interest management saves, and the price is this: when somebody's name
  /// or colour genuinely changes — they reconnected after editing it — there
  /// is no "player updated" message to send, because sending one would mean
  /// keeping a whole second code path alive for an event that happens once a
  /// session. Forcing a re-appear instead reuses the path that already works.
  void _forgetEverywhere(String id) {
    for (final session in _sessions.values) {
      session._forget(id);
    }
  }

  void _sendRaw(PlayerConnection connection, String data, String id) {
    try {
      connection.send(data);
      metrics.recordOutbound(data.length);
    } on Object catch (error) {
      // A socket can die between "still in the map" and "actually writable".
      // One dead peer must not stop the tick for everybody else.
      _log('send to $id failed: $error');
    }
  }
}

/// One connection's slice of the relay: the state that belongs to a socket.
///
/// Holds the id its client was given, so a `move` never has to trust an id
/// sent by the client, and the set of players this client currently knows
/// about — which is what makes "appeared" and "left range" answerable without
/// the client ever telling us what it has.
class RelaySession {
  /// Creates a session, and starts the clock on its `join`.
  ///
  /// The deadline is armed here rather than at the first frame, because the
  /// socket this exists to close is one that never sends a frame at all.
  RelaySession(this._relay, this._connection) {
    _joinTimer = Timer(_relay.joinDeadline, _joinDeadlinePassed);
  }

  final Relay _relay;
  final PlayerConnection _connection;

  /// Who this client was told about in the last snapshot.
  ///
  /// The server tracks this rather than the client because only the server
  /// can decide what "new to you" means, and a client that lied about what it
  /// already has could make itself invisible to nobody but be told about
  /// everybody.
  final Set<String> _known = {};

  /// Picks who this client is told about, reusing its buffers every tick.
  ///
  /// One per session rather than one per relay: it holds mutable working
  /// state for the duration of a call, and the tick walks sessions one at a
  /// time — but a shared instance would be a trap the first time anything on
  /// this path becomes concurrent.
  late final NearestPlayers _selector = NearestPlayers(
    cap: _relay.neighbourCap,
  );

  /// This socket's share of the server's inbound budget.
  ///
  /// One per session, held directly rather than looked up in a map: see
  /// [Relay.newInboundBucket] for why it cannot be keyed by player id.
  late final TokenBucket _inbound =
      _relay.newInboundBucket?.call() ??
      TokenBucket(
        burst: Relay.defaultInboundBurst,
        refill: Relay.defaultInboundRefill,
      );

  String? _playerId;
  bool _closed = false;
  bool _displaced = false;
  bool _slotReleased = false;

  /// Closes this socket if it is still silent when [Relay.joinDeadline] is up.
  ///
  /// Cancelled the moment the socket becomes something other than a stranger
  /// — a successful join, a close, a displacement — so a seated player never
  /// carries a live timer for the rest of their session.
  Timer? _joinTimer;

  /// Whether this socket lost its seat to a newer one for the same session.
  ///
  /// A displaced session is dead as a socket but must not take the player
  /// down with it — somebody else is sitting in that seat now.
  bool get isDisplaced => _displaced;

  /// The id assigned to this connection, once it has joined.
  String? get playerId => _playerId;

  /// The players this client currently has in view.
  Set<String> get known => Set.unmodifiable(_known);

  /// Handles one inbound frame.
  ///
  /// [data] is whatever the socket produced: text, binary, or something the
  /// client should not have sent. Nothing here throws — a hostile or buggy
  /// client must not be able to take the world down.
  void handleData(Object? data) {
    if (_closed) return;
    _relay.metrics.recordInbound();
    if (data is! String) {
      // Through the security sink, not the plain log. This guard sits *above*
      // the per-socket budget below — it has to, since a binary frame is not
      // worth spending a token on — so nothing else caps how often it can
      // fire. Its own line is the only thing that ever needed capping.
      _relay._security.write('dropped a non-text frame (${data.runtimeType})');
      return;
    }

    // Size, then rate, then decode. The order is the whole design: a guard
    // that ran after `jsonDecode` would cost more than it saves, and both of
    // these are integer comparisons — against a length and against a token
    // count — so neither allocates anything.
    if (data.length > Relay.maxInboundFrameBytes) {
      // `length` is UTF-16 code units, not bytes. That undercounts a frame of
      // non-Latin text by up to 3×, so the effective ceiling is somewhere
      // between 4KiB and 12KiB of wire bytes. Deliberate: encoding the string
      // to count its bytes exactly would allocate the very buffer this guard
      // exists to avoid, and erring generous is the right direction for a
      // limit no honest client comes within ten times of.
      // Security sink for the same reason as the frame-type guard above: this
      // runs before the per-socket budget, so its line is otherwise uncapped.
      _relay._security.write(
        'dropped an oversized frame (${data.length} units)',
      );
      return;
    }
    if (!_inbound.allow()) {
      // Silently, matching the reasoning already written into `_handleEmote`:
      // telling a spammer they were throttled hands them a signal to tune
      // against, and an honest client never reaches the limit to begin with.
      return;
    }

    final message = decodeMessage(data);
    switch (message) {
      case JoinMessage():
        _handleJoin(message);
      case MoveMessage():
        _handleMove(message);
      case EmoteMessage():
        _handleEmote(message);
      case BoardMessage():
        _handleBoard(message);
      case UnknownMessage():
        // Forward compatibility: a message this build does not know is
        // dropped, not fatal. A newer client can talk to an older server.
        //
        // The line is doubly guarded, because it is the one that carries a
        // stranger's own text: `UnknownMessage.toString` clips both of its
        // fields (see `maxLoggedFieldLength`) so no single line can be a
        // kilobyte long, and the security sink caps how many of them there
        // can be.
        _relay._security.write('dropped an unreadable message: $message');
      case WelcomeMessage():
      case SnapshotMessage():
      case PlayerLeftMessage():
      case JoinRejectedMessage():
      case PlayerEmotedMessage():
      case PlayerBoardMessage():
      case PlayerRenamedMessage():
      case AdminBanListMessage():
      case AdminUnbanMessage():
      case WorldStatsMessage():
      case AdminAuthResultMessage():
      case AdminPlayerListMessage():
      case AdminActionResultMessage():
      case AdminErrorMessage():
      case ConfigMessage():
        // Server-to-client messages. A client sending one is confused or
        // malicious; either way it is not an instruction.
        _relay._security.write(
          'dropped a server-only message from a client: $message',
        );
      case AdminAuthMessage():
      case AdminKickMessage():
      case AdminBanMessage():
      case AdminMuteNameMessage():
      case AdminSetConfigMessage():
      case AdminSetMaintenanceMessage():
        // A privileged message on a *player* socket. This path can never
        // moderate anything — not "is not authorised here", but "has no code
        // that could act on it at all". Admin messages are only handled by
        // the admin hub, on its own endpoint, behind its own token check.
        //
        // Logged rather than dropped silently: somebody probing the player
        // socket for an admin surface is worth seeing in the log during an
        // event.
        _relay._security.write(
          'dropped an admin message on a player socket: $message',
        );
    }
  }

  /// Builds and sends this client's snapshot, returning how many other
  /// players it carried, or -1 if nothing was worth sending.
  ///
  /// Nothing to say means nothing sent: somebody standing alone in a corner
  /// costs zero bandwidth rather than 15 empty messages a second. That also
  /// keeps the "average players per snapshot" metric honest — a world full of
  /// hermits would otherwise look like successful culling.
  int sendSnapshot() {
    final id = _playerId;
    if (_closed || id == null) return -1;
    final me = _relay.registry[id];
    if (me == null) return -1;

    final neighbours = _nearest(
      _relay.registry.near(me.x, me.y, exceptId: id),
      me,
    );

    final positions = <PlayerPosition>[];
    final appeared = <PlayerState>[];
    final stillHere = <String>{};
    for (final player in neighbours) {
      stillHere.add(player.id);
      positions.add(
        PlayerPosition(
          id: player.id,
          // Whole world units. A bean is 26 units wide and the client
          // interpolates between samples anyway, so sub-unit precision is
          // invisible — but it doubles the size of every snapshot. Measured
          // at 200 players: 78KiB/s per client before, 41KiB/s after.
          x: player.x.roundToDouble(),
          y: player.y.roundToDouble(),
        ),
      );
      // Full metadata exactly once, when they come into view. Re-sending a
      // name and a colour 15 times a second per neighbour is most of what a
      // naive snapshot wastes.
      if (!_known.contains(player.id)) appeared.add(player);
    }

    final outOfRange = _known.difference(stillHere).toList(growable: false);
    if (positions.isEmpty && outOfRange.isEmpty) return -1;

    _known
      ..clear()
      ..addAll(stillHere);
    _send(
      SnapshotMessage(
        appeared: appeared,
        positions: positions,
        outOfRange: outOfRange,
      ),
    );
    return positions.length;
  }

  /// Handles the socket closing, cleanly or abruptly.
  ///
  /// Called for a tab close, a lost network, and an error alike — the
  /// registry must not keep ghosts, so every one of those paths lands here.
  void close() {
    if (_closed) return;
    _closed = true;
    _known.clear();

    _cancelJoinDeadline();
    _releaseSlot();

    final id = _playerId;
    if (id == null) {
      _relay._log(
        'socket closed before joining '
        '(${_relay.registry.count} players)',
      );
      return;
    }

    // The seat may already belong to a newer socket for the same session:
    // that is the re-seat race, seen from the losing side. Tearing the player
    // down here would kick the client that just successfully reconnected —
    // the exact bug this guard exists for.
    if (!identical(_relay._sessions[id], this)) {
      _relay._log('stale socket for $id closed; its seat is still occupied');
      return;
    }

    _relay._sessions.remove(id);
    _relay.emotes.forget(id);
    // Both buckets, or the second one is the slow leak the first one has a
    // comment about.
    _relay.boards.forget(id);
    final player = _relay.registry.remove(id);
    if (player != null) {
      _relay._announceDeparture(id);
    }
    _relay._log(
      'left: $id (${player?.name ?? 'unknown'}) — '
      '${_relay.registry.count} players',
    );
  }

  /// Removes this player and closes their socket, as a moderator would.
  ///
  /// [close] first, then the socket. That order matters: [close] does the
  /// whole normal teardown — registry, grid, departure announcement — and
  /// marks the session closed, so when the transport notices the socket go
  /// and calls [close] again, it returns immediately instead of doing any of
  /// it twice. One removal path, no ghost, exactly like a tab closing.
  void terminate() {
    close();
    try {
      _connection.close();
    } on Object catch (error) {
      _relay._log('closing a kicked socket failed: $error');
    }
  }

  /// Gives up this socket's seat to a newer one and closes it.
  ///
  /// Deliberately does *not* remove the player: the caller has already handed
  /// the seat to the incoming session. The close it triggers comes back
  /// through [close], which returns immediately because this already marked
  /// the session closed.
  /// Hands this socket's admission slot back to the gate, exactly once.
  ///
  /// One implementation, and its own flag rather than leaning on [_closed],
  /// because there are two ways a socket stops existing and only one of them
  /// runs [close]'s body. [_displace] sets `_closed` itself and deliberately
  /// skips the rest of the teardown — somebody else is sitting in that seat —
  /// so the later `close` the transport triggers returns immediately. A
  /// release that lived only in [close] would therefore leak one slot per
  /// reconnect race, which is the slowest possible leak and the one a load
  /// test would never catch.
  void _releaseSlot() {
    if (_slotReleased) return;
    _slotReleased = true;
    _relay.onSocketClosed?.call();
  }

  /// Stops the join deadline, whether or not it was ever going to fire.
  ///
  /// Idempotent, and called from every path that ends a socket's life as a
  /// stranger. A timer left running on a seated player would fire into a
  /// session that has long since joined — harmless, because
  /// [_joinDeadlinePassed] re-checks, but it would also hold this object
  /// alive in the event loop for fifteen seconds after the socket died, which
  /// at 800 sockets is a leak with a heartbeat.
  void _cancelJoinDeadline() {
    _joinTimer?.cancel();
    _joinTimer = null;
  }

  /// Closes a socket that connected and then never said who it was.
  ///
  /// Re-checks rather than trusting the timer: between the tick that fired
  /// this and the microtask that runs it, a `join` may have arrived, and
  /// disconnecting somebody one millisecond after they walked in would be a
  /// far worse bug than the one this closes.
  void _joinDeadlinePassed() {
    _joinTimer = null;
    if (_closed || _playerId != null) return;
    _relay._log(
      'closing a socket that never joined after '
      '${_relay.joinDeadline.inSeconds}s',
    );
    terminate();
  }

  void _displace() {
    if (_closed) return;
    _closed = true;
    _displaced = true;
    _known.clear();
    _cancelJoinDeadline();
    _releaseSlot();
    try {
      _connection.close();
    } on Object catch (error) {
      _relay._log('closing a displaced socket failed: $error');
    }
  }

  void _handleJoin(JoinMessage join) {
    if (_playerId != null) {
      // Joining twice on one socket would orphan the first registry entry
      // behind it, which is exactly how ghosts appear. Note this is a
      // different thing from a *second socket* for the same session, which is
      // the legitimate reconnect handled below.
      // Security sink: a seated client can repeat this as fast as its inbound
      // budget allows, so the line is a stranger's to schedule, not ours.
      _relay._security.write('dropped a second join from $_playerId');
      return;
    }

    // Before everything, including the checks about *this* person. The other
    // refusals below all answer "who are you"; this one answers "is the event
    // open", which is a question about the event and has the same answer for
    // everybody. Asked first so a closed event says one thing to the whole
    // world rather than sorting people into reasons on the way out.
    final until = _relay.maintenanceUntil?.call();
    if (until != null && DateTime.now().toUtc().isBefore(until)) {
      _reject(
        JoinRejection.maintenance,
        'The event is paused for maintenance until '
        '${until.toIso8601String()}.',
      );
      return;
    }

    // Beside the maintenance check, and for the same reason: this is the
    // other refusal that is about the *event* rather than about the person.
    // Everybody gets the same answer, nobody did anything wrong, and there is
    // nothing to retype — so it is asked before any of the checks below,
    // which all answer "who are you".
    //
    // Unlike maintenance it carries no time, because nobody knows when a seat
    // frees. A number here would be the server inventing one.
    if (_relay.isWorldFull?.call() ?? false) {
      _reject(
        JoinRejection.worldFull,
        'The event is full right now. Please try again in a moment.',
      );
      return;
    }

    // Never trust the client, part one: the session id is a map key on the
    // server, so its shape is checked before it is used as one.
    if (!isValidSessionId(join.sessionId)) {
      _reject(
        JoinRejection.invalidSession,
        'That session could not be read. Reload to start a new one.',
      );
      return;
    }

    // Checked before the name, and before a seat is taken: a banned session
    // must not be able to occupy anything, however briefly, and must not be
    // told which of its two problems the server noticed first.
    if (_relay.moderation.isBanned(join.sessionId)) {
      _reject(
        JoinRejection.banned,
        'A moderator has removed you from this event.',
      );
      return;
    }

    // Then the temporary one. Separate from the ban above because the
    // client has to behave differently: this one it can wait out, so the
    // remaining time goes in the message rather than "speak to the team".
    final cooling = _relay.moderation.kickCooldownLeft(join.sessionId);
    if (cooling != null) {
      // Rounded up, so the last fractional second never reads as "0s".
      final seconds = (cooling.inMilliseconds / 1000).ceil();
      _reject(
        JoinRejection.kicked,
        'A moderator removed you from this event. '
        'You can rejoin in ${seconds}s, under a different name.',
      );
      return;
    }

    // The name a kick took away, if this is them coming back wearing it
    // again. Reported as a name problem rather than a moderation one on
    // purpose: `invalidName` is the rejection that means "go back to setup
    // and choose one", which is exactly where this person needs to be.
    if (_relay.moderation.isNameBlocked(join.sessionId, join.name)) {
      _reject(
        JoinRejection.invalidName,
        'A moderator removed that name. Please choose a different one.',
      );
      return;
    }

    // Never trust the client, part two: the client already ran exactly this
    // function to show a message while the player typed. Running it again
    // here is not redundancy — the client's pass is a courtesy to the person
    // typing, and this pass is the rule. A client that skipped it, or one
    // somebody else wrote, gets stopped here.
    final verdict = validateName(join.name);
    if (!verdict.isValid) {
      _reject(JoinRejection.invalidName, verdict.message);
      return;
    }

    // Before the seat is taken, not after: if this session is standing on
    // another map, it has to leave that one first, or a switch shows the
    // player in two places at once for a tick.
    _relay.onSeated?.call(join.sessionId);

    final seat = _relay.registry.seat(join);
    final id = seat.player.id;

    // The re-seat race: the client reconnected before the server noticed the
    // old socket had died, so two sockets briefly claim one seat. The new one
    // wins and the old one is closed — rejecting the join instead would
    // strand a client that did nothing wrong behind a socket that is already
    // dead, until a ping timeout it cannot see.
    final incumbent = _relay._sessions[id];
    if (incumbent != null && !identical(incumbent, this)) {
      incumbent._displace();
    }

    _playerId = id;
    _relay._sessions[id] = this;
    // This socket is no longer a stranger, so the deadline that exists to
    // close strangers has nothing left to do.
    _cancelJoinDeadline();

    // A returning client knows nothing about who is nearby, so everything
    // must be re-announced to it from scratch.
    _known.clear();

    // ...and if they came back looking different, everybody else has to be
    // told too, since metadata is only ever sent on appearance.
    if (seat.appearanceChanged) _relay._forgetEverywhere(id);

    // The welcome is just an id. Who is nearby arrives one tick later in a
    // snapshot, through the same path as every later change — one code path
    // for "who can I see", not two that can disagree.
    _send(WelcomeMessage(yourId: id));
    // A muted player, coming back. The registry seated them under the
    // placeholder — `effectiveName` is the one funnel every name goes
    // through — but their own client still believes the name it typed, and
    // nothing else on this socket would ever contradict it. Told once, here,
    // rather than folded into the welcome: the welcome is an id and stays an
    // id, and a rename is a rename whether it arrives now or an hour in.
    if (seat.player.name != join.name) {
      _send(PlayerRenamedMessage(id: id, name: seat.player.name));
    }
    // Whatever else the server wants every arrival to have, as an already
    // encoded frame. Today that is the event's config; the relay is
    // deliberately not told what it is, only that there is one — which is
    // how it stays a relay.
    final greeting = _relay.joinFrame?.call();
    if (greeting != null) {
      _relay._sendRaw(_connection, greeting, _playerId ?? '?');
    }
    // Straight away, not at the next stats tick: a counter that reads zero
    // for the first second of a session is the first thing a new arrival
    // sees, and it says the event is empty.
    _send(WorldStatsMessage(online: _relay.registry.count));
    _relay._log(
      '${seat.kind.name} on ${_relay.map.id}: $id (${seat.player.name}) — '
      '${_relay.registry.count} players',
    );
  }

  /// Tells the client why it is not coming in, then closes the socket.
  ///
  /// Sent and closed rather than closed silently: a lobby that just sits
  /// there, with no reason on screen, is the worst version of this failure.
  void _reject(JoinRejection reason, String detail) {
    _relay._log('rejected a join: ${reason.wireName} ($detail)');
    _send(JoinRejectedMessage(reason: reason, detail: detail));
    _closed = true;
    // The two pieces of teardown a rejected socket still needs, done here
    // rather than left to [close].
    //
    // **This was a slot leak, and the worst kind: permanent.** Setting
    // `_closed` above is what lets the rejection message go out before the
    // socket dies, but it also means the `close` the transport calls a
    // moment later returns at its first line — so the gate slot this socket
    // took at the upgrade was never handed back. Every refused join burned
    // one, for the life of the process, and refused joins are the cheapest
    // thing in the protocol to send: connect, send a malformed `sessionId`,
    // repeat 800 times, and the server refuses every real attendee for the
    // rest of the day with nothing open to show for it.
    _cancelJoinDeadline();
    _releaseSlot();
    try {
      _connection.close();
    } on Object catch (error) {
      _relay._log('closing a rejected socket failed: $error');
    }
  }

  void _handleMove(MoveMessage move) {
    final id = _playerId;
    if (id == null) {
      // Silently, and the same in `_handleEmote` and `_handleBoard` below.
      // A move before a join is a well-formed message on an unseated socket,
      // which is one line per frame for as long as somebody cares to send
      // them and tells an operator nothing they cannot see from the socket
      // count. The join deadline is what actually deals with these sockets.
      return;
    }

    // Recorded, not relayed. The next tick is what tells anybody about it.
    _relay.registry.move(id, move.x, move.y);
  }

  /// Handles one reaction: rate-limit it, then pass it to the neighbours.
  ///
  /// The relayed message carries the id *this server* assigned, never one the
  /// client sent — the inbound emote has no id field at all, so there is no
  /// way to put a reaction over somebody else's head.
  void _handleEmote(EmoteMessage emote) {
    final id = _playerId;
    if (id == null) {
      // Silently: see `_handleMove`.
      return;
    }
    if (!_relay.emotes.allow(id)) {
      // Silently. Telling a spammer they were throttled is a signal to tune
      // against, and the honest client already throttles itself.
      return;
    }
    _relay._relayToNeighbours(
      id,
      PlayerEmotedMessage(id: id, emote: emote.emote),
    );
  }

  /// Handles one board toggle: record it, rate-limit it, then relay it.
  ///
  /// Mirrors [_handleEmote] line for line, including the part that matters:
  /// the relayed message carries the id *this server* assigned. The inbound
  /// message has no id field at all, so there is no way to hand somebody else
  /// a board or take theirs away.
  ///
  /// The registry write comes first and is not rate-limited, so a dropped
  /// relay never leaves the server's idea of a player disagreeing with the
  /// client's. What the limiter protects is the fan-out.
  void _handleBoard(BoardMessage board) {
    final id = _playerId;
    if (id == null) {
      // Silently: see `_handleMove`.
      return;
    }
    if (_relay.registry.setBoard(id, hasBoard: board.hasBoard) == null) {
      return;
    }
    if (!_relay.boards.allow(id)) {
      // Silently, as with emotes. The state is recorded either way; only the
      // announcement is dropped, and the next appearance carries it anyway.
      return;
    }
    _relay._relayToNeighbours(
      id,
      PlayerBoardMessage(id: id, hasBoard: board.hasBoard),
    );
  }

  /// Trims [neighbours] to the nearest [Relay.neighbourCap] around [me].
  ///
  /// The selection itself lives in [NearestPlayers], which holds its working
  /// buffers per session so the hottest loop on the server allocates nothing.
  List<PlayerState> _nearest(List<PlayerState> neighbours, PlayerState me) =>
      _selector.select(
        neighbours,
        x: me.x,
        y: me.y,
        isKnown: _known.contains,
      );

  /// Drops [id] from what this client knows, reporting whether it was there.
  bool _forget(String id) => _known.remove(id);

  void _send(ProtocolMessage message) {
    _relay._sendRaw(_connection, encodeMessage(message), _playerId ?? '?');
  }
}
