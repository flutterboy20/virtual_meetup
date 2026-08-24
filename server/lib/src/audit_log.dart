import 'dart:io';

import 'package:protocol/protocol.dart';
import 'package:server/src/log.dart';

/// The file audit lines are appended to when nothing overrides it.
const String defaultAuditFilePath = 'audit.log';

/// A record of every privileged action taken against the world.
///
/// Two sinks on purpose. The log line is what you read *during* the event,
/// tailing stderr next to everything else the server is saying. The file is
/// what you read *after* it, when somebody asks what happened to them and
/// stderr has long since scrolled away or been rotated by a host.
///
/// What is deliberately not in here: the admin token, the target's session
/// id, or anything else that would turn the audit trail into a second copy of
/// the secrets. An audit log is written precisely because something went
/// wrong, so it is the last file that should be worth stealing.
class AuditLog {
  /// Creates an audit log.
  ///
  /// [path] is where lines are appended; pass `null` for the log line only,
  /// which is what the tests use. [now] is injectable so a test can assert on
  /// an exact timestamp.
  AuditLog({
    this.path = defaultAuditFilePath,
    LogSink log = logLine,
    DateTime Function() now = DateTime.now,
  }) : // Named parameters cannot be private, so neither of these can be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _log = log,
       // A named parameter cannot be private.
       // ignore: prefer_initializing_formals
       _now = now;

  /// Where lines are appended, or `null` to write nowhere but the log.
  final String? path;

  final LogSink _log;
  final DateTime Function() _now;

  /// Records that [action] was taken against [targetId], then called
  /// [targetName].
  ///
  /// The name is recorded alongside the id because an id means nothing a week
  /// later, and the name is what the report that triggered the action used.
  void record({
    required AdminAction action,
    required String targetId,
    required String targetName,
  }) {
    final line =
        '${_now().toIso8601String()}\t${action.wireName}\t'
        '$targetId\t$targetName';
    _log('audit: $line');
    _append(line);
  }

  void _append(String line) {
    final target = path;
    if (target == null) return;
    try {
      File(target).writeAsStringSync('$line\n', mode: FileMode.append);
    } on Object catch (error) {
      // A disk that will not take the line must not stop the kick going
      // through. Losing the record is bad; leaving the disruption in the room
      // is worse.
      _log('could not append to the audit log at $target: $error');
    }
  }
}
