import 'dart:async';
import 'dart:math';

import 'package:loadtest/src/scenario.dart';
import 'package:loadtest/src/wander.dart';
import 'package:protocol/protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Names bots join with, so a real player watching can tell them apart from
/// each other and from actual humans.
const List<String> botNames = [
  'Bot Aarav',
  'Bot Bhavya',
  'Bot Chirag',
  'Bot Divya',
  'Bot Eshan',
  'Bot Farah',
  'Bot Gaurav',
  'Bot Hina',
  'Bot Ishaan',
  'Bot Jaya',
];

/// Returns the display name for the bot at [index].
///
/// It has to pass the server's own [validateName], because the server rejects
/// a bad name now instead of trimming it — a load test whose bots are all
/// turned away at the door measures nothing. The modulo keeps it inside the
/// 16-character cap for any swarm size this project will ever run.
String botName(int index) =>
    '${botNames[index % botNames.length]} ${index % 1000}';

/// Body colours bots pick from.
const List<int> botColors = [
  0xFF54C5F8,
  0xFF7ED9B6,
  0xFFF2B33D,
  0xFFEF6F6C,
  0xFFB78BE8,
];

/// What one run of the load test measured.
class SwarmStats {
  /// Sockets currently open.
  ///
  /// A gauge, not a running total: under [LoadScenario.churn] bots leave and
  /// rejoin all run, and a counter that only went up would report a swarm
  /// four times the size of the one actually connected.
  int connected = 0;

  /// Sockets that never opened, or died unexpectedly.
  ///
  /// A bot the churn driver closed on purpose is not a failure; it is counted
  /// in [left] instead.
  int failed = 0;

  /// Sockets opened over the whole run, including rejoins.
  int opened = 0;

  /// Bots the churn driver disconnected on purpose.
  int left = 0;

  /// Bots that came back with the same session id, exercising the re-seat
  /// path a phone leaving wifi takes.
  int reseated = 0;

  /// Bots that came back as a brand-new person, exercising the join path.
  int arrived = 0;

  /// Move messages sent to the server.
  int movesSent = 0;

  /// Messages received from the server.
  int received = 0;

  /// Characters received from the server. ASCII JSON, so also bytes.
  int receivedBytes = 0;

  /// Board announcements sent to the server.
  int boardsSent = 0;

  /// Snapshots received from the server.
  int snapshots = 0;

  /// Total players named across every snapshot received.
  int playersInSnapshots = 0;

  /// The mean number of other players a snapshot carried.
  ///
  /// The client's own view of culling: it should sit far below the number of
  /// bots, and should barely move as that number grows.
  double get averagePlayersPerSnapshot =>
      snapshots == 0 ? 0 : playersInSnapshots / snapshots;

  /// A one-line summary for the console.
  String summary(Duration elapsed) {
    final seconds = elapsed.inMilliseconds / 1000;
    final perClient = connected == 0 ? 0.0 : receivedBytes / connected;
    return 'connected=$connected failed=$failed '
        'sent=${_rate(movesSent, seconds)}msg/s '
        'recv=${_rate(received, seconds)}msg/s '
        '${(perClient / seconds / 1024).toStringAsFixed(2)}KiB/s/client '
        'perSnapshot=${averagePlayersPerSnapshot.toStringAsFixed(1)} '
        'churn=$left out/${reseated + arrived} in'
        '${boardsSent == 0 ? '' : ' boards=$boardsSent'}';
  }

  static String _rate(int total, double seconds) =>
      seconds <= 0 ? '0' : (total / seconds).toStringAsFixed(0);
}

/// One simulated attendee: a socket, a join, and a bean that wanders.
class Bot {
  /// Creates a bot that will connect to [url].
  Bot({
    required this.url,
    required this.index,
    required Random random,
    MapSpec spec = MapSpec.conference,
    double? clusterRadius,
    this.surfs = false,
    double? toggleSeconds,
  }) : minimumToggle = toggleSeconds ?? defaultMinimumToggleSeconds,
       maximumToggle = toggleSeconds ?? defaultMaximumToggleSeconds,
       // Jittered from the start, so 200 bots that all unlocked a board at
       // connect time do not then all flip it on the same second. A
       // lockstep spike is a load the real world never produces, and
       // measuring one teaches nothing.
       _nextToggle =
           (toggleSeconds ?? defaultMinimumToggleSeconds) +
           random.nextDouble() *
               ((toggleSeconds ?? defaultMaximumToggleSeconds) -
                   (toggleSeconds ?? defaultMinimumToggleSeconds)),
       wanderer = Wanderer(
         random: random,
         spec: spec,
         clusterRadius: clusterRadius,
       ),
       // Bots generate a session id the same way a real client does, from the
       // shared helper in `protocol/`. A per-bot random one, not one derived
       // from the index: a rerun of the load test must look like a room full
       // of new people, not like 200 old sessions all reconnecting at once.
       sessionId = newSessionId(random),
       _random = random;

