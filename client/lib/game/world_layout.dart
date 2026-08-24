import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/bot_brain.dart';
import 'package:client/game/game_map.dart';
import 'package:client/game/zone_floor_art.dart';
import 'package:client/game/zone_props.dart';
import 'package:protocol/protocol.dart';

export 'package:client/game/game_map.dart'
    show
        CircleObstacle,
        GameMap,
        GlowSpot,
        HintBeanSpot,
        LightRun,
        Obstacle,
        RectObstacle;

/// Every fixed thing in the world: what is drawn, and what blocks a bean.
///
/// One object owns both because they must agree. A stage that is drawn three
/// metres wider than the block it collides with is the bug you only find by
/// walking into it, and it is found by a player, not by you.
///
/// Everything here is a **rectangle or a circle in code**, not an image.
/// Every asset added to this app costs cold-load time on conference wifi, and
/// this whole world is a few hundred bytes of coordinates that stay crisp at
/// any zoom and recolour for free.
///
/// **This class is the conference's coordinate table, not the map object.**
/// Phase 10 turned "the world" into a value — see [GameMap] — and the thing
/// components are handed is [ConferenceMap] below. Everything here stayed a
/// `static const` on purpose, because these numbers are what the conference's
/// art is written against: `ZoneProps` and `ZoneFloorArt` name them a few
/// dozen times, and turning `WorldLayout.stage` into an instance field would
/// have rewritten a thousand lines of Phase 9 art to prove a point about a
/// second map that does not have a stage.
abstract final class WorldLayout {
  /// Builds the conference map, placing a booth for each of [sponsors].
  ///
  /// The booths are the only part of the world that comes from config, which
  /// is why this is a factory rather than a pile of constants: the fixed
  /// furniture is the venue, and the booths are the tenants.
  static ConferenceMap of(
    List<Sponsor> sponsors, {
    String boardMessage = AppConfig.defaultBoardMessage,
    List<String> stageLines = AppConfig.defaultStageLines,
  }) => ConferenceMap(sponsors, boardMessage, stageLines);

  // ---- Conference hall (north arm) ----------------------------------------

  /// The stage everybody faces.
  static const WorldRect stage = WorldRect(650, 40, 950, 150);

  /// The screen behind the stage.
  static const WorldRect stageScreen = WorldRect(686, 54, 914, 122);

  /// The seat rows, front to back.
  ///
  /// Split down the middle, because a solid 300-unit bench with no aisle is
  /// the one piece of furniture guaranteed to trap somebody.
  static const List<RectObstacle> seatRows = [
    RectObstacle(WorldRect(664, 211, 780, 229)),
    RectObstacle(WorldRect(820, 211, 936, 229)),
    RectObstacle(WorldRect(664, 253, 780, 271)),
    RectObstacle(WorldRect(820, 253, 936, 271)),
    RectObstacle(WorldRect(664, 295, 780, 313)),
    RectObstacle(WorldRect(820, 295, 936, 313)),
  ];

  // ---- Lounge & pool (south arm) ------------------------------------------

  /// The pool. Swimmable since Phase 9.
  ///
  /// It is deliberately **not** in [fixedObstacles] any more. It is a water
  /// *region*: walkable, but movement through it is multiplied by
  /// [swimSpeedFactor], and a bean inside it is drawn half-submerged.
  ///
  /// The thing worth understanding here is that swimming costs the protocol
  /// nothing. Every client runs this same `WorldLayout` code, so every client
  /// can ask [isWater] about every remote bean whose position it already
  /// receives. Diving, swimming and the splash are all *derived* from the
  /// position stream — no new field on `PlayerPosition`, no protocol version
  /// bump, no extra bytes on the wire, and the server learns nothing. That is
  /// the relay decision paying a concrete dividend.
  static const WorldRect pool = WorldRect(690, 900, 910, 1090);

  /// How much of its walking speed a bean keeps while in the water.
  ///
  /// Slow enough to feel like water, fast enough that nobody is ever stranded
  /// — the pool is 220 units across, so the far wall is under three seconds
  /// away even at this pace.
  static const double swimSpeedFactor = 0.55;

  /// Whether ([x], [y]) is in the water.
  static bool isWater(double x, double y) => pool.contains(x, y);

