/// The wire protocol shared by the client and the server.
///
/// Every message that crosses the WebSocket is defined here exactly once, so
/// the two ends can never drift apart. This package is deliberately pure Dart
/// with no Flutter dependency — the server could not import it otherwise.
library;

export 'src/admin.dart';
export 'src/app_config.dart';
export 'src/codec.dart';
export 'src/emote.dart';
export 'src/join_rejection.dart';
export 'src/map_id.dart';
export 'src/map_spec.dart';
export 'src/message_type.dart';
export 'src/messages.dart';
export 'src/name_validation.dart';
export 'src/player_position.dart';
export 'src/player_state.dart';
export 'src/protocol_version.dart';
export 'src/session_id.dart';
export 'src/world.dart';
export 'src/world_map.dart';
