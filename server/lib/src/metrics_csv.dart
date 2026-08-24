import 'dart:async';
import 'dart:io';

import 'package:server/src/log.dart';
import 'package:server/src/metrics.dart';

/// Turns the server's metrics into rows a spreadsheet can chart.
///
/// The logged summary line is for watching a run; this is for judging one
/// afterwards. The questions Phase 7 asks — *is the memory line flat, is the
/// tick tail growing, does the snapshot size move when the crowd doubles* —
/// are all questions about a **trend**, and a trend cannot be read out of a
/// scrolling console. So every reporting window also becomes one row.
///
/// CSV rather than a metrics backend on purpose: one file, no daemon, opens
/// in anything, and it survives being emailed to somebody. The whole point of
/// this phase is evidence, and evidence has to be shareable.
abstract final class MetricsCsv {
  /// The column names, in the order [row] writes them.
  static const String header =
      'wallClock,uptimeSeconds,windowSeconds,players,peakPlayers,'
      'ticksPerSecond,averageTickMillis,p95TickMillis,worstTickMillis,'
      'tickOverruns,tickOverrunRate,averagePlayersPerSnapshot,busiestCell,'
      'outboundMessagesPerSecond,outboundBytesPerSecond,'
      'outboundBytesPerClientPerSecond,inboundMessagesPerSecond,residentBytes';

  /// Renders one window of [metrics] as a CSV row, without a line ending.
  ///
  /// [at] is passed in rather than read here so a test can pin the clock, and
  /// so the row's timestamp is the one the caller used to decide it was time
  /// to write a row.
  static String row(ServerMetrics metrics, {required DateTime at}) => [
    at.toUtc().toIso8601String(),
    _seconds(metrics.uptime),
    _seconds(metrics.window),
    metrics.players,
    metrics.peakPlayers,
    _round(metrics.ticksPerSecond),
    _round(metrics.averageTickMillis),
    _round(metrics.p95TickMillis),
    _round(metrics.worstTickMillis),
    metrics.tickOverruns,
    _round(metrics.tickOverrunRate),
    _round(metrics.averagePlayersPerSnapshot),
    metrics.busiestCell,
    _round(metrics.outboundMessagesPerSecond),
    _round(metrics.outboundBytesPerSecond),
    _round(metrics.outboundBytesPerClientPerSecond),
    _round(metrics.inboundMessagesPerSecond),
    metrics.residentBytes,
  ].join(',');

  static String _seconds(Duration duration) =>
      (duration.inMilliseconds / 1000).toStringAsFixed(1);

  static String _round(double value) => value.toStringAsFixed(2);
}

/// Appends a metrics row per reporting window to a file.
///
/// Opened once and held open, because opening a file on every window would
/// put a syscall on a timer that also has to be honest about what the server
/// costs. Appends rather than truncates: two runs against one file is a
/// nuisance, a run that silently erased the last one is a lost afternoon.
class MetricsRecorder {
  /// Creates a recorder that writes to [path].
  ///
  /// A `null` [path] means recording is off, and every method becomes a
  /// no-op. That is the default, so an ordinary server never writes a file
  /// nobody asked for.
  MetricsRecorder({required this.path, LogSink log = logLine})
    : // A named parameter cannot be private, so this cannot be an
      // initializing formal.
      // ignore: prefer_initializing_formals
      _log = log;

  /// Where rows are appended, or `null` when recording is off.
  final String? path;

  final LogSink _log;

  IOSink? _sink;

  /// Whether rows are actually being written.
  bool get isRecording => _sink != null;

  /// Opens the file and writes the header if it is a fresh one.
  ///
  /// A failure here is logged and swallowed. A load run that cannot write its
  /// CSV is worth complaining about; it is not worth refusing to serve the
  /// conference over.
  Future<void> start() async {
    final target = path;
    if (target == null || _sink != null) return;
    try {
      final file = File(target);
      final fresh = !file.existsSync() || file.lengthSync() == 0;
      // Probed with a synchronous open first. `openWrite` hands back a sink
      // whether or not the path is writable and only fails later, on a
      // future nobody is awaiting — so without this a bad path would look
      // like a working recorder that silently records nothing.
      file.openSync(mode: FileMode.append).closeSync();
      final sink = file.openWrite(mode: FileMode.append);
      unawaited(
        sink.done.catchError((Object error) {
          _sink = null;
          _log('metrics csv failed ($target): $error');
        }),
      );
      _sink = sink;
      if (fresh) sink.writeln(MetricsCsv.header);
      _log('  profile:   recording metrics to $target');
    } on Object catch (error) {
      _sink = null;
      _log('metrics csv unavailable ($target): $error');
    }
  }

  /// Writes one row for the window that just closed.
  void record(ServerMetrics metrics, {DateTime? at}) {
    final sink = _sink;
    if (sink == null) return;
    try {
      sink.writeln(MetricsCsv.row(metrics, at: at ?? DateTime.now()));
    } on Object catch (error) {
      _log('metrics csv write failed: $error');
    }
  }

  /// Flushes and closes the file.
  Future<void> stop() async {
    final sink = _sink;
    _sink = null;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } on Object {
      // A file that is already gone does not need closing twice.
    }
  }
}