  /// The speed multiplier that applies at ([x], [y]).
  static double speedFactorAt(double x, double y) =>
      isWater(x, y) ? swimSpeedFactor : 1;

  /// Loungers along the top of the lounge, with a gap to walk through.
  static const List<RectObstacle> loungers = [
    RectObstacle(WorldRect(640, 836, 686, 864)),
    RectObstacle(WorldRect(706, 836, 752, 864)),
    RectObstacle(WorldRect(848, 836, 894, 864)),
    RectObstacle(WorldRect(914, 836, 960, 864)),
  ];

  // ---- Food Court (west arm) ----------------------------------------------
  //
  // Phase 12 rebuilt this room as a food court: three stall bays, menu
  // boards, trays and plates instead of one urn and a row of glasses. **Every
  // rectangle below kept its coordinates**, and the Phase 9 layout tests
  // passing unmodified is the review of that rename.

  /// The counter people queue at.
  ///
  /// Replaced the photo backdrop in Phase 9. A counter is a better gathering
  /// object than a wall for the same reason a kitchen is: a wall is something
  /// you stand in front of and then leave, and a counter is something you
  /// stand *around*.
  static const WorldRect foodCounter = WorldRect(58, 470, 132, 706);

  /// The middle of the three stall bays, in world units.
  ///
  /// Drawn but not collided: the bays stand on the counter, which is already
  /// solid, and a second obstacle inside the first is a second thing to keep
  /// in sync. Was the tea urn before Phase 12, at the same spot.
  static const double tawaX = 95;

  /// The middle of the three stall bays, in world units.
  static const double tawaY = 512;

  /// How wide one stall bay's hotplate is, in world units.
  static const double tawaRadius = 18;

  /// How far apart the three bays sit down the counter, in world units.
  static const double bayPitch = 74;

  /// The awning over the stalls.
  ///
  /// Drawn only — you walk *under* an awning. Collidable shade is the classic
  /// invisible wall, and the one a player will never guess at.
  static const WorldRect courtAwning = WorldRect(44, 448, 200, 728);

  /// The samosa cart.
  static const WorldRect snackCart = WorldRect(292, 452, 404, 502);

  /// Stools along the counter, with gaps wide enough to walk between.
  static const List<CircleObstacle> courtStools = [
    CircleObstacle(178, 512, 15),
    CircleObstacle(178, 566, 15),
    CircleObstacle(178, 620, 15),
    CircleObstacle(178, 674, 15),
  ];

  /// Planters framing the walk in from the atrium.
  static const List<CircleObstacle> planters = [
    CircleObstacle(470, 466, 26),
    CircleObstacle(470, 734, 26),
  ];

  /// Where the counter's crowd glow sits, in world units.
  static const double courtGlowX = 268;

  /// Where the counter's crowd glow sits, in world units.
  static const double courtGlowY = 600;

  /// How big the crowd glow is, in world units.
  static const double courtGlowRadius = 68;

  // ---- Code Lab (north-east) ----------------------------------------------

  /// The projector screen at the front of the lab.
  static const WorldRect labScreen = WorldRect(1150, 44, 1382, 96);

  /// The whiteboard next to it.
  static const WorldRect whiteboard = WorldRect(1414, 44, 1552, 96);

  /// The desk rows, front to back.
  ///
  /// Split down the middle, exactly like the hall's seating and for exactly
  /// the same reason: a solid 480-unit bench with no aisle is the one prop
  /// guaranteed to trap somebody, and this room has three of them.
  static const List<RectObstacle> labDesks = [
    RectObstacle(WorldRect(1052, 160, 1252, 198)),
    RectObstacle(WorldRect(1332, 160, 1532, 198)),
    RectObstacle(WorldRect(1052, 244, 1252, 282)),
    RectObstacle(WorldRect(1332, 244, 1532, 282)),
    RectObstacle(WorldRect(1052, 328, 1252, 366)),
    RectObstacle(WorldRect(1332, 328, 1532, 366)),
  ];

  /// Where the aisle between the desk banks runs, in world units.
  static const double labAisleX = 1292;

  // ---- Garden Deck (south-west) -------------------------------------------

