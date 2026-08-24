import 'dart:io';
import 'dart:math' as math;

/// What the server measures about itself.
///
/// Every number here exists to answer a question the load test asks, and none
/// of them is a guess: how many people are connected, how much work a tick
/// really costs, how much of the world each client is actually being told
/// about, and what that adds up to in messages and bytes.
///
/// The one that matters most is [averagePlayersPerSnapshot]. If interest
/// management works, it stays low and flat while [players] climbs — that is
/// culling, measured rather than assumed.
///
/// Counters are cheap on purpose: integer adds on the tick path, no
/// allocation, no timestamps per message. Instrumentation that shows up in
/// its own measurements is worse than none.
class ServerMetrics {
  /// Creates a metrics collector.
  ///
  /// [now] is injectable so tests can drive the clock instead of sleeping.
  ServerMetrics({
    DateTime Function() now = DateTime.now,
    this.tickBudget = defaultTickBudget,
    this.readResidentBytes = _currentRss,
  }) : _now = now,
       _windowStart = now(),
       _startedAt = now();

  /// The tick budget assumed when none is given: the relay's default 15Hz.
  ///
  /// Not imported from `Relay` because that would make the metrics depend on
  /// the thing they measure; the real one is passed in from the relay.
  static const Duration defaultTickBudget = Duration(milliseconds: 66);

  /// How wide one latency bucket is, in milliseconds.
  ///
  /// One millisecond is finer than any decision made from these numbers, and
  /// a 256-entry array of ints is small enough that the histogram is free.
  static const int bucketMillis = 1;

  /// How many buckets the histogram has, the last one being the overflow.
  ///
  /// A tick that takes more than a quarter of a second is not a latency
  /// measurement, it is an incident — [worstTickMillis] is the number that
  /// describes it, so the histogram does not need the resolution up there.
  static const int bucketCount = 256;

  /// How long one tick is allowed to take before it counts as an overrun.
  ///
  /// The single most important threshold on the server. A tick that runs past
  /// its own interval means the next one starts late, and a run of them means
  /// the snapshot rate everybody is interpolating against is a fiction.
  final Duration tickBudget;

  /// Reads the process's resident set size in bytes.
  ///
  /// Injectable so a test can assert on a memory trend without allocating
  /// one, and so a platform that will not report RSS degrades to zero rather
  /// than to an exception on the metrics route.
  final int Function() readResidentBytes;

  final DateTime Function() _now;

  DateTime _windowStart;
  final DateTime _startedAt;

  int _players = 0;
  int _peakPlayers = 0;
  int _ticks = 0;
  int _tickMicros = 0;
  int _worstTickMicros = 0;
  int _snapshots = 0;
  int _playersInSnapshots = 0;
  int _outboundMessages = 0;
  int _outboundBytes = 0;
  int _inboundMessages = 0;
  int _busiestCell = 0;
  int _tickOverruns = 0;
  final List<int> _tickBuckets = List<int>.filled(bucketCount, 0);

  /// How long the server has been up.
  Duration get uptime => _now().difference(_startedAt);

  /// How long the current measurement window has been open.
  Duration get window => _now().difference(_windowStart);

  /// Players connected and joined, as of the last tick.
  int get players => _players;

  /// The most players seen at once during this window.
  int get peakPlayers => _peakPlayers;

  /// Completed ticks in this window.
  int get ticks => _ticks;

  /// Ticks per second over this window.
  double get ticksPerSecond => _perSecond(_ticks);

  /// Mean time spent inside a tick, in milliseconds.
  double get averageTickMillis => _ticks == 0 ? 0 : _tickMicros / _ticks / 1000;

  /// The slowest tick in this window, in milliseconds.
  ///
  /// The average hides the problem: one tick that overruns the 66ms budget is
  /// a visible hitch for everybody, even if the mean looks fine.
  double get worstTickMillis => _worstTickMicros / 1000;

  /// The 95th-percentile tick, in milliseconds.
  ///
  /// The number to tune against, and the reason the histogram exists. The
  /// mean is too forgiving — it hides a tail that every player feels — and
  /// the max is too brittle, because one GC pause during a thirty-minute run
  /// would condemn a server that was fine. The p95 is what "usually smooth"
  /// actually means.
  ///
  /// Resolved to the top of its bucket, so it is an upper bound and never
  /// flatters the run. Ticks past the histogram's range report
  /// [worstTickMillis] instead.
  double get p95TickMillis {
    if (_ticks == 0) return 0;
    final target = (_ticks * 0.95).ceil();
    var seen = 0;
    for (var bucket = 0; bucket < bucketCount; bucket++) {
      seen += _tickBuckets[bucket];
      if (seen < target) continue;
      if (bucket == bucketCount - 1) return worstTickMillis;
      return ((bucket + 1) * bucketMillis).toDouble();
    }
    return worstTickMillis;
  }

