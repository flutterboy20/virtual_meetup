import 'package:meta/meta.dart';
import 'package:protocol/src/json_reader.dart';

/// A cosmetic worn on a bean's head.
///
/// Kept tiny on purpose: identity is mostly body colour, the cosmetic is the
/// second signal so two players with the same colour still read apart.
///
/// It lives in the protocol rather than in the client's rendering code
/// because it travels on the wire — one enum, so the two ends cannot drift.
enum PlayerCosmetic {
  /// Bare head.
  none('none'),

  /// A baseball cap, brim pointing the way the bean faces.
  cap('cap'),

  /// Over-ear headphones.
  headphones('headphones'),

  /// A mane of spiky blond curls.
  ///
  /// The one cosmetic drawn in a **fixed** colour rather than tinted from the
  /// body: hair the same shade as a lime-green shirt is a wig, not hair. Every
  /// other cosmetic keeps the tint, because the tint is what makes two players
  /// who picked the same body colour still read apart.
  malingaHair('malingaHair'),

  /// A visor of laser light, and the glowing eyes behind it.
  ///
  /// The second cosmetic whose colour is **fixed** rather than tinted from the
  /// body, for the same reason [malingaHair] is: a laser the same shade as a
  /// pastel shirt is not a laser. The band it sits in still takes the tint,
  /// so the prop is worn by a recognisable bean.
  ///
  /// It replaced a plain pair of shades, whose wire name is still accepted —
  /// see [fromWireName].
  laserVisor('laserVisor'),

  /// A beanie with a two-blade propeller on top.
  propellerBeanie('propellerBeanie');

  const PlayerCosmetic(this.wireName);

  /// The string written into a message's `cosmetic` field.
  final String wireName;

  /// Returns the cosmetic named by [wireName], or [PlayerCosmetic.none].
  ///
  /// An unrecognised cosmetic is a bare head rather than an error: a newer
  /// client wearing a hat this build has never heard of should still show up.
  static PlayerCosmetic fromWireName(String? wireName) {
    for (final cosmetic in PlayerCosmetic.values) {
      if (cosmetic.wireName == wireName) return cosmetic;
    }
    // The one legacy name. `shades` was this slot before it became a laser
    // visor, and a device that saved the old value should come back wearing
    // the thing that replaced it rather than silently losing its hat.
    if (wireName == _legacyShades) return PlayerCosmetic.laserVisor;
    return PlayerCosmetic.none;
  }

  /// The wire name [PlayerCosmetic.laserVisor] used to travel under.
  static const String _legacyShades = 'shades';
}

/// Everything one player looks like and where they are.
///
/// This is the unit the server keeps in its registry and the shape the client
/// needs to draw somebody else's bean.
@immutable
class PlayerState {
  /// Creates a player state.
  const PlayerState({
    required this.id,
    required this.name,
    required this.color,
    required this.cosmetic,
    required this.x,
    required this.y,
    this.hasBoard = false,
  });

  /// Reads a player state from its JSON form.
  ///
  /// Throws a [FormatException] if any field is missing or the wrong type.
  factory PlayerState.fromJson(Map<String, Object?> json) {
    return PlayerState(
      id: readString(json, 'id'),
      name: readString(json, 'name'),
      color: readInt(json, 'color'),
      cosmetic: PlayerCosmetic.fromWireName(readString(json, 'cosmetic')),
      x: readDouble(json, 'x'),
      y: readDouble(json, 'y'),
      hasBoard: readOptionalBool(json, 'hasBoard'),
    );
  }

  /// The server-assigned id. Unique for the lifetime of a connection.
  final String id;

  /// The display name the player joined with.
  final String name;

  /// The bean's body colour as a 32-bit ARGB value.
  ///
  /// An int, not a Flutter `Color`: `protocol/` must stay pure Dart or the
  /// server could not import it.
  final int color;

  /// The cosmetic worn on the bean's head.
  final PlayerCosmetic cosmetic;

  /// Position along the world's x axis, in world units.
  final double x;

  /// Position along the world's y axis, in world units.
  final double y;

  /// Whether this player has found the surfboard.
  ///
  /// A fact about a *player*, not about a position, which is the whole reason
  /// it lives here and not on `PlayerPosition`. It changes at most twice in a
  /// session, so it travels with the metadata that is sent once per
  /// appearance rather than with the two numbers that are repeated per
  /// neighbour fifteen times a second.
  ///
  /// Whether the board is actually *drawn* is never on the wire: a client
  /// works that out from this flag and its own copy of the map geometry,
  /// exactly as it already works out who is swimming.
  final bool hasBoard;

  /// Returns a copy of this state at ([x], [y]).
  PlayerState movedTo(double x, double y) => PlayerState(
    id: id,
    name: name,
    color: color,
    cosmetic: cosmetic,
    x: x,
    y: y,
    hasBoard: hasBoard,
  );

  /// Returns the JSON form of this state.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'cosmetic': cosmetic.wireName,
    'x': x,
    'y': y,
    'hasBoard': hasBoard,
  };

  @override
  bool operator ==(Object other) =>
      other is PlayerState &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.cosmetic == cosmetic &&
      other.x == x &&
      other.y == y &&
      other.hasBoard == hasBoard;

  @override
  int get hashCode => Object.hash(id, name, color, cosmetic, x, y, hasBoard);

  @override
  String toString() => 'PlayerState($id, $name, at $x,$y)';
}
