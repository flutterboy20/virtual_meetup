import 'package:server/src/audit_log.dart';
import 'package:server/src/config_store.dart';
import 'package:server/src/connection_gate.dart';
import 'package:server/src/moderation.dart';
import 'package:server/src/player_registry.dart';
import 'package:server/src/relay.dart';
import 'package:server/src/spatial_grid.dart';

/// The port used when the environment does not name one.
const int defaultPort = 8080;

/// The environment variable that overrides [defaultPort].
const String portEnvVar = 'PORT';

/// Resolves the TCP port to listen on from [environment].
///
/// Falls back to [defaultPort] when [portEnvVar] is absent or empty. A value
/// that is present but not a valid port is a deployment mistake, so it throws
/// rather than silently starting on the wrong port.
int resolvePort(Map<String, String> environment) {
  final raw = environment[portEnvVar];
  if (raw == null || raw.trim().isEmpty) return defaultPort;

  final port = int.tryParse(raw.trim());
  if (port == null || port < 1 || port > 65535) {
    throw FormatException(
      '$portEnvVar must be an integer in 1..65535, got "$raw"',
    );
  }
  return port;
}

/// The environment variable that overrides the interest grid's cell size.
const String cellSizeEnvVar = 'CELL_SIZE';

/// Resolves the interest grid's cell edge, in world units, from [environment].
///
/// Tunable from the outside because it is the one number the load test wants
/// to sweep: too small and players pop in at the edge of the screen, too
/// large and everybody is everybody's neighbour and the culling buys nothing.
/// Falls back to [SpatialGrid.defaultCellSize].
double resolveCellSize(Map<String, String> environment) {
  final raw = environment[cellSizeEnvVar];
  if (raw == null || raw.trim().isEmpty) return SpatialGrid.defaultCellSize;

  final size = double.tryParse(raw.trim());
  if (size == null || !size.isFinite || size <= 0) {
    throw FormatException(
      '$cellSizeEnvVar must be a positive number, got "$raw"',
    );
  }
  return size;
}

/// The environment variable that overrides the neighbour cap.
const String neighbourCapEnvVar = 'NEIGHBOUR_CAP';

/// Resolves the most neighbours one snapshot may carry, from [environment].
///
/// Tunable from the outside because it is the second thing the load test
/// wants to sweep, and the right value depends on how the crowd actually
/// bunches up on the day. Falls back to [Relay.defaultNeighbourCap].
///
/// Rejects zero: a cap of nothing would leave every client alone in an empty
/// world, which is a configuration mistake that would look exactly like a
/// broken server.
int resolveNeighbourCap(Map<String, String> environment) {
  final raw = environment[neighbourCapEnvVar];
  if (raw == null || raw.trim().isEmpty) return Relay.defaultNeighbourCap;

  final cap = int.tryParse(raw.trim());
  if (cap == null || cap < 1) {
    throw FormatException(
      '$neighbourCapEnvVar must be a whole number >= 1, got "$raw"',
    );
  }
  return cap;
}

/// The environment variable that overrides the hard socket cap.
const String maxSocketsEnvVar = 'MAX_SOCKETS';

/// Resolves the most sockets this server will hold open, from [environment].
///
/// The hard cap, and the only one an attacker meets: it is checked at the
/// HTTP upgrade, before a socket is allocated. Falls back to
/// [ConnectionGate.defaultMaxSockets].
///
/// Rejects zero for the same reason [resolveNeighbourCap] does: a server that
/// admits nobody is indistinguishable from a server that is down, and a
/// misconfiguration that looks like an outage is the worst kind.
int resolveMaxSockets(Map<String, String> environment) {
  final raw = environment[maxSocketsEnvVar];
  if (raw == null || raw.trim().isEmpty) {
    return ConnectionGate.defaultMaxSockets;
  }

  final cap = int.tryParse(raw.trim());
  if (cap == null || cap < 1) {
    throw FormatException(
      '$maxSocketsEnvVar must be a whole number >= 1, got "$raw"',
    );
  }
  return cap;
}

