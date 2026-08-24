import 'package:meta/meta.dart';
import 'package:protocol/src/json_reader.dart';

/// Where one player is, and nothing else.
///
/// This is the unit a snapshot repeats every tick, so it is deliberately
/// the smallest thing that can be said about a player: id and two numbers.
/// Name, colour and cosmetic never change mid-session, so they travel once —
/// as a full player state, when the player first appears — and never again.
/// At 15Hz × the players around you, that difference is most of the
/// bandwidth bill.
@immutable
class PlayerPosition {
  /// Creates a position.
  const PlayerPosition({required this.id, required this.x, required this.y});

  /// Reads a position from its JSON form.
  factory PlayerPosition.fromJson(Map<String, Object?> json) => PlayerPosition(
    id: readString(json, 'id'),
    x: readDouble(json, 'x'),
    y: readDouble(json, 'y'),
  );

  /// Whose position this is.
  final String id;

  /// Position along the world's x axis, in world units.
  final double x;

  /// Position along the world's y axis, in world units.
  final double y;

  /// Returns the JSON form of this position.
  ///
  /// A whole-numbered coordinate is written as an int, not a double. That
  /// looks like a triviality and is not: `842.1234567890123` is 19 characters
  /// and `842` is three, and this object is repeated for every neighbour, on
  /// every tick, to every client. Measured at 200 players it was the
  /// difference between 5.1KB and 2.7KB per snapshot — about half the
  /// server's entire outbound bandwidth, spent on precision finer than a
  /// thousandth of a pixel.
  ///
  /// The rounding itself happens where positions are put on the wire, not
  /// here, so this class never quietly changes a value it was handed.
  Map<String, Object?> toJson() => {
    'id': id,
    'x': _compact(x),
    'y': _compact(y),
  };

  /// Returns [value] as an int when it is a whole number, else unchanged.
  ///
  /// `readDouble` accepts either, so this is invisible to the far end.
  static Object _compact(double value) =>
      value == value.roundToDouble() ? value.toInt() : value;

  @override
  bool operator ==(Object other) =>
      other is PlayerPosition && other.id == id && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(id, x, y);

  @override
  String toString() => 'PlayerPosition($id, $x, $y)';
}