  /// Ticks in this window that ran past [tickBudget].
  ///
  /// Zero is the only good answer. Anything else is the server failing to
  /// keep its own clock, which no amount of client-side smoothing can hide.
  int get tickOverruns => _tickOverruns;

  /// The share of this window's ticks that overran, from 0 to 1.
  double get tickOverrunRate => _ticks == 0 ? 0 : _tickOverruns / _ticks;

  /// How much memory the process is holding, in bytes.
  ///
  /// A gauge, not a rate, and the only metric here whose *trend* matters more
  /// than its value: a flat line over thirty minutes is the pass. Any steady
  /// climb at a constant player count is a leak, and a five-minute run would
  /// never have shown it.
  int get residentBytes => readResidentBytes();

  /// Mean number of other players carried by one snapshot.
  ///
  /// The culling number. Compare it against [players]: far below means
  /// interest management is doing its job.
  double get averagePlayersPerSnapshot =>
      _snapshots == 0 ? 0 : _playersInSnapshots / _snapshots;

  /// Messages sent to clients per second across the whole server.
  double get outboundMessagesPerSecond => _perSecond(_outboundMessages);

  /// Bytes sent to clients per second across the whole server.
  double get outboundBytesPerSecond => _perSecond(_outboundBytes);

  /// Bytes per second sent to one client, on average.
  ///
  /// The number that decides whether this works on conference wifi.
  double get outboundBytesPerClientPerSecond =>
      _players == 0 ? 0 : outboundBytesPerSecond / _players;

  /// Messages received from clients per second.
  double get inboundMessagesPerSecond => _perSecond(_inboundMessages);

  /// The most players in any one grid cell during this window.
  ///
  /// A hot cell is what makes one client's snapshot far more expensive than
  /// the average, so the average alone would be a comforting lie.
  int get busiestCell => _busiestCell;

  /// Records one completed tick.
  ///
  /// [snapshots] counts the snapshots actually sent — a client with nobody
  /// nearby is sent nothing, and counting those as zero-player snapshots
  /// would flatter [averagePlayersPerSnapshot].
  void recordTick({
    required Duration duration,
    required int players,
    required int snapshots,
    required int playersInSnapshots,
    required int busiestCell,
  }) {
    _ticks++;
    final micros = duration.inMicroseconds;
    _tickMicros += micros;
    _worstTickMicros = math.max(_worstTickMicros, micros);
    final bucket = math.min(
      micros ~/ (bucketMillis * Duration.microsecondsPerMillisecond),
      bucketCount - 1,
    );
    _tickBuckets[bucket]++;
    if (micros > tickBudget.inMicroseconds) _tickOverruns++;
    _players = players;
    _peakPlayers = math.max(_peakPlayers, players);
    _snapshots += snapshots;
    _playersInSnapshots += playersInSnapshots;
    _busiestCell = math.max(_busiestCell, busiestCell);
  }

  /// Records one message sent to a client.
  ///
  /// [characters] is the encoded length. For this protocol's JSON that is the
  /// byte count too — every field name is ASCII, and only a display name can
  /// carry anything wider.
  void recordOutbound(int characters) {
    _outboundMessages++;
    _outboundBytes += characters;
  }

  /// Records one message received from a client.
  void recordInbound() => _inboundMessages++;

  /// Returns the one-line summary the server logs periodically.
  String get summary =>
      'players=$_players '
      'tick=${ticksPerSecond.toStringAsFixed(1)}/s '
      'avg=${averageTickMillis.toStringAsFixed(2)}ms '
      'p95=${p95TickMillis.toStringAsFixed(2)}ms '
      'worst=${worstTickMillis.toStringAsFixed(2)}ms '
      'overrun=$_tickOverruns '
      'perSnapshot=${averagePlayersPerSnapshot.toStringAsFixed(1)} '
      'busiestCell=$_busiestCell '
      'out=${outboundMessagesPerSecond.toStringAsFixed(0)}msg/s '
      '${_kib(outboundBytesPerSecond)}/s '
      '(${_kib(outboundBytesPerClientPerSecond)}/s/client) '
      'in=${inboundMessagesPerSecond.toStringAsFixed(0)}msg/s '
      'rss=${_mib(residentBytes)}';

  /// The machine-readable form, served on the metrics route.
  Map<String, Object?> toJson() => {
    'uptimeSeconds': uptime.inMilliseconds / 1000,
    'windowSeconds': window.inMilliseconds / 1000,
    'players': _players,
    'peakPlayers': _peakPlayers,
    'ticksPerSecond': _round(ticksPerSecond),
    'averageTickMillis': _round(averageTickMillis),
    'p95TickMillis': _round(p95TickMillis),
    'worstTickMillis': _round(worstTickMillis),
    'tickOverruns': _tickOverruns,
    'tickOverrunRate': _round(tickOverrunRate),
    'residentBytes': residentBytes,
    'averagePlayersPerSnapshot': _round(averagePlayersPerSnapshot),
    'busiestCell': _busiestCell,
    'outboundMessagesPerSecond': _round(outboundMessagesPerSecond),
    'outboundBytesPerSecond': _round(outboundBytesPerSecond),
    'outboundBytesPerClientPerSecond': _round(outboundBytesPerClientPerSecond),
    'inboundMessagesPerSecond': _round(inboundMessagesPerSecond),
  };