/// The environment variable that overrides the soft player cap.
const String maxPlayersEnvVar = 'MAX_PLAYERS';

/// Resolves the most players this server will seat, from [environment].
///
/// The soft cap, and the one a *person* meets: a join past it is refused with
/// `JoinRejection.worldFull`, which costs a socket precisely so the client
/// can be told why in words it can render. Falls back to
/// [ConnectionGate.defaultMaxPlayers].
int resolveMaxPlayers(Map<String, String> environment) {
  final raw = environment[maxPlayersEnvVar];
  if (raw == null || raw.trim().isEmpty) {
    return ConnectionGate.defaultMaxPlayers;
  }

  final cap = int.tryParse(raw.trim());
  if (cap == null || cap < 1) {
    throw FormatException(
      '$maxPlayersEnvVar must be a whole number >= 1, got "$raw"',
    );
  }
  return cap;
}

/// The environment variable that overrides the session linger window.
const String sessionLingerEnvVar = 'SESSION_LINGER_SECONDS';

/// Resolves how long a departed session's seat is held, from [environment].
///
/// Tunable because the right answer depends on the venue: a hall with solid
/// wifi wants a short window so a seat is freed promptly, and a basement with
/// dead spots wants a long one so a two-minute outage is not a kick. Falls
/// back to [defaultSessionLinger].
///
/// Zero is allowed and means "hold nothing" — a returning client is simply a
/// new player. That is a legitimate configuration, not a mistake, so it is
/// not rejected.
Duration resolveSessionLinger(Map<String, String> environment) {
  final raw = environment[sessionLingerEnvVar];
  if (raw == null || raw.trim().isEmpty) return defaultSessionLinger;

  final seconds = int.tryParse(raw.trim());
  if (seconds == null || seconds < 0) {
    throw FormatException(
      '$sessionLingerEnvVar must be a whole number of seconds >= 0, '
      'got "$raw"',
    );
  }
  return Duration(seconds: seconds);
}

/// The environment variable that overrides the kick cooldown.
const String kickCooldownEnvVar = 'KICK_COOLDOWN_SECONDS';

/// Resolves how long a kicked session is refused, from [environment].
///
/// Tunable because it is the one moderation number with a judgement call in
/// it: too short and the client's own reconnect walks the person straight
/// back in, too long and a warning shot has become a ban nobody recorded.
/// Falls back to [defaultKickCooldown].
///
/// Zero is allowed and means the kick is a disconnect and nothing more —
/// which is the behaviour to pick only if the clients are known to not
/// reconnect on their own.
Duration resolveKickCooldown(Map<String, String> environment) {
  final raw = environment[kickCooldownEnvVar];
  if (raw == null || raw.trim().isEmpty) return defaultKickCooldown;

  final seconds = int.tryParse(raw.trim());
  if (seconds == null || seconds < 0) {
    throw FormatException(
      '$kickCooldownEnvVar must be a whole number of seconds >= 0, '
      'got "$raw"',
    );
  }
  return Duration(seconds: seconds);
}

/// The environment variable holding the admin token.
///
/// The name is public; the value never is. It is read from the process
/// environment at startup and never written into the client, into a config
/// file, or into a log line.
const String adminTokenEnvVar = 'ADMIN_TOKEN';

/// The shortest admin token the server will accept.
///
/// A short shared secret over a public WebSocket is guessable at leisure, and
/// the thing it guards is the ability to disconnect every attendee. Sixteen
/// characters is not a security theory, it is a floor low enough to type on a
/// phone and high enough that nobody sets it to "admin".
const int minAdminTokenLength = 16;

