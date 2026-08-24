import 'package:client/game/bot_brain.dart';
import 'package:client/game/game_map.dart';
import 'package:client/game/world_layout.dart' show ConferenceBots;
import 'package:protocol/protocol.dart';

/// Where everything on the beach stands.
///
/// The beach's answer to `WorldLayout`: a table of coordinates, `static const`
/// for the same reason, and read by both the art (`BeachProps`) and the
/// collision list below it. Furniture drawn in one place and collided in
/// another is the classic invisible wall, and it is always found by a player
/// rather than by a test.
///
/// **The sea holds no obstacles at all.** The buoy cluster and the sandbar are
/// drawn and nothing else, and the raft blocks nothing either. Two reasons,
/// and the second is the one that matters:
///
/// - Being stopped dead by a raft while swimming is the single most
///   irritating thing this map could do.
/// - They exist to be **places to swim towards**. A thin crowd spread over
///   1.08M square units needs somewhere to collect, and a landmark does that
///   job whether or not it is solid. Making them solid would add nothing and
///   cost the one thing the sea is for.
///
/// The raft is the one thing in the water that is not *only* drawn: it is a
/// dry platform (see [dryPlatforms]). You swim out to it and walk onto it,
/// which is the opposite of being blocked by it.
abstract final class BeachLayout {
  /// The sea, as a rectangle.
  ///
  /// The same numbers as `WorldZone.beachSea.rect`, written out because a
  /// field read off a const object is not a constant expression and the water
  /// region list has to be one.
  static const WorldRect sea = WorldRect(0, 420, beachWidth, beachHeight);

  // ---- Boardwalk (north band) ---------------------------------------------

  /// The shacks along the boardwalk: juice, a pub, a shop.
  ///
  /// Three of them, with wide gaps. The boardwalk is 200 units deep and it is
  /// the strip everybody arrives facing, so anything that narrows it narrows
  /// the way in.
  static const List<RectObstacle> shacks = [
    RectObstacle(WorldRect(120, 44, 300, 150)),
    RectObstacle(WorldRect(500, 44, 680, 150)),
    RectObstacle(WorldRect(900, 44, 1080, 150)),
  ];

  /// What each shack is called, in the same order as [shacks].
  static const List<String> shackNames = ['JUICE', 'PUB', 'SHOP'];

  /// Which of [shacks] is the pub, so the decks land in front of the right
  /// one.
  static const int pubIndex = 1;

  // ---- The pub (boardwalk, in front of the middle shack) ------------------

  /// The DJ booth in front of the pub.
  ///
  /// Drawn and **not** collided, like the awning and the volleyball net: the
  /// boardwalk is only 200 units deep and it is the strip everybody arrives
  /// facing, so a solid box parked in the middle of it would narrow the way
  /// in. The DJ standing behind it is a bot, not a wall.
  static const WorldRect djBooth = WorldRect(536, 152, 644, 186);

  /// Where the DJ stands, behind the decks, in world units.
  ///
  /// y=158 and not 150: the pub shack's footprint runs to y=150 inclusive, so
  /// a bot on that line would be standing inside the wall it is meant to be
  /// standing in front of.
  static const double djX = 590;

  /// Where the DJ stands, behind the decks, in world units.
  static const double djY = 158;

  /// The checkered dance floor.
  ///
  /// East of the booth rather than south of it, and that is the whole reason
  /// for these numbers: the beach's spawn ring is at (600, 310) with a radius
  /// of 80, so a floor directly south of the pub would have been painted
  /// under everybody's first frame. x 700–860 clears it by 40 units.
  static const WorldRect danceFloor = WorldRect(700, 190, 860, 260);

  /// Where the mirrorball hangs over the floor, in world units.
  ///
  /// Written out rather than read off [danceFloor], because a field read off a
  /// const object is not a constant expression — the same reason [sea] repeats
  /// the zone's numbers instead of borrowing them.
  static const double discoX = 780;

  /// Where the mirrorball hangs over the floor, in world units.
  static const double discoY = 176;

  /// How big the warm patch over the dance floor is, in world units.
  ///
  /// This map's one gather-here glow, and the beach's answer to the food
  /// court. Same component, same smoothing, same restraint: it brightens when
  /// people stand on it and does nothing else. The instant it counts down or
  /// awards something it stops being a place and becomes a task.
  ///
  /// A map gets exactly one gather-here glow — two are two places to stand,
  /// which is the opposite of what one is for.
  static const double discoGlowRadius = 74;

