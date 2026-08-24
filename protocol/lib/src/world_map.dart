import 'package:meta/meta.dart';
import 'package:protocol/src/map_id.dart';
import 'package:protocol/src/world.dart';

/// An axis-aligned rectangle in world units.
///
/// `protocol/` cannot use `dart:ui`'s `Rect` — that would drag Flutter into a
/// package the server imports — so this is the smallest thing that does the
/// job for both ends.
@immutable
class WorldRect {
  /// Creates a rectangle from its four edges.
  const WorldRect(this.left, this.top, this.right, this.bottom);

  /// The x coordinate of the left edge.
  final double left;

  /// The y coordinate of the top edge.
  final double top;

  /// The x coordinate of the right edge.
  final double right;

  /// The y coordinate of the bottom edge.
  final double bottom;

  /// The distance between the left and right edges.
  double get width => right - left;

  /// The distance between the top and bottom edges.
  double get height => bottom - top;

  /// The x coordinate halfway between the left and right edges.
  double get centerX => (left + right) / 2;

  /// The y coordinate halfway between the top and bottom edges.
  double get centerY => (top + bottom) / 2;

  /// Whether ([x], [y]) is inside this rectangle, edges included.
  ///
  /// Inclusive on purpose: two zones that share an edge must both accept a
  /// point standing exactly on it, or the seam between them becomes a wall.
  bool contains(double x, double y) =>
      x >= left && x <= right && y >= top && y <= bottom;

  /// Returns this rectangle pulled inwards by the given amounts.
  WorldRect deflate({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) => WorldRect(
    this.left + left,
    this.top + top,
    this.right - right,
    this.bottom - bottom,
  );

  /// Returns this rectangle pushed outwards by [amount] on every edge.
  WorldRect inflate(double amount) =>
      WorldRect(left - amount, top - amount, right + amount, bottom + amount);

  @override
  bool operator ==(Object other) =>
      other is WorldRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'WorldRect($left, $top, $right, $bottom)';
}

/// Half the width of an arm of the cross, in world units.
const double _armHalf = 200;

/// The x coordinate of the world's centre line.
const double _midX = worldWidth / 2;

/// The y coordinate of the world's centre line.
const double _midY = worldHeight / 2;

/// The width of the beach, in world units.
///
/// Smaller than the conference on purpose — 1200x900 against 1600x1200, which
/// is 1.08M square units against 1.44M. A second place splits the crowd, and
/// Phase 9's own rule (empty floor is the enemy) bites twice as hard when the
/// same ~250 people are spread over two venues.
const double beachWidth = 1200;

/// The height of the beach, in world units.
const double beachHeight = 900;

/// Where the sand band starts, in world units.
const double _beachSandTop = 200;

/// Where the sand band ends and the sea begins, in world units.
const double _beachSeaTop = 420;

/// One of the rooms of the world.
///
/// The map is a **cross with two filled corners**, not a maze: four arms
/// meeting in a central atrium, joined by openings as wide as the arms
/// themselves, plus a Code Lab and a Garden Deck tucked into the north-east
/// and south-west corners. Every room shares at least one *full* edge with a
/// neighbour, so there are no corridors anywhere. That shape is a crowd
/// decision before it is an art decision — 200 people funnelled through a
/// doorway is a jam, and a jam in a social toy reads as a broken game.
///
/// ```txt
///         0     600  1000        1600
///    0   +------+----+------------+
///        | void |HALL|  CODE LAB  |
///  400   +------+----+------------+
///        | FOOD |ATRI| SPONSOR ROW|
///  800   +------+----+------------+
///        |GARDEN|POOL|    void    |
/// 1200   +------+----+------------+
/// ```
///
/// The two remaining corners stay **void** on purpose. Seven zones already
/// give ~1.44M square units of floor, which at the ~250-person target is
/// roughly 76x76 units per person against a 24-unit bean. Filling the voids
/// would add another ~480k for the same crowd, and a social toy dies when you
/// can walk ten seconds without passing anyone. Empty floor is the enemy.
///
/// The geometry lives in `protocol/` for the same reason [worldWidth] does:
/// the client walks it and the server spawns into it, and two ideas of where
/// the atrium is would put people in walls.
enum WorldZone {
  /// The centre of the cross: where everybody spawns.
  atrium(
    'atrium',
    'Atrium',
    WorldRect(
      _midX - _armHalf,
      _midY - _armHalf,
      _midX + _armHalf,
      _midY + _armHalf,
    ),
  ),

