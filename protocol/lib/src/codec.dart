import 'dart:convert';

import 'package:protocol/src/json_reader.dart';
import 'package:protocol/src/message_type.dart';
import 'package:protocol/src/messages.dart';

/// Encodes [message] as the JSON text that goes on the wire.
String encodeMessage(ProtocolMessage message) => jsonEncode(message.toJson());

/// Decodes wire text into a message, never throwing.
///
/// Anything unreadable — not JSON, not an object, an unknown `type`, a field
/// of the wrong shape — comes back as an [UnknownMessage] carrying the reason.
/// Both ends drop unknowns, which is what lets a client and a server run
/// slightly different builds without a flag day.
ProtocolMessage decodeMessage(String raw) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException catch (error) {
    return UnknownMessage(reason: 'not JSON: ${error.message}');
  }

  if (json is! Map<String, Object?>) {
    return UnknownMessage(
      reason: 'top level must be an object, got ${json.runtimeType}',
    );
  }
  return decodeMessageJson(json);
}

/// Decodes an already-parsed JSON object into a message, never throwing.
///
/// This is the one place that maps a `type` tag to a class. Nothing else in
/// either end may switch on the raw string.
ProtocolMessage decodeMessageJson(Map<String, Object?> json) {
  final rawType = json['type'];
  final type = MessageType.fromWireName(rawType is String ? rawType : null);

  try {
    switch (type) {
      case MessageType.join:
        return JoinMessage.fromJson(json);
      case MessageType.move:
        return MoveMessage.fromJson(json);
      case MessageType.welcome:
        return WelcomeMessage.fromJson(json);
      case MessageType.snapshot:
        return SnapshotMessage.fromJson(json);
      case MessageType.playerLeft:
        return PlayerLeftMessage.fromJson(json);
      case MessageType.joinRejected:
        return JoinRejectedMessage.fromJson(json);
      case MessageType.emote:
        return EmoteMessage.fromJson(json);
      case MessageType.playerEmoted:
        return PlayerEmotedMessage.fromJson(json);
      case MessageType.board:
        return BoardMessage.fromJson(json);
      case MessageType.playerBoard:
        return PlayerBoardMessage.fromJson(json);
      case MessageType.playerRenamed:
        return PlayerRenamedMessage.fromJson(json);
      case MessageType.worldStats:
        return WorldStatsMessage.fromJson(json);
      case MessageType.config:
        return ConfigMessage.fromJson(json);
      case MessageType.adminSetConfig:
        return AdminSetConfigMessage.fromJson(json);
      case MessageType.adminSetMaintenance:
        return AdminSetMaintenanceMessage.fromJson(json);
      case MessageType.adminAuth:
        return AdminAuthMessage.fromJson(json);
      case MessageType.adminAuthResult:
        return AdminAuthResultMessage.fromJson(json);
      case MessageType.adminPlayerList:
        return AdminPlayerListMessage.fromJson(json);
      case MessageType.adminKick:
        return AdminKickMessage.fromJson(json);
      case MessageType.adminBan:
        return AdminBanMessage.fromJson(json);
      case MessageType.adminBanList:
        return AdminBanListMessage.fromJson(json);
      case MessageType.adminUnban:
        return AdminUnbanMessage.fromJson(json);
      case MessageType.adminMuteName:
        return AdminMuteNameMessage.fromJson(json);
      case MessageType.adminActionResult:
        return AdminActionResultMessage.fromJson(json);
      case MessageType.adminError:
        return AdminErrorMessage.fromJson(json);
      case MessageType.unknown:
        // A message that says it is unknown is only produced by this
        // decoder, so it round-trips; anything else with an unreadable tag
        // lands here too and is reported as such.
        if (rawType == MessageType.unknown.wireName) {
          return UnknownMessage.fromJson(json);
        }
        return UnknownMessage(
          reason: 'unknown message type',
          rawType: rawType is String ? rawType : null,
        );
    }
  } on FormatException catch (error) {
    return UnknownMessage(
      reason: error.message,
      rawType: rawType is String ? rawType : null,
    );
  }
}

/// Reads the `version` field of an already-parsed message, when it has one.
///
/// Nothing rejects a message on version today — the field is recorded so a
/// future change can. Kept here so callers do not read the raw map by hand.
int? readMessageVersion(Map<String, Object?> json) {
  try {
    return readInt(json, 'version');
  } on FormatException {
    return null;
  }
}