  /// Where the deck rail runs along the front of the boardwalk.
  static const double railY = 176;

  /// How far apart the rail posts stand, in world units.
  ///
  /// Wide. The posts are the only solid part of the rail — the rail itself is
  /// drawn and walked through, because a solid line across the full width of
  /// the map would turn two bands into two rooms.
  static const double railPostSpacing = 150;

  /// How thick a rail post is, in world units.
  static const double railPostRadius = 7;

  /// The rail posts, spaced across the map.
  static const List<CircleObstacle> railPosts = [
    CircleObstacle(90, railY, railPostRadius),
    CircleObstacle(240, railY, railPostRadius),
    CircleObstacle(390, railY, railPostRadius),
    CircleObstacle(540, railY, railPostRadius),
    CircleObstacle(690, railY, railPostRadius),
    CircleObstacle(840, railY, railPostRadius),
    CircleObstacle(990, railY, railPostRadius),
    CircleObstacle(1140, railY, railPostRadius),
  ];

  // ---- Sand (middle band) -------------------------------------------------

  /// How thick an umbrella pole is, in world units.
  ///
  /// The **pole** is the obstacle; the canopy is drawn far wider and blocks
  /// nothing, exactly like the food court's awning. Collidable shade is the
  /// classic invisible wall, and the one a player will never guess at.
  static const double umbrellaPoleRadius = 9;

  /// How wide an umbrella canopy is drawn, in world units.
  static const double umbrellaRadius = 52;

  /// The umbrella poles.
  ///
  /// Kept well clear of the spawn ring at (600, 310) — see the test that says
  /// so. Materialising inside a pole is a bad first second.
  static const List<CircleObstacle> umbrellas = [
    CircleObstacle(330, 250, umbrellaPoleRadius),
    CircleObstacle(330, 386, umbrellaPoleRadius),
    CircleObstacle(960, 248, umbrellaPoleRadius),
    CircleObstacle(1078, 380, umbrellaPoleRadius),
  ];

  /// The towels laid out on the sand.
  ///
  /// Drawn and **not** collided: a towel is a thing you walk onto. It is also
  /// the cheapest possible gathering cue — a rectangle that says somebody
  /// sits here.
  static const List<WorldRect> towels = [
    WorldRect(392, 232, 470, 288),
    WorldRect(392, 356, 470, 412),
    WorldRect(1000, 236, 1078, 292),
    WorldRect(880, 372, 958, 428),
  ];

  // ---- The secret ---------------------------------------------------------

  /// The big surfboard, stood upright in the sand at the far east end.
  ///
  /// Deliberately at the opposite end of the map from [hintBeanX]: the hint
  /// and the thing it hints at have to be a walk apart, or finding it is
  /// reading a sign rather than exploring. Deliberately **not** an obstacle —
  /// it is a prop you tap, and a solid one would be a wall across the only
  /// dry band.
  ///
  /// No proximity rule guards the tap and none is needed. The camera shows
  /// roughly 244x527 world units at zoom 1.6 on a 1200-wide map, so a player
  /// who can see this rectangle has already walked to it.
  static const WorldRect bigBoard = WorldRect(1096, 214, 1146, 350);

  /// Where the hint bean stands, in world units.
  ///
  /// Far west, on the sand, clear of the volleyball posts at x=180 and a long
  /// way from the spawn ring at (600, 310).
  static const double hintBeanX = 76;

  /// Where the hint bean stands, in world units.
  static const double hintBeanY = 306;

  /// How big a box around the hint bean counts as tapping it.
  ///
  /// Wider and taller than the bean itself, because the thing a player aims
  /// at is the bean *and* the `!` bobbing over its head, and a thumb on a
  /// phone is bigger than either.
  static const double hintBeanTapWidth = 46;

  /// How big a box around the hint bean counts as tapping it.
  static const double hintBeanTapHeight = 74;

  /// How thick a volleyball post is, in world units.
  static const double netPostRadius = 7;

