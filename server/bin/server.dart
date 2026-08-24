import 'dart:io';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final port = resolvePort(Platform.environment);
  final cellSize = resolveCellSize(Platform.environment);
  final sessionLinger = resolveSessionLinger(Platform.environment);
  final neighbourCap = resolveNeighbourCap(Platform.environment);
  // Read once, at the edge, and never logged. Everything downstream takes it
  // as a parameter, so there is no second place in the process that reaches
  // for the environment to find out whether it is allowed to do something.
  final adminToken = resolveAdminToken(Platform.environment);
  final banFilePath = resolveBanFilePath(Platform.environment);
  final auditFilePath = resolveAuditFilePath(Platform.environment);
  final kickCooldown = resolveKickCooldown(Platform.environment);
  final tickInterval = resolveTickInterval(Platform.environment);
  final metricsCsvPath = resolveMetricsCsvPath(Platform.environment);
  final configFilePath = resolveConfigFilePath(Platform.environment);
  final maxSockets = resolveMaxSockets(Platform.environment);
  final maxPlayers = resolveMaxPlayers(Platform.environment);
  final allowedOrigins = resolveAllowedOrigins(Platform.environment);

  // Opened before the relay starts ticking, so the very first reporting
  // window has somewhere to go.
  final recorder = MetricsRecorder(path: metricsCsvPath);
  await recorder.start();

  // The relays are built here rather than inside the handler because they
  // own the tick loops: whoever starts them has to be able to stop them.
  // One hub, one relay per map, one shared moderation state — a ban is a ban
  // on every map.
  // One gate for the process, built here and handed to the hub, exactly as
  // the config store, the audit log and the moderation state are. Both caps
  // sit far above the crowd this event expects; neither should ever fire on
  // the day, which is what a backstop is for.
  final gate = ConnectionGate(maxSockets: maxSockets, maxPlayers: maxPlayers);

  final hub = MapRelays(
    gate: gate,
    // Read from disk here, so a config a moderator pushed last night is the
    // config the first arrival this morning is handed.
    config: ConfigStore(path: configFilePath),
    cellSize: cellSize,
    sessionLinger: sessionLinger,
    neighbourCap: neighbourCap,
    tickInterval: tickInterval,
    audit: AuditLog(path: auditFilePath),
    recorder: recorder,
    moderation: ModerationState(
      storage: FileBanStorage(path: banFilePath, onError: logLine),
      kickCooldown: kickCooldown,
    ),
  );
  final admin = AdminHub(relays: hub, token: adminToken);

  await shelf_io.serve(
    buildHandler(relays: hub, admin: admin, allowedOrigins: allowedOrigins),
    InternetAddress.anyIPv4,
    port,
  );
  hub.start();
  admin.start();

  logLine(helloProtocol());
  logLine('listening on :$port');
  for (final map in MapId.values) {
    final spec = MapSpec.of(map);
    logLine(
      '  map:       ${map.id.padRight(10)} '
      '${spec.width.toInt()}x${spec.height.toInt()} units, '
      '${spec.zones.length} zones, '
      'interest cells of ${cellSize.toInt()}',
    );
  }
  logLine('  interest:  at most $neighbourCap neighbours per snapshot');
  logLine(
    '  capacity:  $maxSockets sockets (503 at the upgrade), '
    '$maxPlayers players (worldFull at the join)',
  );
  logLine(
    '  tick:      ${(1000 / tickInterval.inMilliseconds).toStringAsFixed(1)}Hz '
    '(${tickInterval.inMilliseconds}ms)',
  );
  logLine(
    '  sessions:  a dropped socket keeps its seat for '
    '${sessionLinger.inSeconds}s',
  );
  logLine(
    switch (allowedOrigins) {
      // Somebody asked for this by name, so say so in the words they used.
      null =>
        '  origins:   ANY — $allowedOriginsEnvVar=$anyOriginWildcard '
            '(development only)',
      // The unset case, and the one worth being loud about: the server works,
      // the moderator can moderate, and not one browser can connect.
      final origins when origins.isEmpty =>
        '  origins:   none — browsers are refused. '
            'Set $allowedOriginsEnvVar to your site, or '
            '$anyOriginWildcard for local development',
      final origins => '  origins:   ${origins.join(', ')}',
    },
  );
  logLine('  config:    http://localhost:$port/$configPath ($configFilePath)');
  logLine('  health:    http://localhost:$port/$healthPath');
  logLine('  metrics:   http://localhost:$port/$metricsPath');
  logLine('  websocket: ws://localhost:$port/$webSocketPath?map=<id>');
  // The token itself is never printed — only whether there is one, and how
  // many bans were carried over from the last run.
  logLine(
    admin.isEnabled
        ? '  moderation: on — ws://localhost:$port/$adminWebSocketPath, '
              '${hub.moderation.bannedCount} ban(s) loaded from '
              '$banFilePath'
        : '  moderation: OFF — set $adminTokenEnvVar to enable it',
  );
  if (admin.isEnabled) {
    logLine('  audit:     $auditFilePath');
    logLine(
      '  kicks:     a kicked session is refused for '
      '${kickCooldown.inSeconds}s',
    );
  }
}