  /// Where the relay is.
  final Uri url;

  /// This bot's number in the swarm, used to pick a name.
  final int index;

  /// This bot's device identity, sent on every join it makes.
  ///
  /// Held for the bot's lifetime rather than regenerated per connect, so a
  /// reconnecting bot exercises the server's re-seat path exactly the way a
  /// phone leaving wifi does.
  final String sessionId;

  /// The shortest gap between one bot's board toggles, in seconds.
  static const double defaultMinimumToggleSeconds = 30;

  /// The longest gap between one bot's board toggles, in seconds.
  static const double defaultMaximumToggleSeconds = 90;

  /// The shortest gap this bot leaves between toggles, in seconds.
  final double minimumToggle;

  /// The longest gap this bot leaves between toggles, in seconds.
  final double maximumToggle;

  /// Where this bot is and where it is walking.
  final Wanderer wanderer;

  /// Whether this bot has found a board and flips it periodically.
  ///
  /// The point of the flag is the *steady state*: a bot with a board must
  /// cost the server the same bytes per second as one without, because
  /// `hasBoard` rides in the appeared list and not in the per-tick path. If
  /// a run at `--surfers 50` moves bytes/sec, the flag leaked into the tick.
  final bool surfs;

  /// Whether this bot is currently carrying its board.
  bool hasBoard = false;

  double _nextToggle;
  double _sinceToggle = 0;

  final Random _random;

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;

  /// Whether this bot's socket is open.
  bool get isConnected => _channel != null;

  /// Opens the socket and joins. Returns whether it worked.
  ///
  /// Never throws: at 200 bots a handful of refused connections is data, not
  /// a reason to abandon the run.
  Future<bool> connect(SwarmStats stats) async {
    try {
      final channel = WebSocketChannel.connect(url);
      await channel.ready;
      _channel = channel;
      _subscription = channel.stream.listen(
        (data) => _onFrame(data, stats),
        onError: (Object _) => _drop(stats),
        onDone: () => _drop(stats),
        cancelOnError: false,
      );
      channel.sink.add(
        encodeMessage(
          JoinMessage(
            sessionId: sessionId,
            name: botName(index),
            color: botColors[_random.nextInt(botColors.length)],
            cosmetic:
                PlayerCosmetic.values[_random.nextInt(
                  PlayerCosmetic.values.length,
                )],
          ),
        ),
      );
      if (surfs) {
        // Once, right after the join — the same moment a real client
        // re-announces after its welcome.
        hasBoard = true;
        channel.sink.add(encodeMessage(const BoardMessage(hasBoard: true)));
        stats.boardsSent++;
      }
      stats.connected++;
      stats.opened++;
      return true;
    } on Object {
      stats.failed++;
      return false;
    }
  }

  /// Walks for [dt] seconds and reports the new position.
  void step(double dt, SwarmStats stats) {
    wanderer.update(dt);
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(
        encodeMessage(MoveMessage(x: wanderer.x, y: wanderer.y)),
      );
      stats.movesSent++;
      _stepBoard(dt, channel, stats);
    } on Object {
      _drop(stats);
    }
  }

  /// Flips this bot's board when its jittered timer comes due.
  ///
  /// Driven off the same send timer as the walk rather than a timer of its
  /// own: two hundred extra timers on one isolate is the load tester
  /// measuring its own scheduler.
  void _stepBoard(double dt, WebSocketChannel channel, SwarmStats stats) {
    if (!surfs) return;
    _sinceToggle += dt;
    if (_sinceToggle < _nextToggle) return;
    _sinceToggle = 0;
    _nextToggle =
        minimumToggle + _random.nextDouble() * (maximumToggle - minimumToggle);
    hasBoard = !hasBoard;
    channel.sink.add(encodeMessage(BoardMessage(hasBoard: hasBoard)));
    stats.boardsSent++;
  }

  /// Closes the socket.
  ///
  /// A deliberate close is not a failure, so this clears the connection
  /// before the `onDone` callback can see it and count one.
  Future<void> close(SwarmStats stats) async {
    final channel = _channel;
    _channel = null;
    if (channel != null) stats.connected--;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await channel?.sink.close();
    } on Object {
      // A socket that is already gone does not need closing twice.
    }
  }

  void _onFrame(Object? data, SwarmStats stats) {
    if (data is! String) return;
    stats.received++;
    stats.receivedBytes += data.length;
    final message = decodeMessage(data);
    if (message is SnapshotMessage) {
      stats.snapshots++;
      stats.playersInSnapshots += message.positions.length;
    }
  }

  void _drop(SwarmStats stats) {
    if (_channel == null) return;
    _channel = null;
    stats.connected--;
    stats.failed++;
  }
}

