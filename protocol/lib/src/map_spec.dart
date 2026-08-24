import 'package:meta/meta.dart';
import 'package:protocol/src/map_id.dart';
import 'package:protocol/src/world.dart';
import 'package:protocol/src/world_map.dart';

/// One place to be: how big it is, where it spawns, and what is in it.
///
/// Before Phase 10 all of this was top-level `const` in `world.dart` and a
/// flat `WorldZone` enum, which is to say the world was a **compile-time
/// constant**. Adding a second place meant turning it into a value that both
/// ends carry, and this is that value.
///
/// It lives in `protocol/` for exactly the reason `worldWidth` did: the
/// client clamps its bean to these bounds and the server clamps every inbound
/// position to the same ones, and two ideas of how big the beach is would put
/// remote beans in the sea.
///
/// Note what is *not* here: any art, any furniture, any collision. Those are
/// the client's business — the server is a relay and only needs to know where
/// the floor is so it can spawn people somewhere real.
@immutable
class MapSpec {
  const MapSpec._({
    required this.id,
    required this.width,
    required this.height,
    required this.spawnCenterX,
    required this.spawnCenterY,
    required this.spawnRingRadius,
    required this.zones,
    required this.edgeInset,
  });

  /// The conference venue: a cross with two filled corners, 1600x1200.
  ///
  /// Every number is the one the world already had. The equality of this and
  /// the old top-level constants is asserted in `map_spec_test.dart`, so the
  /// aliases in `world.dart` cannot quietly drift away from it.
  static const MapSpec conference = MapSpec._(
    id: MapId.conference,
    width: worldWidth,
    height: worldHeight,
    edgeInset: worldEdgeInset,
    // The middle of the atrium, written as an expression rather than as 800
    // so it stays the middle if the venue is ever resized. The top-level
    // `spawnCenterX` says the same thing and cannot be named here, because
    // this class has a field by that name.
    spawnCenterX: worldWidth / 2,
    spawnCenterY: worldHeight / 2,
    spawnRingRadius: 120,
    zones: [
      WorldZone.atrium,
      WorldZone.hall,
      WorldZone.sponsorRow,
      WorldZone.lounge,
      WorldZone.foodCourt,
      WorldZone.codeLab,
      WorldZone.garden,
    ],
  );

  /// The beach: three stacked bands, 1200x900, over half of it swimmable.
  ///
  /// The spawn ring is 80 rather than the conference's 120 because the sand
  /// band it has to fit inside is only 220 units tall — see
  /// [WorldZone.beachSand].
  static const MapSpec beach = MapSpec._(
    id: MapId.beach,
    width: beachWidth,
    height: beachHeight,
    edgeInset: worldEdgeInset,
    spawnCenterX: 600,
    spawnCenterY: 310,
    spawnRingRadius: 80,
    zones: [
      WorldZone.beachBoardwalk,
      WorldZone.beachSand,
      WorldZone.beachSea,
    ],
  );

  /// Every map there is, in the order a picker should show them.
  static const List<MapSpec> values = [conference, beach];

  /// Returns the spec for [id].
  static MapSpec of(MapId id) => switch (id) {
    MapId.conference => conference,
    MapId.beach => beach,
  };

  /// Which map this is.
  final MapId id;

  /// The width of this map's bounding box, in world units.
  final double width;

  /// The height of this map's bounding box, in world units.
  final double height;

  /// How far a bean is kept from the map's edge, in world units.
  final double edgeInset;

  /// Where new arrivals are placed, in world units.
  final double spawnCenterX;

  /// Where new arrivals are placed, in world units.
  final double spawnCenterY;

  /// How far from the spawn centre new arrivals are placed.
  ///
  /// A ring, not a point: a point puts forty people inside one another, and
  /// on the conference map it also puts them inside the credit pillar. Per
  /// map rather than global, because the band a beach arrival must land in is
  /// half the size of the atrium.
  final double spawnRingRadius;

  /// This map's floor, zone by zone.
  ///
  /// Written out rather than filtered from `WorldZone.values`, because a
  /// `where` is not a constant expression and this has to be one. The two are
  /// asserted to agree in `map_spec_test.dart`.
  final List<WorldZone> zones;

  /// Clamps [x] to this map's playable width.
  double clampX(double x) => x.clamp(edgeInset, width - edgeInset);

  /// Clamps [y] to this map's playable height.
  double clampY(double y) => y.clamp(edgeInset, height - edgeInset);

  /// The zone whose floor covers ([x], [y]) on this map, or `null`.
  WorldZone? zoneAt(double x, double y) {
    for (final zone in zones) {
      if (zone.rect.contains(x, y)) return zone;
    }
    return null;
  }

  /// Whether a bean's feet may stand at ([x], [y]) as far as the *map* is
  /// concerned.
  ///
  /// This answers "is this floor" and nothing else. Furniture is the client's
  /// business, because the client is the only thing that draws it and the
  /// only thing that decides where its own bean goes.
  bool isOnFloor(double x, double y) {
    for (final zone in zones) {
      if (zone.walkable.contains(x, y)) return true;
    }
    return false;
  }

  @override
  bool operator ==(Object other) => other is MapSpec && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MapSpec(${id.id}, ${width.toInt()}x${height.toInt()})';
}