  /// The stepped viewing deck that looks out over the pool.
  ///
  /// **This is fake depth, on purpose.** There is no z axis anywhere in this
  /// world — no height on the wire, no per-frame draw-order sort, no per-floor
  /// collision. The treads and the shadow gradient are painted on flat ground,
  /// and the whole thing is **walkable and level underneath**: it is not in
  /// [fixedObstacles] and it changes nothing about movement.
  ///
  /// It is written down here so that nobody later reads it as a broken
  /// elevation system and "fixes" it. Real multi-level is a phase of its own,
  /// and it would undo the no-y-sorting decision this renderer is built on.
  static const WorldRect gardenDeck = WorldRect(400, 950, 596, 1140);

  /// Where the treads stop and the raised platform begins, in world units.
  static const double deckPlatformX = 470;

  /// How many treads climb up to the platform.
  static const int deckTreads = 4;

  /// The fountain in the middle of the lawn.
  static const CircleObstacle fountain = CircleObstacle(150, 1040, 46);

  /// The trees. Their canopies are drawn far wider than these trunks.
  static const List<CircleObstacle> gardenTrees = [
    CircleObstacle(92, 878, 20),
    CircleObstacle(492, 856, 20),
    CircleObstacle(196, 1148, 18),
    CircleObstacle(560, 884, 18),
  ];

  /// The benches: one facing the fountain, one on the walk in.
  static const List<RectObstacle> gardenBenches = [
    RectObstacle(WorldRect(112, 1132, 200, 1154)),
    RectObstacle(WorldRect(360, 862, 448, 884)),
  ];

  // ---- Atrium (centre) ----------------------------------------------------

  /// Where the credit pillar stands, in world units.
  static const double pillarX = spawnCenterX;

  /// Where the credit pillar stands, in world units.
  static const double pillarY = spawnCenterY;

  /// How thick the credit pillar is, in world units.
  ///
  /// Comfortably smaller than the spawn ring, so nobody ever materialises
  /// inside it.
  static const double pillarRadius = 40;

  /// Everything that blocks a bean and is not a sponsor booth.
  ///
  /// Spread from the lists above rather than re-typed, so a prop that moves
  /// on screen moves in the collision map in the same edit. Furniture drawn
  /// in one place and collided in another is the classic invisible wall.
  ///
  /// The pool is conspicuously **not** in here since Phase 9 — see [pool].
  static const List<Obstacle> fixedObstacles = [
    RectObstacle(stage),
    ...seatRows,
    ...loungers,
    RectObstacle(foodCounter),
    ...courtStools,
    RectObstacle(snackCart),
    ...planters,
    RectObstacle(labScreen),
    RectObstacle(whiteboard),
    ...labDesks,
    fountain,
    ...gardenTrees,
    ...gardenBenches,
    CircleObstacle(pillarX, pillarY, pillarRadius),
  ];

  // ---- Ambience -----------------------------------------------------------

  /// The bulb runs, as start and end points in world units.
  ///
  /// Strung across the four walkways into the atrium and along the two
  /// corner-room seams — which is to say, exactly over the places people
  /// funnel through. Lighting the walkways rather than the rooms is also what
  /// keeps the rooms' own palettes readable.
  ///
  /// A map's property since Phase 10 rather than the light component's, for
  /// the obvious reason: a run of bulbs strung over the atrium would be
  /// hanging in mid-air over the sea.
  static const List<LightRun> lightRuns = [
    (x1: 610, y1: 400, x2: 990, y2: 400),
    (x1: 610, y1: 800, x2: 990, y2: 800),
    (x1: 600, y1: 410, x2: 600, y2: 790),
    (x1: 1000, y1: 410, x2: 1000, y2: 790),
    (x1: 1010, y1: 400, x2: 1560, y2: 400),
    (x1: 40, y1: 800, x2: 590, y2: 800),
  ];
}

/// The conference venue, as the one object every component is handed.
///
/// A thin shell over [WorldLayout] rather than a copy of it. The Phase 9
/// content moved here **by reference, not by value**: every rectangle, every
/// prop and every colour is still the constant it was, and the Phase 9 tests
/// pass unmodified, which is the whole review of the refactor.
///
/// Everything about it is fixed except the two sentences config owns — see
/// [applyConfig].
class ConferenceMap extends GameMap {
  /// Creates the venue with a booth for each of [sponsors].
  ///
  /// [boardMessage] is the second positional rather than a named parameter
  /// because [sponsors] is already an optional positional, and Dart will not
  /// let one constructor have both.
  ConferenceMap([
    List<Sponsor> sponsors = const [],
    String boardMessage = AppConfig.defaultBoardMessage,
    List<String> stageLines = AppConfig.defaultStageLines,
  ]) : _boardMessage = boardMessage,
       _stageLines = List.unmodifiable(stageLines),
       sponsors = List.unmodifiable(sponsors),
       obstacles = List.unmodifiable([
         ...WorldLayout.fixedObstacles,
         for (final sponsor in sponsors) RectObstacle(sponsor.footprint),
       ]);