/// A crowd of bots against one server.
///
/// Every bot is driven from a single timer rather than one timer each. Two
/// hundred independent timers on one isolate is the load tester measuring its
/// own scheduler, and the numbers that come back would be about the tester,
/// not the server.
class Swarm {
  /// Creates a swarm of [count] bots pointed at [url].
  ///
  /// [maps] is which world (or worlds) the bots join. More than one splits
  /// the swarm round-robin between them and appends `?map=` to each bot's
  /// URL, which is what a run against a two-map server has to do: a load
  /// test that only ever hits the conference is a load test that never
  /// measures the second relay's tick.
  Swarm({
    required this.url,
    required this.count,
    this.sendInterval = defaultSendInterval,
    this.scenario = LoadScenario.spread,
    this.churnInterval = defaultChurnInterval,
    List<MapId> maps = const [MapId.conference],
    double? clusterRadius,
    double? churnFraction,
    this.surferShare = 0,
    this.surfToggleSeconds,
    Random? random,
  }) : maps = maps.isEmpty ? const [MapId.conference] : maps,
       clusterRadius = clusterRadius ?? scenario.clusterRadius,
       churnFraction = churnFraction ?? scenario.churnFraction,
       _nextIndex = count,
       _random = random ?? Random();

  /// How often each bot reports its position: ~10Hz, like the real client.
  static const Duration defaultSendInterval = Duration(milliseconds: 100);

  /// How often the churn driver wakes up.
  ///
  /// A second, not a tick: churn is a slow process and running it on the send
  /// timer would put socket teardown on the hot path of the measurement.
  static const Duration defaultChurnInterval = Duration(seconds: 1);

  /// Where the relay is.
  final Uri url;

  /// How many bots to run.
  final int count;

  /// The gap between position reports.
  final Duration sendInterval;

  /// The crowd shape this run simulates.
  final LoadScenario scenario;

  /// The gap between churn steps.
  final Duration churnInterval;

  /// Which maps this swarm is spread across.
  final List<MapId> maps;

  /// The share of the swarm that leaves and rejoins each minute.
  final double churnFraction;

  /// Forces every surfer's toggle gap to this many seconds, or `null` for
  /// the jittered 30-90s a real player would produce.
  ///
  /// Only ever set to something silly, and only for one thing: proving the
  /// server's board limiter holds. A run at `--surfers 100` with a sub-second
  /// gap is 200 clients trying to fan out a toggle several times a second,
  /// and the outbound rate has to stay bounded anyway.
  final double? surfToggleSeconds;

  /// The share of the swarm that unlocks a board, from 0 to 1.
  ///
  /// Applied by index rather than at random, for the same reason [mapFor] is:
  /// a run you cannot repeat is not a measurement. At 0.5 every other bot
  /// surfs, in every run, on every machine.
  final double surferShare;

  /// When set, every bot stays within this radius of its map's spawn point.
  ///
  /// The crowded case. Bots spread evenly over the whole world are the
  /// comfortable measurement: every interest cell holds a handful of people
  /// and the culling looks free. Piling them all into the atrium is what the
  /// grid is actually worst at, and it is what a real event does at 09:30.
  final double? clusterRadius;

  final Random _random;

  /// The bots, once [connect] has run.
  final List<Bot> bots = [];

  /// What this run has measured so far.
  final SwarmStats stats = SwarmStats();

  /// How many bots the churn driver still owes, below the next whole one.
  late final ChurnPlan churn = ChurnPlan(
    count: count,
    fractionPerMinute: churnFraction,
  );

  Timer? _timer;
  Timer? _churnTimer;
  int _nextIndex;
  int _recycles = 0;
  bool _recycling = false;