  /// North arm: the stage and its seating.
  hall(
    'hall',
    'Conference Hall',
    WorldRect(_midX - _armHalf, 0, _midX + _armHalf, _midY - _armHalf),
  ),

  /// East arm: the sponsor booths.
  sponsorRow(
    'sponsorRow',
    'Sponsor Row',
    WorldRect(_midX + _armHalf, _midY - _armHalf, worldWidth, _midY + _armHalf),
  ),

  /// South arm: the pool and the loungers.
  lounge(
    'lounge',
    'Lounge & Pool',
    WorldRect(
      _midX - _armHalf,
      _midY + _armHalf,
      _midX + _armHalf,
      worldHeight,
    ),
  ),

  /// West arm: the food stalls, the snack cart and the gather-here counter.
  foodCourt(
    'foodCourt',
    'Food Court',
    WorldRect(0, _midY - _armHalf, _midX - _armHalf, _midY + _armHalf),
  ),

  /// North-east corner: desk rows, a projector and a whiteboard.
  ///
  /// Shares its whole left edge with the hall and its whole bottom edge with
  /// the sponsor row, so it is reached by two wide-open walkways rather than
  /// by a corridor.
  codeLab(
    'codeLab',
    'Code Lab',
    WorldRect(_midX + _armHalf, 0, worldWidth, _midY - _armHalf),
  ),

  /// South-west corner: lawn, trees, a fountain and the stepped viewing deck.
  ///
  /// Shares its whole top edge with the food court and its whole right edge
  /// with the lounge, which is what puts the stepped deck within sight of the
  /// pool it looks out over.
  garden(
    'garden',
    'Garden Deck',
    WorldRect(0, _midY + _armHalf, _midX - _armHalf, worldHeight),
  ),

  /// The beach's top band: shacks, deck rails, and the way in.
  ///
  /// Deliberately shallow. It is the strip you arrive facing, not a room to
  /// spend time in — the things worth walking to are one band south.
  beachBoardwalk(
    'beachBoardwalk',
    'Boardwalk',
    WorldRect(0, 0, beachWidth, _beachSandTop),
    map: MapId.beach,
  ),

  /// The beach's middle band: umbrellas, towels, a dance floor and a net.
  ///
  /// The spawn band, and the only dry place with anything in it. 220 units
  /// tall, which is why the beach's spawn ring is 80 and not the conference's
  /// 120 — a 120-unit ring centred here would drop a third of new arrivals
  /// into the sea and another third onto the boardwalk, and a first frame
  /// spent underwater is a first frame spent confused.
  beachSand(
    'beachSand',
    'Sand',
    WorldRect(0, _beachSandTop, beachWidth, _beachSeaTop),
    map: MapId.beach,
  ),

  /// The beach's bottom band: walkable water, and 53% of the map.
  ///
  /// Swimmable, exactly the way the pool is — same `SwimState`, same
  /// `WaterWatcher`, same one boolean per bean per frame. The sea costs the
  /// protocol nothing for the same reason the pool does: every client has
  /// this rectangle and derives swimming from positions it already receives.
  beachSea(
    'beachSea',
    'Sea',
    WorldRect(0, _beachSeaTop, beachWidth, beachHeight),
    map: MapId.beach,
  );

  const WorldZone(
    this.id,
    this.label,
    this.rect, {
    this.map = MapId.conference,
  });

  /// The stable identifier, used in config files and logs.
  final String id;

  /// The name a human sees.
  final String label;

  /// The floor this zone covers.
  final WorldRect rect;

  /// Which map this zone belongs to.
  ///
  /// Defaulted rather than written out seven times, because every zone that
  /// existed before Phase 10 is a conference zone and re-typing that on each
  /// of them would be seven chances to get one wrong.
  ///
  /// **Coordinates are per map, not global.** The beach's rectangles overlap
  /// the conference's numerically, and they are meant to: they are two
  /// separate coordinate spaces that happen to use the same units. Anything
  /// that asks "which zone is at (x, y)" must therefore say *which map* —
  /// see `MapSpec.zoneAt`. The unqualified [WorldZone.at] answers for the
  /// conference, because that is what it answered before this field existed
  /// and every caller of it means the conference.
  final MapId map;