/// Resolves the admin token from [environment], or `null` if there is none.
///
/// A missing token means **admin is switched off**, not that admin is open:
/// the hub refuses every message on every admin socket. A deployment that
/// forgot the variable gets no moderation, which is a bad day; the other
/// default gets unauthenticated moderation, which is a much worse one.
///
/// A token that is present but too short throws, because that is a mistake
/// somebody made on purpose and it should not survive to the event.
String? resolveAdminToken(Map<String, String> environment) {
  final raw = environment[adminTokenEnvVar];
  if (raw == null || raw.trim().isEmpty) return null;

  final token = raw.trim();
  if (token.length < minAdminTokenLength) {
    throw FormatException(
      '$adminTokenEnvVar must be at least $minAdminTokenLength characters; '
      'the one supplied is ${token.length}',
    );
  }
  return token;
}

/// The environment variable naming the origins a browser may connect from.
///
/// Comma-separated: `https://meet.example.com,https://www.example.com`.
const String allowedOriginsEnvVar = 'ALLOWED_ORIGINS';

/// The value of [allowedOriginsEnvVar] that means "every origin".
///
/// Spelled out rather than reached by leaving the variable unset, so that
/// running a server open to the whole web is something somebody typed.
const String anyOriginWildcard = '*';

/// Resolves the origins a browser may connect from.
///
/// Three answers, and the difference between the first two is the point:
///
/// - **Unset or blank → an empty set: no browser origin at all.** A browser
///   pointed at this server from any page is refused at the handshake.
/// - **`*` → `null`: every origin.** The development escape hatch, and the
///   only way to reach the old behaviour.
/// - **A comma-separated list → those origins.**
///
/// **This default was flipped deliberately, and it is a breaking change for
/// anybody running the server locally.** Unset used to mean *allow any*, on
/// the reasoning that local development and the LAN demo should need no
/// environment at all. The cost of that convenience is that the safe
/// configuration was the one you had to remember, and the exposed one was the
/// one you got by saying nothing — so a production deploy that forgot the
/// variable was indistinguishable, in the logs and in behaviour, from one
/// that had been configured correctly.
///
/// Now forgetting it fails loudly and safely: browsers cannot connect, which
/// is obvious within seconds of the first person trying, rather than silently
/// leaving the door open for the length of the event. Local development sets
/// `$allowedOriginsEnvVar=*` once and is otherwise unchanged.
///
/// Each entry is trimmed and lowercased, because that is the form
/// `shelf_web_socket` compares against and a list that only works when
/// somebody types it in the right case is a list that will be typed in the
/// wrong one.
///
/// **What this does, and what it emphatically does not.**
///
/// It stops a hostile web page from using its visitors' browsers to open
/// sockets against this server. A browser always sends `Origin`, so a page on
/// an unlisted origin is refused at the handshake. That is the entire
/// benefit, and it is real.
///
/// It does **not** stop `curl`, or anybody who can be bothered.
/// `shelf_web_socket` refuses a connection only when an `Origin` header is
/// *present* and unlisted; a request with no `Origin` at all passes straight
/// through. That is deliberate on their part and correct for us — it is what
/// keeps `tool/loadtest/` working with no change, which matters because a
/// hardening phase that broke the load tester would simply be undone at the
/// next load-testing phase.
///
/// **Origin pinning is not access control** and must never be written about
/// here or anywhere else as though it were. The socket cap in
/// [resolveMaxSockets] is what stops the attacker who sends no `Origin`; this
/// stops a different attacker entirely.
Set<String>? resolveAllowedOrigins(Map<String, String> environment) {
  final raw = environment[allowedOriginsEnvVar];
  // The safe end of the flip: say nothing, get nothing.
  if (raw == null || raw.trim().isEmpty) return const {};

  final origins = <String>{
    for (final entry in raw.split(','))
      if (entry.trim().isNotEmpty) entry.trim().toLowerCase(),
  };
  // A value that was present but held nothing but commas and spaces is a
  // mistake, and reading it as anything at all would be guessing at a typo.
  if (origins.isEmpty) {
    throw FormatException(
      '$allowedOriginsEnvVar was set but names no origins, got "$raw"',
    );
  }

  if (origins.contains(anyOriginWildcard)) {
    // Alone, or not at all. A list that mixes the wildcard with real origins
    // cannot be read: either the wildcard is redundant or the origins are,
    // and which one the author meant is exactly the thing not to guess about.
    if (origins.length > 1) {
      throw FormatException(
        '$allowedOriginsEnvVar mixes "$anyOriginWildcard" with named '
        'origins, got "$raw". Use one or the other.',
      );
    }
    return null;
  }

  return origins;
}