  /// The venue with no booths in it.
  ///
  /// The default for anything that needs *a* map before config has been read
  /// — a component built in a test, a floor drawn before the sponsor list
  /// arrives. Shared rather than rebuilt, because building one walks the
  /// whole obstacle list.
  static final ConferenceMap empty = ConferenceMap();

  @override
  MapSpec get spec => MapSpec.conference;

  /// The beans standing around this venue who are not people.
  ///
  /// Client-side scenery: see [ConferenceBots]. They are drawn, they walk and
  /// they react, and the server is never told any of it.
  ///
  /// The venue's own crowd first, then one bean behind each booth. The order
  /// matters: turning the crowd down keeps the front of this list, and the
  /// room everybody spawns in is worth more than the garden.
  @override
  List<BotSpec> get bots => _bots;

  late final List<BotSpec> _bots = List.unmodifiable([
    ...ConferenceBots.roster,
    ...ConferenceBots.boothStaff(sponsors),
  ]);

  /// What the hall's screen says, from config.
  ///
  /// Unlike [boardMessage] this is **not** painted into the furniture: it
  /// changes every six seconds, and a display list is a recording. It is
  /// handed to `StageScreenComponent`, which is a live component.
  @override
  List<String> get stageLines => _stageLines;

  @override
  bool get hasStageScreen => true;

  /// The line painted on the Code Lab's projector screen.
  ///
  /// It comes from `AppConfig`, and it *is* inside the static furniture
  /// picture: no component, no per-frame text layout. That is why changing it
  /// is [applyConfig]'s business rather than a plain field write — the words
  /// are in a recording, and a recording has to be made again.
  String get boardMessage => _boardMessage;

  String _boardMessage;
  List<String> _stageLines;

  /// Takes the projector's line and the stage's programme from [config].
  ///
  /// Whoever calls this owns re-recording the furniture afterwards; this
  /// object has no idea a `Picture` exists. See `ConferenceGame.applyConfig`.
  @override
  void applyConfig(AppConfig config) {
    _boardMessage = config.boardMessage;
    _stageLines = List.unmodifiable(config.stageLines);
  }

  @override
  final List<Sponsor> sponsors;

  @override
  final List<Obstacle> obstacles;

  /// The pool, and nothing else.
  ///
  /// A one-element list where the beach has one covering half its map. That
  /// difference is the entire cost of making the sea swimmable.
  @override
  List<WorldRect> get waterRegions => const [WorldLayout.pool];

  @override
  double get swimSpeedFactor => WorldLayout.swimSpeedFactor;

  @override
  List<Rect> get voids => ZoneFloorArt.voids;

  @override
  List<LightRun> get lightRuns => WorldLayout.lightRuns;

  @override
  GlowSpot get crowdGlow => (
    x: WorldLayout.courtGlowX,
    y: WorldLayout.courtGlowY,
    radius: WorldLayout.courtGlowRadius,
    zone: WorldZone.foodCourt,
  );

  @override
  void paintZoneFloor(Canvas canvas, WorldZone zone, Rect rect) =>
      ZoneFloorArt.paint(canvas, zone, rect);

  @override
  void paintFurniture(Canvas canvas) {
    ZoneProps.paintHall(canvas);
    ZoneProps.paintLounge(canvas);
    ZoneProps.paintFoodCourt(canvas);
    ZoneProps.paintCodeLab(canvas, boardMessage);
    ZoneProps.paintGarden(canvas);
    ZoneProps.paintBooths(canvas, sponsors);
    ZoneProps.paintPillar(canvas);
    ZoneProps.paintBanners(canvas);
  }
}

