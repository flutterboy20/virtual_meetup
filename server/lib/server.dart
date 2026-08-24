/// The walk-around world's relay server.
///
/// The server is a relay, not a simulator: it never runs movement physics. It
/// keeps a registry of who is connected, and repeats what each client reports
/// about itself to the others.
library;

export 'src/admin_hub.dart';
export 'src/audit_log.dart';
export 'src/config.dart';
export 'src/config_store.dart';
export 'src/connection_gate.dart';
export 'src/handler.dart';
export 'src/log.dart';
export 'src/map_relays.dart';
export 'src/metrics.dart';
export 'src/metrics_csv.dart';
export 'src/moderation.dart';
export 'src/nearest.dart';
export 'src/player_registry.dart';
export 'src/relay.dart';
export 'src/spatial_grid.dart';
export 'src/token_bucket.dart';
export 'src/web_socket_upgrade.dart';
export 'src/ws_handler.dart';