/// The environment variable that overrides where bans are persisted.
const String banFileEnvVar = 'BAN_FILE';

/// Resolves the path the ban list is kept at, from [environment].
///
/// A path rather than a database because a ban list at this scale is a few
/// dozen strings, and because during an incident you want to be able to read
/// it — and empty it — with the tools already on the box.
String resolveBanFilePath(Map<String, String> environment) {
  final raw = environment[banFileEnvVar];
  if (raw == null || raw.trim().isEmpty) return defaultBanFilePath;
  return raw.trim();
}

/// The environment variable that overrides where the event's config is kept.
const String configFileEnvVar = 'CONFIG_FILE';

/// Resolves the path the event's config is kept at, from [environment].
///
/// A file, for the same reason the ban list is one: it is a few hundred bytes
/// somebody has to be able to read and fix with the tools already on the box.
String resolveConfigFilePath(Map<String, String> environment) {
  final raw = environment[configFileEnvVar];
  if (raw == null || raw.trim().isEmpty) return defaultConfigFilePath;
  return raw.trim();
}

/// The environment variable that overrides where the audit log is appended.
const String auditFileEnvVar = 'AUDIT_FILE';

/// Resolves the path admin actions are appended to, from [environment].
String resolveAuditFilePath(Map<String, String> environment) {
  final raw = environment[auditFileEnvVar];
  if (raw == null || raw.trim().isEmpty) return defaultAuditFilePath;
  return raw.trim();
}

/// The environment variable that overrides the snapshot tick rate.
const String tickHzEnvVar = 'TICK_HZ';

/// The fastest tick rate the server will accept, in Hz.
///
/// Above this the outbound cost climbs while nothing visibly improves — the
/// client interpolates between snapshots at 60fps regardless — so a value up
/// here is a typo, not a tuning decision.
const double maxTickHz = 60;

/// Resolves the gap between snapshots from [environment].
///
/// Expressed in Hz rather than milliseconds because that is the unit the
/// tuning conversation happens in ("does 10Hz still feel smooth?"), and the
/// conversion to a timer interval is arithmetic nobody should do by hand at
/// the command line.
///
/// This is *the* knob of Phase 7: it multiplies straight into outbound
/// messages, outbound bytes, and server CPU, and it trades against how much
/// interpolation the client needs to hide the gaps. Falls back to
/// [Relay.defaultTickInterval].
Duration resolveTickInterval(Map<String, String> environment) {
  final raw = environment[tickHzEnvVar];
  if (raw == null || raw.trim().isEmpty) return Relay.defaultTickInterval;

  final hz = double.tryParse(raw.trim());
  if (hz == null || !hz.isFinite || hz <= 0 || hz > maxTickHz) {
    throw FormatException(
      '$tickHzEnvVar must be a number in 0..$maxTickHz Hz, got "$raw"',
    );
  }
  // Rounded to whole milliseconds because that is the resolution a Dart timer
  // has; asking for 23.7Hz and silently getting 23.8 is worse than being told
  // what you actually got, which the startup banner prints.
  final millis = (1000 / hz).round();
  return Duration(milliseconds: millis < 1 ? 1 : millis);
}

/// The environment variable naming the CSV the profiler writes.
const String metricsCsvEnvVar = 'METRICS_CSV';

/// Resolves where per-window metrics rows are appended, or `null` for none.
///
/// Off by default. Profiling writes a file, and a server that writes files
/// nobody asked for is a server that fills a disk during a six-hour event.
String? resolveMetricsCsvPath(Map<String, String> environment) {
  final raw = environment[metricsCsvEnvVar];
  if (raw == null || raw.trim().isEmpty) return null;
  return raw.trim();
}