  /// Opens every socket, [ramp] apart.
  ///
  /// Staggered on purpose: 200 sockets in the same millisecond measures the
  /// accept queue, not the running server. A conference fills up over
  /// minutes, and a load test that cannot tell a connect storm from steady
  /// state is not measuring the thing that matters.
  Future<void> connect({
    Duration ramp = const Duration(milliseconds: 20),
    void Function(int connected)? onProgress,
  }) async {
    for (var i = 0; i < count; i++) {
      final bot = _newBot(i);
      bots.add(bot);
      await bot.connect(stats);
      onProgress?.call(i + 1);
      if (ramp > Duration.zero) await Future<void>.delayed(ramp);
    }
  }

  /// Starts everybody walking, and the churn driver if this scenario has one.
  void start() {
    _timer ??= Timer.periodic(sendInterval, (_) {
      final dt = sendInterval.inMilliseconds / 1000;
      for (final bot in bots) {
        bot.step(dt, stats);
      }
    });
    if (churnFraction <= 0) return;
    _churnTimer ??= Timer.periodic(churnInterval, (_) {
      final due = churn.take(churnInterval.inMilliseconds / 1000);
      if (due > 0) unawaited(recycle(due));
    });
  }

  /// Stops the walking and closes every socket.
  Future<void> stop() async {
    _timer?.cancel();
    _churnTimer?.cancel();
    _timer = null;
    _churnTimer = null;
    for (final bot in bots) {
      await bot.close(stats);
    }
  }

  /// Disconnects [howMany] random bots and brings them back.
  ///
  /// Alternates between the two ways a person leaves and returns, because
  /// they take different paths through the server and only one of them is
  /// obvious:
  ///
  /// - **Re-seated.** The same session id reconnects, the way a phone does
  ///   when it drops off wifi and comes back. The server is supposed to hand
  ///   the seat it was holding back to them.
  /// - **Arrived.** A brand-new session id, the way a new attendee does. The
  ///   old seat is supposed to expire on its own.
  ///
  /// A leak in either one shows up as memory that climbs while the player
  /// count sits flat, which is the whole reason this scenario exists.
  ///
  /// Public so a test can step it without waiting for the timer. Re-entrant
  /// calls are dropped rather than queued: the timer must not be able to
  /// stack up socket teardown faster than it completes.
  Future<void> recycle(int howMany) async {
    if (_recycling || bots.isEmpty) return;
    _recycling = true;
    try {
      for (var i = 0; i < howMany; i++) {
        final slot = _random.nextInt(bots.length);
        final leaving = bots[slot];
        await leaving.close(stats);
        stats.left++;
        final reseat = _recycles.isEven;
        _recycles++;
        if (reseat) {
          await leaving.connect(stats);
          stats.reseated++;
        } else {
          final arriving = _newBot(_nextIndex++);
          bots[slot] = arriving;
          await arriving.connect(stats);
          stats.arrived++;
        }
      }
    } finally {
      _recycling = false;
    }
  }

  /// Whether the bot at [index] is one of the surfers.
  ///
  /// Deterministic for a given [surferShare], which is what lets a run at
  /// `--surfers 50` be compared against the same run without the flag.
  bool surfsAt(int index) {
    if (surferShare <= 0) return false;
    if (surferShare >= 1) return true;
    // Spread through the swarm rather than taking the first N, so the
    // surfers are not all in the same corner of a clustered run.
    return (index % 100) < (surferShare * 100).round();
  }

  /// Which map the bot at [index] joins.
  ///
  /// Round-robin by index rather than random, so a run split across two maps
  /// puts a predictable, even crowd on each. A random split of 200 bots lands
  /// anywhere from 85 to 115 on a side, and a load number you cannot repeat
  /// is not a measurement.
  MapId mapFor(int index) => maps[index % maps.length];

  /// The socket URL for the bot at [index], carrying its `?map=`.
  ///
  /// Only appended when a run names more than one map, so a single-map run
  /// against an older server still opens exactly the URL it used to.
  Uri urlFor(int index) {
    if (maps.length == 1 && maps.single == MapId.conference) return url;
    return url.replace(
      queryParameters: {...url.queryParameters, 'map': mapFor(index).id},
    );
  }

  Bot _newBot(int index) => Bot(
    url: urlFor(index),
    index: index,
    random: _random,
    spec: MapSpec.of(mapFor(index)),
    clusterRadius: clusterRadius,
    surfs: surfsAt(index),
    toggleSeconds: surfToggleSeconds,
  );
}