/// The conference's bot roster, and the palette they are drawn in.
///
/// **Client-side scenery. Nothing here goes on the wire.** Every client draws
/// these same twenty-one beans in these same places from these same constants,
/// exactly the way `HintBeanComponent` and every prop on this map already
/// work. The server does not know bots exist and must never be told.
///
/// A separate class from [WorldLayout] only because that one is the *venue's*
/// coordinate table and this is a cast list — the venue does not change when
/// somebody adds a bean to the garden.
abstract final class ConferenceBots {
  /// Pastel bodies, so a bot reads as scenery beside a player's saturated
  /// pick.
  ///
  /// Deliberately not the eight colours the setup screen offers: a bot in a
  /// colour a player can choose is a bot somebody thinks is a person, and a
  /// person who never answers is worse than no person at all.
  static const List<int> palette = [
    0xFFBFD8C9,
    0xFFD8CBBF,
    0xFFC7C9DE,
    0xFFDEC7D2,
    0xFFCFDCC0,
    0xFFC0D6DE,
    0xFFDDD3B4,
  ];

  /// A bot who stands where it is put.
  static BotSpec idle(
    double x,
    double y, {
    required int color,
    required String name,
    PlayerCosmetic cosmetic = PlayerCosmetic.none,
  }) => (
    x: x,
    y: y,
    name: name,
    behaviour: BotBehaviour.idle,
    waypoints: const [],
    color: palette[color % palette.length],
    cosmetic: cosmetic,
  );

  /// A bot who walks [waypoints] in a loop, starting at the first.
  static BotSpec patrol(
    List<({double x, double y})> waypoints, {
    required int color,
    required String name,
    PlayerCosmetic cosmetic = PlayerCosmetic.none,
    BotBehaviour behaviour = BotBehaviour.patrol,
  }) => (
    x: waypoints.first.x,
    y: waypoints.first.y,
    name: name,
    behaviour: behaviour,
    waypoints: waypoints,
    color: palette[color % palette.length],
    cosmetic: cosmetic,
  );

  /// The beans standing around the conference who are not people.
  ///
  /// Every one of them is on walkable floor, clear of every obstacle and clear
  /// of the spawn ring — which is asserted, not hoped, in `bot_test.dart`. An
  /// empty room reads as a broken server long before it reads as an early
  /// arrival, and these are the answer to "is this thing working?" before
  /// anybody has to ask it.
  ///
  /// **The order is a priority order**, because a moderator can turn the crowd
  /// down and a lower count keeps the first N. So the atrium — where everybody
  /// spawns and looks around — comes first, the stage next, and the quiet
  /// corners of the map last. Trimming empties the garden before it empties
  /// the room you arrive in.
  ///
  /// The booths' own staff are **not** here: they are placed from the sponsor
  /// list, which is config. See [boothStaff].
  static final List<BotSpec> roster = [
    // ---- Atrium: two circling the credit pillar -------------------------
    //
    // One loop *inside* the spawn ring and one well outside it. Neither may
    // sit on the ring itself at radius 120 — a bean materialising on top of a
    // bot is somebody's first frame spent inside scenery — which is why the
    // inner loop is at radius 72 (clear of the 40-unit pillar) and the outer
    // one runs the corners of the atrium at radius 226.
    patrol(
      const [
        (x: 872, y: 600),
        (x: 800, y: 672),
        (x: 728, y: 600),
        (x: 800, y: 528),
      ],
      color: 0,
      name: 'Priya Pixelperfect',
      cosmetic: PlayerCosmetic.cap,
    ),
    patrol(
      const [
        (x: 640, y: 440),
        (x: 960, y: 440),
        (x: 960, y: 760),
        (x: 640, y: 760),
      ],
      color: 3,
      name: 'Sam Scrollbar',
      cosmetic: PlayerCosmetic.laserVisor,
    ),

    // ---- Hall: two on the stage, two in the front row -------------------
    //
    // Four, not the seven this used to have. Seven filled every seat in shot,
    // which made the hall read as *finished* rather than as filling up — and
    // left a real attendee walking in with nowhere that looked like it was
    // theirs to stand.
    idle(720, 168, color: 1, name: 'Kavya Keynote'),
    idle(
      876,
      168,
      color: 6,
      name: 'Sanjay Slidedeck',
      cosmetic: PlayerCosmetic.headphones,
    ),
    idle(
      752,
      244,
      color: 5,
      name: 'Rohan Notetaker',
      cosmetic: PlayerCosmetic.cap,
    ),
    idle(
      856,
      244,
      color: 3,
      name: 'Ishita Applause',
      cosmetic: PlayerCosmetic.propellerBeanie,
    ),

    // ---- Food court: one behind the counter, one in the queue -----------
    idle(
      150,
      560,
      color: 3,
      name: 'Vikram Vada',
      cosmetic: PlayerCosmetic.cap,
    ),
    idle(214, 600, color: 5, name: 'Sneha Samosa'),

    // ---- Code Lab: two at the desks --------------------------------------
    idle(
      1150,
      218,
      color: 1,
      name: 'Divya Debugger',
      cosmetic: PlayerCosmetic.propellerBeanie,
    ),
    idle(1430, 302, color: 6, name: 'Sid Stacktrace'),

    // ---- Lounge: one on the deck, one swimming a loop in the pool --------
    idle(
      790,
      812,
      color: 6,
      name: 'Pooja Poolside',
      cosmetic: PlayerCosmetic.headphones,
    ),
    patrol(
      const [
        (x: 800, y: 870),
        (x: 800, y: 1000),
        (x: 870, y: 1050),
        (x: 730, y: 1000),
      ],
      color: 0,
      name: 'Deepak Deepend',
      behaviour: BotBehaviour.swim,
    ),

    // ---- Garden: one at the fountain, one walking ------------------------
    idle(150, 1110, color: 4, name: 'Farhan Fern'),
    patrol(
      const [(x: 300, y: 900), (x: 300, y: 1120), (x: 100, y: 950)],
      color: 2,
      name: 'Bindu Bonsai',
      cosmetic: PlayerCosmetic.malingaHair,
    ),
  ];

