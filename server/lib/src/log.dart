import 'dart:io';

import 'package:server/src/token_bucket.dart';

/// Writes one timestamped line to stderr.
///
/// stderr, not stdout: logs stay out of anything a future command-line tool
/// might want to pipe. There is no logging package yet — one line of text per
/// event is all the server needs, and `print` is banned by the conventions.
void logLine(String message) {
  stderr.writeln('${DateTime.now().toIso8601String()}  $message');
}

/// The type of the log sink, so tests can capture lines instead of printing.
typedef LogSink = void Function(String message);

/// A log sink for the lines a *stranger* can cause the server to write.
///
/// **Why this exists.** Every guard on the inbound path used to announce
/// itself: a bad frame, an unreadable message, a message a client has no
/// business sending. Each is one line, which is fine until you multiply it.
/// The socket cap is 800 and the per-socket inbound budget is ~30 frames a
/// second, so the honest ceiling on those announcements is roughly 24,000
/// lines a second — and the guards that ran *before* the per-socket budget
/// had no ceiling at all. A flood aimed at nothing but the log costs the
/// attacker one malformed frame and costs the server disk, IO and a log
/// pipeline.
///
/// So: operational lines — the metrics summary, a socket opening, a kick —
/// keep going straight to [logLine], because the server causes those and
/// their rate is the server's own. Anything a client can trigger comes
/// through here instead, where one shared bucket caps the whole server rather
/// than one per connection. Per-connection would be no cap: the flood is a
/// thousand connections sending one line each.
///
/// Nothing is lost quietly. Lines refused while the bucket is empty are
/// counted, and the count rides along on the next line that gets through, so
/// an operator reading the log sees "this happened 40,000 times", which is
/// the fact they actually needed — not 40,000 copies of it.
class SecurityLog {
  /// Creates a sink that writes at most [burst] lines back to back.
  ///
  /// [now] is injectable for the same reason [TokenBucket] takes one: a rate
  /// limit has to be testable against a clock the test drives.
  SecurityLog({
    LogSink log = logLine,
    int burst = defaultBurst,
    Duration refill = defaultRefill,
    DateTime Function() now = DateTime.now,
  }) : // A named parameter cannot be private, so this cannot be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _log = log,
       _bucket = TokenBucket(burst: burst, refill: refill, now: now);

  /// How many security lines may be written back to back.
  ///
  /// Twenty is enough to see the shape of a real incident starting — several
  /// distinct guards firing at once still all get through — without letting a
  /// steady flood ride the burst.
  static const int defaultBurst = 20;

  /// How long one spent security-line token takes to come back.
  ///
  /// One a second. That is a rate a human reads and a disk ignores, and it is
  /// three orders of magnitude below what an unlimited path can produce.
  static const Duration defaultRefill = Duration(seconds: 1);

  final LogSink _log;
  final TokenBucket _bucket;

  int _suppressed = 0;

  /// How many lines have been refused since the last one that got through.
  ///
  /// Exposed for tests, and for nothing else.
  int get suppressed => _suppressed;

  /// Writes [message], unless the server is already writing too many.
  ///
  /// A [LogSink] by shape, so it can be handed anywhere one is expected.
  void write(String message) {
    if (!_bucket.allow()) {
      _suppressed++;
      return;
    }
    if (_suppressed == 0) {
      _log(message);
      return;
    }
    final dropped = _suppressed;
    _suppressed = 0;
    _log('$message  [+$dropped suppressed]');
  }
}
