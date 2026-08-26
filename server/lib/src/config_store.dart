import 'dart:convert';
import 'dart:io';

import 'package:protocol/protocol.dart';
import 'package:server/src/log.dart';

/// Where the event's config is kept when nobody says otherwise.
const String defaultConfigFilePath = 'config.json';

/// The largest config document this server will accept, in bytes.
///
/// Admin-gated, so this is less a hole than an **amplifier**: the document is
/// re-encoded and pushed to every player on every map, and to every
/// subsequent joiner, so one fat-fingered paste fans out across the whole
/// event.
///
/// Thirty-two kibibytes is roughly a hundred times the real document, which
/// is a handful of strings and a sponsor list.
///
/// It sits deliberately **below** the 64KiB frame ceiling on an admin socket.
/// If the two were the other way round the frame guard would fire first and
/// the moderator would see a silent drop instead of a sentence telling them
/// what went wrong — which, on the one screen in this system where somebody
/// is standing there waiting to be told they made a mistake, is the whole
/// difference between a usable tool and a broken one.
const int maxConfigDocumentBytes = 32 * 1024;

/// The one copy of the event's editable content, and the file behind it.
///
/// A file rather than a database for the same reason the ban list is one: this
/// is a few hundred bytes that a person has to be able to read — and fix —
/// with the tools already on the box, at eight in the morning, from a phone
/// over SSH if it comes to that.
///
/// **The file is a cache of the truth, not the truth.** The truth is
/// [config], held in memory, and every read goes to it. The file exists so
/// that the truth survives a restart. A disk that refuses to be written is
/// therefore a logged warning and not a refused edit: a moderator who cannot
/// fix the projector because the volume is full is a worse outcome than a
/// config that does not survive a restart nobody was planning.
class ConfigStore {
  /// Creates a store over [path], reading whatever is already there.
  ConfigStore({this.path = defaultConfigFilePath, LogSink log = logLine})
    : // A named parameter cannot be private, so this cannot be an
      // initializing formal.
      // ignore: prefer_initializing_formals
      _log = log {
    _load();
  }

  /// Creates a store that keeps nothing, for tests and for `--no-config`.
  ConfigStore.inMemory({AppConfig config = AppConfig.defaults})
    : path = null,
      _log = _silent,
      // A named parameter cannot be private, so this cannot be an
      // initializing formal.
      // ignore: prefer_initializing_formals
      _config = config;

  /// The file the config is persisted to, or `null` for a memory-only store.
  final String? path;

  final LogSink _log;

  AppConfig _config = AppConfig.defaults;

  /// What the event currently says it is.
  AppConfig get config => _config;

  /// [config] as the JSON document a client or an editor would read.
  String get document =>
      const JsonEncoder.withIndent('  ').convert(_config.toJson());

  /// The message that carries the current config to anybody who asks.
  ///
  /// Built here rather than at every call site so there is one answer to
  /// "what does the server say the config is", and it is this object's.
  ConfigMessage get message => ConfigMessage(config: _config);

  /// Replaces the config with [raw], or answers `null` if it is refused.
  ///
  /// Two ways to be refused, and the caller turns both into a sentence: [raw]
  /// is not a JSON object, or it is longer than [maxConfigDocumentBytes].
  ///
  /// Strict on purpose — see [tryParseAppConfig]. This is the one place in
  /// the whole system where somebody is standing there waiting to be told
  /// they made a mistake, and silently keeping the old config would look
  /// exactly like a push that worked.
  ///
  /// Writes through to [path] on success. A failed write is logged and
  /// swallowed; see the class comment for why.
  AppConfig? apply(String raw) {
    if (raw.length > maxConfigDocumentBytes) return null;

    final parsed = tryParseAppConfig(raw);
    if (parsed == null) return null;

    _config = parsed;
    _write();
    return parsed;
  }

  /// Closes the event until [until], or opens it when that is `null`, and
  /// says [message] while it is closed.
  ///
  /// Edits the held config rather than taking a document, because this is the
  /// one config change that is not somebody typing JSON: it comes from a
  /// picker, it changes three fields at most, and rebuilding the whole
  /// document around it on the client would be a second place for the other
  /// six to get lost.
  ///
  /// [message] and [showTimer] are both optional and both left alone when
  /// absent, so a caller that only means to move the moment cannot wipe the
  /// sentence a moderator typed for the window they are extending.
  ///
  /// Persisted like every other change, which is what makes a maintenance
  /// window survive the restart it probably exists for.
  AppConfig setMaintenanceUntil(
    DateTime? until, {
    String? message,
    bool? showTimer,
  }) {
    _config = _config.withMaintenanceUntil(
      until,
      message: message,
      showTimer: showTimer,
    );
    _write();
    return _config;
  }

  void _load() {
    final at = path;
    if (at == null) return;

    final file = File(at);
    if (!file.existsSync()) {
      _log('no config file at $at; serving the built-in defaults');
      return;
    }
    try {
      final parsed = tryParseAppConfig(file.readAsStringSync());
      if (parsed == null) {
        // Loud, and then carry on. A config file somebody broke by hand
        // must not stop the event starting, but it must not be silent
        // either — the whole room would be looking at last month's tagline
        // with nothing anywhere saying why.
        _log('config file at $at is not readable JSON; using the defaults');
        return;
      }
      _config = parsed;
      _log('loaded config from $at');
    } on FileSystemException catch (error) {
      _log('could not read the config at $at: ${error.message}');
    }
  }

  void _write() {
    final at = path;
    if (at == null) return;
    try {
      File(at).writeAsStringSync(document);
    } on FileSystemException catch (error) {
      _log('could not write the config to $at: ${error.message}');
    }
  }

  static void _silent(String line) {}
}