  /// The two volleyball posts.
  ///
  /// The **posts** are solid; the net between them is drawn and walked
  /// through. A solid net would be a 156-unit wall across the west end of the
  /// only dry band on the map.
  static const List<CircleObstacle> netPosts = [
    CircleObstacle(180, 240, netPostRadius),
    CircleObstacle(180, 396, netPostRadius),
  ];

  // ---- Sea (south band) ---------------------------------------------------
  //
  // Landmarks, all of them drawn only. See the class doc.

  /// The raft moored out in the water.
  ///
  /// Solid ground, not scenery: it is the map's one [dryPlatforms] entry, so
  /// a bean that swims to it climbs on, stands up and walks at full speed
  /// while it is aboard. It is not an obstacle — you never bump into it, you
  /// end up on top of it.
  static const WorldRect raft = WorldRect(540, 500, 700, 590);

  /// The buoy cluster, as centres and radii in world units.
  static const List<({double x, double y, double radius})> buoys = [
    (x: 200, y: 720, radius: 14),
    (x: 252, y: 762, radius: 11),
    (x: 168, y: 784, radius: 12),
  ];

  /// The shallow sandbar: a paler patch you can see the bottom through.
  static const WorldRect sandbar = WorldRect(900, 640, 1140, 742);

  // ---- Collision ----------------------------------------------------------

  /// Everything on the beach a bean cannot walk through.
  ///
  /// Spread from the lists above rather than re-typed, so a prop that moves
  /// on screen moves in the collision map in the same edit.
  static const List<Obstacle> fixedObstacles = [
    ...shacks,
    ...railPosts,
    ...umbrellas,
    ...netPosts,
  ];

  /// The parts of the sea a bean stands on rather than swims in.
  ///
  /// Just the raft. The sandbar is deliberately not here: it is drawn as
  /// something seen *through* the water, and standing on a pale smudge with
  /// no edge would read as the swimming being broken rather than as shallows.
  static const List<WorldRect> dryPlatforms = [raft];

  /// The bulb runs strung over the boardwalk.
  ///
  /// Two, along the front of the shacks, which is where people funnel. The
  /// conference has six because it has six walkways; the beach has one strip
  /// worth lighting and does not pretend otherwise.
  static const List<LightRun> lightRuns = [
    (x1: 60, y1: 30, x2: 590, y2: 30),
    (x1: 610, y1: 30, x2: 1140, y2: 30),
  ];
}

/// The beach's bot roster.
///
/// **Client-side scenery. Nothing here goes on the wire** — see
/// `ConferenceBots`, which this is the beach's half of. Six beans: two on the
/// boardwalk, two on the sand, two in the sea.
abstract final class BeachBots {
  /// The six beans standing around the beach.
  ///
  /// Every one of them is on walkable floor, clear of every obstacle and clear
  /// of the spawn ring at (600, 310) r=80 — asserted in `bot_test.dart`, not
  /// hoped.
  static final List<BotSpec> roster = [
    // ---- Boardwalk: the DJ at the decks, one on the dance floor ---------
    ConferenceBots.idle(
      BeachLayout.djX,
      BeachLayout.djY,
      color: 2,
      name: 'Dhruv on the Decks',
      cosmetic: PlayerCosmetic.headphones,
    ),
    ConferenceBots.patrol(
      const [(x: 740, y: 210), (x: 820, y: 240), (x: 780, y: 200)],
      color: 5,
      name: 'Bhavesh Bassdrop',
      cosmetic: PlayerCosmetic.laserVisor,
    ),

    // ---- Sand: one under an umbrella, one at the net --------------------
    ConferenceBots.idle(
      378,
      250,
      color: 1,
      name: 'Sana Sunscreen',
      cosmetic: PlayerCosmetic.cap,
    ),
    ConferenceBots.idle(
      222,
      318,
      color: 4,
      name: 'Varun Volley',
      cosmetic: PlayerCosmetic.malingaHair,
    ),

    // ---- Sea: one swimming a loop, one standing on the raft -------------
    ConferenceBots.patrol(
      const [
        (x: 300, y: 470),
        (x: 300, y: 640),
        (x: 200, y: 720),
        (x: 160, y: 520),
      ],
      color: 0,
      name: 'Bala Backstroke',
      behaviour: BotBehaviour.swim,
    ),
    ConferenceBots.idle(620, 545, color: 6, name: 'Reema Raftlife'),
  ];
}