  /// Merges the metrics of several relays into one `/metrics` body.
  ///
  /// Phase 10 runs a relay per map inside one process, so `/metrics` has to
  /// describe a server made of parts. Every key keeps the meaning it had, so
  /// nothing already reading this route breaks:
  ///
  /// - **Counters and rates are summed.** They are load, and load adds up.
  ///   `averageTickMillis` is summed too, deliberately: it is "how long the
  ///   process spends ticking per cycle", and both relays tick on the same
  ///   clock.
  /// - **Latencies and gauges are the worst/largest.** A p95 that averaged
  ///   two relays would hide a beach that is struggling behind a conference
  ///   that is not, and RSS is one number for the whole process, not two.
  /// - **`averagePlayersPerSnapshot` is weighted by snapshots**, because an
  ///   unweighted mean of a busy map and an empty one is a fiction.
  static Map<String, Object?> mergeJson(Iterable<ServerMetrics> parts) {
    final all = parts.toList(growable: false);
    if (all.isEmpty) return ServerMetrics().toJson();
    if (all.length == 1) return all.single.toJson();

    var snapshots = 0;
    var playersInSnapshots = 0;
    for (final part in all) {
      snapshots += part._snapshots;
      playersInSnapshots += part._playersInSnapshots;
    }

    double sum(double Function(ServerMetrics) read) =>
        all.fold(0, (total, part) => total + read(part));
    double most(double Function(ServerMetrics) read) =>
        all.map(read).reduce(math.max);
    int sumInt(int Function(ServerMetrics) read) =>
        all.fold(0, (total, part) => total + read(part));
    int mostInt(int Function(ServerMetrics) read) =>
        all.map(read).reduce(math.max);

    return {
      'uptimeSeconds': most((m) => m.uptime.inMilliseconds / 1000),
      'windowSeconds': most((m) => m.window.inMilliseconds / 1000),
      'players': sumInt((m) => m.players),
      'peakPlayers': sumInt((m) => m.peakPlayers),
      'ticksPerSecond': _round(most((m) => m.ticksPerSecond)),
      'averageTickMillis': _round(sum((m) => m.averageTickMillis)),
      'p95TickMillis': _round(most((m) => m.p95TickMillis)),
      'worstTickMillis': _round(most((m) => m.worstTickMillis)),
      'tickOverruns': sumInt((m) => m.tickOverruns),
      'tickOverrunRate': _round(most((m) => m.tickOverrunRate)),
      'residentBytes': mostInt((m) => m.residentBytes),
      'averagePlayersPerSnapshot': _round(
        snapshots == 0 ? 0 : playersInSnapshots / snapshots,
      ),
      'busiestCell': mostInt((m) => m._busiestCell),
      'outboundMessagesPerSecond': _round(
        sum((m) => m.outboundMessagesPerSecond),
      ),
      'outboundBytesPerSecond': _round(sum((m) => m.outboundBytesPerSecond)),
      'outboundBytesPerClientPerSecond': _round(
        sum((m) => m.outboundBytesPerClientPerSecond),
      ),
      'inboundMessagesPerSecond': _round(
        sum((m) => m.inboundMessagesPerSecond),
      ),
    };
  }

  /// Starts a fresh measurement window, keeping only the player gauge.
  ///
  /// Rates are reported per window rather than since boot: an average over
  /// two hours would smear a load spike into nothing.
  void resetWindow() {
    _windowStart = _now();
    _peakPlayers = _players;
    _ticks = 0;
    _tickMicros = 0;
    _worstTickMicros = 0;
    _snapshots = 0;
    _playersInSnapshots = 0;
    _outboundMessages = 0;
    _outboundBytes = 0;
    _inboundMessages = 0;
    _busiestCell = 0;
    _tickOverruns = 0;
    _tickBuckets.fillRange(0, bucketCount, 0);
  }

  double _perSecond(int total) {
    final seconds = window.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return 0;
    return total / seconds;
  }

  static double _round(double value) => (value * 100).roundToDouble() / 100;

  static String _kib(double bytes) => '${(bytes / 1024).toStringAsFixed(1)}KiB';

  static String _mib(int bytes) =>
      '${(bytes / 1024 / 1024).toStringAsFixed(1)}MiB';

  /// The process's resident set, or zero where the platform will not say.
  ///
  /// `currentRss` throws on platforms that do not implement it, and a metrics
  /// call that can take the server down is worse than a missing number.
  static int _currentRss() {
    try {
      return ProcessInfo.currentRss;
    } on Object {
      return 0;
    }
  }
}
