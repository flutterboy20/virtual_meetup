import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/beach_floor_art.dart';
import 'package:client/game/beach_layout.dart';
import 'package:client/game/beach_props.dart';
import 'package:client/game/bot_brain.dart';
import 'package:client/game/tap_target.dart';
import 'package:client/game/world_layout.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:protocol/protocol.dart';

/// The beach: a boardwalk, a band of sand, and a swimmable sea.
///
/// The second place to be, and the proof that Phase 10's refactor was right:
/// a different size, a different palette, different art and a sea 13.8x the
/// pool cost this class and three files of coordinates, and changed nothing
/// about the game, the collision, the camera, the minimap or the wire.
///
/// Two things it deliberately does not have:
///
/// - **No booths.** `sponsors` is `const []`, not a feature switched off.
///   Beach sponsorship is not a thing this event has, and a per-map sponsor
///   config would be a knob nobody would ever turn.
/// - **No voids.** The conference is a cross inside a rectangle with two
///   corners left empty; the beach's three bands tile their whole box, so
///   there is no exterior ground to draw.
@immutable
class BeachMap extends GameMap {
  /// Creates the beach.
  ///
  /// No parameters: unlike the conference, nothing here comes from config.
  const BeachMap();

  @override
  MapSpec get spec => MapSpec.beach;

  /// No booths on the beach.
  @override
  List<Sponsor> get sponsors => const [];

  @override
  List<Obstacle> get obstacles => BeachLayout.fixedObstacles;

  /// The sea: one rectangle covering 53% of the map.
  ///
  /// The whole band, not the band minus the sandbar. The sandbar is drawn as
  /// something seen *through* the water rather than as dry land, so it needs
  /// no hole in this list — and a hole would mean four water rects with four
  /// rims, which would read as four swimming pools rather than as one sea.
  @override
  List<WorldRect> get waterRegions => const [BeachLayout.sea];

  /// The raft: sea to swim in, timber to stand on.
  ///
  /// The sea rect still covers it — the water is drawn under the raft, which
  /// is what a moored raft looks like — and this list is what stops the bean
  /// standing on it from swimming through the deck.
  @override
  List<WorldRect> get dryPlatforms => BeachLayout.dryPlatforms;

  /// The same swim speed as the pool.
  ///
  /// Deliberately not slower for being open water. The sea is 480 units deep,
  /// so at 0.55 the far side is about six seconds away — slow enough to feel
  /// like water and fast enough that nobody is ever stranded, which is the
  /// same trade the pool made at a fifth of the distance.
  @override
  double get swimSpeedFactor => 0.55;

  /// Surfing happens here, and only here.
  ///
  /// 0.9 rather than 1.0: a board should be quick, not a teleporter across a
  /// 480-unit sea. At this speed the far side is about 3.7 seconds away
  /// against swimming's 6.2, which is a real difference to feel without
  /// making the swim look broken to everybody who has not found the board.
  @override
  double? get surfSpeedFactor => 0.9;

  /// The bean who knows about the board, at the far west end of the sand.
  @override
  HintBeanSpot get hintBean => (
    x: BeachLayout.hintBeanX,
    y: BeachLayout.hintBeanY,
  );

  /// Two: the board and the bean who hints at it.
  ///
  /// Written out as a `const` list rather than built per call, because this
  /// is read on every tap and a fresh list per tap would be an allocation on
  /// an input path for no reason at all.
  @override
  List<TapTarget> get tapTargets => _tapTargets;

  static const List<TapTarget> _tapTargets = [
    TapTarget(TapTargetId.board, BeachLayout.bigBoard),
    TapTarget(
      TapTargetId.hint,
      WorldRect(
        BeachLayout.hintBeanX - BeachLayout.hintBeanTapWidth / 2,
        BeachLayout.hintBeanY - BeachLayout.hintBeanTapHeight,
        BeachLayout.hintBeanX + BeachLayout.hintBeanTapWidth / 2,
        BeachLayout.hintBeanY + 6,
      ),
    ),
  ];

  /// The pub's disco, over the dance floor. The one on either map.
  @override
  bool get hasDisco => true;

  /// The six beans standing around the beach who are not people.
  ///
  /// Client-side scenery: see `BeachBots`. The DJ is one of them rather than
  /// a special case built into the pub, because two things that should be one
  /// drift apart.
  @override
  List<BotSpec> get bots => BeachBots.roster;

  /// Nothing. The three bands tile the whole bounding box.
  @override
  List<Rect> get voids => const [];

  @override
  List<LightRun> get lightRuns => BeachLayout.lightRuns;

  /// The dance floor outside the pub, which is this map's food court.
  ///
  /// One glow per map: two would be two places to stand, which is the
  /// opposite of what one is for.
  @override
  GlowSpot get crowdGlow => (
    x: BeachLayout.danceFloor.centerX,
    y: BeachLayout.danceFloor.centerY,
    radius: BeachLayout.discoGlowRadius,
    zone: WorldZone.beachSand,
  );

  @override
  void paintZoneFloor(Canvas canvas, WorldZone zone, Rect rect) =>
      BeachFloorArt.paint(canvas, zone, rect);

  @override
  void paintFurniture(Canvas canvas) => BeachProps.paintAll(canvas);
}

/// The map for [id], with [sponsors] placed if it has booths.
///
/// The one place in the client that turns a [MapId] into a world. Everything
/// else takes a [GameMap] and never asks which one it has, which is what lets
/// the whole game run either venue without a branch in it.
///
/// [boardMessage] goes the same way the booths do: it is config, it is read
/// before the game is built, and only one of the two maps has anywhere to put
/// it. The beach has no Code Lab, so it drops the line rather than finding
/// somewhere to paint it.
GameMap gameMapFor(
  MapId id, {
  List<Sponsor> sponsors = const [],
  String boardMessage = AppConfig.defaultBoardMessage,
  List<String> stageLines = AppConfig.defaultStageLines,
}) => switch (id) {
  MapId.conference => ConferenceMap(sponsors, boardMessage, stageLines),
  // The booths are dropped rather than misplaced: a sponsor footprint is
  // a coordinate in the conference's space, and putting one on the beach
  // would drop a booth in the sea.
  MapId.beach => const BeachMap(),
};
