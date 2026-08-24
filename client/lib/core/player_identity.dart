import 'package:flutter/foundation.dart' show immutable;
import 'package:protocol/protocol.dart';

/// Who this device says it is: a stable session id plus how the bean looks.
///
/// The session id is the part that matters and the part nobody sees. Name,
/// colour and cosmetic are what the player chose and can change; the session
/// id is what lets the server recognise them across a dropped socket, so it
/// survives every edit to the other three.
///
/// A plain value object with no Flutter UI types in it — `color` is an `int`,
/// not a `Color` — so it can be handed straight to a [JoinMessage] and so the
/// ViewModels that hold it stay unit-testable.
@immutable
class PlayerIdentity {
  /// Creates an identity.
  const PlayerIdentity({
    required this.sessionId,
    required this.name,
    required this.color,
    required this.cosmetic,
  });

  /// This device's identity, generated once and persisted.
  final String sessionId;

  /// The display name the player chose.
  final String name;

  /// The bean's body colour as a 32-bit ARGB value.
  final int color;

  /// The cosmetic worn on the bean's head.
  final PlayerCosmetic cosmetic;

  /// Returns a copy with the given fields replaced.
  PlayerIdentity copyWith({
    String? name,
    int? color,
    PlayerCosmetic? cosmetic,
  }) => PlayerIdentity(
    // Deliberately not replaceable: changing your name must not make you a
    // different person to the server, or every edit would cost you your
    // place in the world.
    sessionId: sessionId,
    name: name ?? this.name,
    color: color ?? this.color,
    cosmetic: cosmetic ?? this.cosmetic,
  );

  /// Returns the join message this identity would send.
  ///
  /// Built here rather than at the call site so there is exactly one place
  /// that decides what goes into a join, and the reconnect path cannot drift
  /// from the first-connect path.
  JoinMessage toJoin() => JoinMessage(
    sessionId: sessionId,
    name: name,
    color: color,
    cosmetic: cosmetic,
  );

  @override
  bool operator ==(Object other) =>
      other is PlayerIdentity &&
      other.sessionId == sessionId &&
      other.name == name &&
      other.color == color &&
      other.cosmetic == cosmetic;

  @override
  int get hashCode => Object.hash(sessionId, name, color, cosmetic);

  @override
  String toString() => 'PlayerIdentity($name)';
}