  /// The part of [rect] a bean's feet may actually stand on.
  ///
  /// Only the edges that face the *outside* of the building are inset. An
  /// edge shared with a neighbouring zone is left alone, because insetting it
  /// would put an invisible 24-unit wall across a walkway that is supposed to
  /// be wide open — the single easiest way to turn this map back into a maze.
  ///
  /// Each entry below is "which of my four edges has nothing on the far side
  /// of it", and adding a zone changes the answer for its neighbours too:
  /// the hall's right edge, the sponsor row's top edge, the lounge's left
  /// edge and the food court's bottom edge were all outward-facing when the
  /// map was a bare cross, and none of them are any more.
  WorldRect get walkable => switch (this) {
    // Ringed by the other four arms.
    WorldZone.atrium => rect,
    // Left faces the north-west void; top is the world edge.
    WorldZone.hall => rect.deflate(left: worldEdgeInset, top: worldEdgeInset),
    // Right is the world edge; bottom faces the south-east void.
    WorldZone.sponsorRow => rect.deflate(
      right: worldEdgeInset,
      bottom: worldEdgeInset,
    ),
    // Right faces the south-east void; bottom is the world edge.
    WorldZone.lounge => rect.deflate(
      right: worldEdgeInset,
      bottom: worldEdgeInset,
    ),
    // Left is the world edge; top faces the north-west void.
    WorldZone.foodCourt => rect.deflate(
      left: worldEdgeInset,
      top: worldEdgeInset,
    ),
    // Top and right are both the world edge.
    WorldZone.codeLab => rect.deflate(
      top: worldEdgeInset,
      right: worldEdgeInset,
    ),
    // Left and bottom are both the world edge.
    WorldZone.garden => rect.deflate(
      left: worldEdgeInset,
      bottom: worldEdgeInset,
    ),
    // The beach is three stacked bands, so on every one of them the only
    // shared edges are the horizontal ones and every vertical edge is the
    // world's. Inset the outward ones, leave the seams alone — the same rule
    // as above, applied to a much simpler shape.
    WorldZone.beachBoardwalk => rect.deflate(
      left: worldEdgeInset,
      top: worldEdgeInset,
      right: worldEdgeInset,
    ),
    WorldZone.beachSand => rect.deflate(
      left: worldEdgeInset,
      right: worldEdgeInset,
    ),
    WorldZone.beachSea => rect.deflate(
      left: worldEdgeInset,
      right: worldEdgeInset,
      bottom: worldEdgeInset,
    ),
  };

  /// Returns the zone named by [id], or `null`.
  static WorldZone? fromId(String? id) {
    for (final zone in WorldZone.values) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  /// The **conference** zone whose floor covers ([x], [y]), or `null`.
  ///
  /// Scoped to one map since Phase 10, because coordinates are per map and an
  /// unscoped search over `values` would answer "the boardwalk" for a point
  /// in the conference hall. Ask `MapSpec.zoneAt` when the map is a value
  /// rather than an assumption.
  static WorldZone? at(double x, double y) {
    for (final zone in WorldZone.values) {
      if (zone.map != MapId.conference) continue;
      if (zone.rect.contains(x, y)) return zone;
    }
    return null;
  }

  /// Every zone belonging to [map], in declaration order.
  static List<WorldZone> of(MapId map) =>
      WorldZone.values.where((zone) => zone.map == map).toList(growable: false);
}

/// Whether a bean's feet may stand at ([x], [y]) as far as the *map* is
/// concerned.
///
/// This answers "is this floor" and nothing else. Furniture — the stage, the
/// pool, the booths — is the client's business, because the client is the
/// only thing that draws it and the only thing that decides where its own
/// bean goes. The server is a relay: this is here so it can spawn people
/// somewhere real, not so it can police them.
/// Scoped to the **conference** since Phase 10 — see [WorldZone.at] for why.
/// `MapSpec.isOnFloor` is the same question asked of a map you hold as a
/// value, and it is what the client and the beach-aware paths use.
bool isOnFloor(double x, double y) {
  for (final zone in WorldZone.values) {
    if (zone.map != MapId.conference) continue;
    if (zone.walkable.contains(x, y)) return true;
  }
  return false;
}

/// Where the world begins for everybody, in world units.
const double spawnCenterX = _midX;

/// Where the world begins for everybody, in world units.
const double spawnCenterY = _midY;

/// How far from [spawnCenterX] / [spawnCenterY] new arrivals are placed.
///
/// A ring, not a point: the credit pillar stands at the exact centre of the
/// atrium, and 40 people spawning inside it would be both invisible and
/// stuck. A ring also spreads arrivals out enough that the first thing a new
/// player sees is other beans rather than one bean-shaped pile.
const double spawnRingRadius = 120;