  /// The names the booths' staff go by, taken in order and wrapped around.
  ///
  /// A pool rather than a name written beside each sponsor, because sponsors
  /// come from config and config can hold six booths or two. Nobody should
  /// have to name a bean in order to add a booth.
  static const List<String> staffNames = [
    'Bhavya Booth',
    'Sowmya Swag',
    'Dinesh Demo',
    'Lakshmi Lanyard',
    'Sameer Standee',
    'Farida Flyer',
  ];

  /// How far clear of a booth's edge its staff stand, in world units.
  ///
  /// Clear of the footprint, which is an obstacle: a bean placed inside one
  /// would spend the event being shoved back out by the collision resolver.
  static const double staffStandoff = 26;

  /// Where one booth's staff stands.
  ///
  /// Behind the booth if there is room behind it, and off to one side if
  /// there is not — the sponsor row's back wall is only a few units past the
  /// rear booths, and a bean shoved through it would be standing in the void.
  ///
  /// What both answers have in common is the thing that matters: neither of
  /// them is on the booth's **top** edge, which is where the branded band and
  /// the sponsor's name are painted. That edge is the booth's face, and a
  /// bean standing on it is a bean standing in front of the logo.
  static ({double x, double y}) staffPlace(Sponsor sponsor) {
    final behind = sponsor.footprint.bottom + staffStandoff;
    if (MapSpec.conference.isOnFloor(sponsor.x, behind)) {
      return (x: sponsor.x, y: behind);
    }
    return (x: sponsor.footprint.right + staffStandoff, y: sponsor.y);
  }

  /// One bean working each of [sponsors]' booths.
  ///
  /// **Derived from the booth rather than written down beside it.** The old
  /// roster had four staff at fixed coordinates, and they had drifted into a
  /// line of beans standing in an empty aisle nowhere near the booths they
  /// were meant to be working — because the booths moved in config and the
  /// beans could not. A booth that moves now takes its staff with it.
  ///
  /// Where each one ends up is [staffPlace]'s decision.
  static List<BotSpec> boothStaff(List<Sponsor> sponsors) => [
    for (var i = 0; i < sponsors.length; i++)
      idle(
        staffPlace(sponsors[i]).x,
        staffPlace(sponsors[i]).y,
        color: i,
        name: staffNames[i % staffNames.length],
        // Every other one gets a hat, so a row of booths does not read as a
        // row of identical beans.
        cosmetic: i.isEven ? PlayerCosmetic.cap : PlayerCosmetic.none,
      ),
  ];
}
