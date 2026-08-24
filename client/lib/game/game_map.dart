import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/bot_brain.dart';
import 'package:client/game/tap_target.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:protocol/protocol.dart';

/// Something a bean cannot walk through.
///
/// Only two shapes, because only two shapes are needed and a third would be a
/// third case in the hot loop. Everything in this world is a block or a post.
@immutable
sealed class Obstacle {
  const Obstacle();

  /// Whether ([x], [y]) is inside this obstacle.
  bool contains(double x, double y);
}

/// A rectangular block: the stage, a seat row, a booth, a beach shack.
@immutable
class RectObstacle extends Obstacle {
  /// Creates a rectangular obstacle covering [rect].
  const RectObstacle(this.rect);

  /// The footprint.
  final WorldRect rect;

  @override
  bool contains(double x, double y) => rect.contains(x, y);
}

/// A round post: the credit pillar, a planter, an umbrella pole.
@immutable
class CircleObstacle extends Obstacle {
  /// Creates a round obstacle.
  const CircleObstacle(this.x, this.y, this.radius);

  /// Centre x, in world units.
  final double x;

  /// Centre y, in world units.
  final double y;

  /// Radius, in world units.
  final double radius;

  @override
  bool contains(double px, double py) {
    final dx = px - x;
    final dy = py - y;
    return dx * dx + dy * dy < radius * radius;
  }
}

/// One run of strung bulbs, as two points in world units.
typedef LightRun = ({double x1, double y1, double x2, double y2});

/// The one warm patch of floor a map invites people to stand on.
typedef GlowSpot = ({double x, double y, double radius, WorldZone zone});

/// Where a map's hint bean stands, if it has one.
typedef HintBeanSpot = ({double x, double y});

/// One place to be, as the client sees it: the map plus everything drawn on
/// it and everything a bean bumps into.
///
/// Before Phase 10 this was `WorldLayout`, a wall of `static const` referenced
/// about fifty-five times across nine files. Everything reached for the world
/// directly, which was fine while there was exactly one. A second place turns
/// every one of those references into a bug, so the world became a **value**
/// that components are handed in their constructor.
///
/// One object owns both the art and the collision because they must agree. A
/// stage drawn three metres wider than the block it collides with is the bug
/// you only find by walking into it, and it is found by a player, not by you.
///
/// Everything here is a **rectangle or a circle in code**, not an image. Every
/// asset added to this app costs cold-load time on conference wifi, and a
/// whole map is a few hundred bytes of coordinates that stay crisp at any zoom
/// and recolour for free.
abstract class GameMap {
  /// Creates a map.
  const GameMap();

  /// The geometry both ends agree on: size, spawn, zones.
  MapSpec get spec;

  /// The booths standing in this world. Empty on a map that has none.
  List<Sponsor> get sponsors;

  /// Everything a bean cannot walk through, booths included.
  List<Obstacle> get obstacles;

  /// The swimmable regions of this map.
  ///
  /// A **list**, not one rectangle, which is the entire difference between the
  /// conference's pool and the beach's sea. `SwimState`, `WaterWatcher` and
  /// `SplashField` all derive everything from one boolean per bean per frame
  /// — "is this position in water" — so pointing that boolean at a list
  /// instead of a single rect is the whole of what swimming in the sea cost.
  ///
  /// And it still costs the protocol nothing: every client runs this same
  /// code over positions it already receives, so no new field, no version
  /// bump, no extra bytes. That is the relay decision paying its dividend a
  /// second time.
  List<WorldRect> get waterRegions;

  /// The solid decks that sit *inside* [waterRegions].
  ///
  /// A raft is drawn floating on the sea and a bean standing on one is
  /// standing on timber, not treading water. There is still no z axis: a
  /// platform is not a height, it is a hole punched in the water test, so a
  /// bean walks onto it at full speed, stops swimming, and stops dropping
  /// wakes — and swims again the moment it steps off the far side.
  ///
  /// Empty on a map whose water has nothing in it. Anything listed here must
  /// be drawn *above* the live water, or a bean will appear to stand on the
  /// surface of the sea.
  List<WorldRect> get dryPlatforms => const [];

  /// The ground that shows through where this map has no floor.
  ///
  /// The conference is a cross with two empty corners; the beach is a solid
  /// rectangle and has none.
  List<Rect> get voids;

  /// The bulb runs strung over this map's walkways.
  List<LightRun> get lightRuns;

  /// Where this map's gather-here glow sits.
  ///
  /// Exactly one per map, and never absent. Two gather-here glows would be
  /// two places to stand, which is the opposite of what one is for; none at
  /// all would leave a map with nowhere it quietly suggests you go.
  GlowSpot get crowdGlow;

  /// How much of its walking speed a bean keeps while in the water.
  ///
  /// Slow enough to feel like water, fast enough that nobody is ever
  /// stranded.
  double get swimSpeedFactor;

  /// How much of its walking speed a bean keeps while *surfing* here, or
  /// `null` if this map has no surfing at all.
  ///
  /// A nullable double rather than an `allowsSurfing` bool beside a speed,
  /// and the reason is the failure mode of the alternative: two fields can
  /// disagree, and a map that claims surfing is allowed at a speed of `null`
  /// is a crash waiting for the first person who walks into the pool with a
  /// board. One field cannot contradict itself.
  ///
  /// This is the single statement of "the board is a beach thing". The speed
  /// pick in `ConferenceGame.update` asks it, and `BeanComponent` asks it
  /// before drawing a board under *any* bean, local or remote. Same trick as
  /// `WaterWatcher.wakeInterval`, where an infinite interval is how the flat
  /// LOD tier says "no wakes" without a second flag beside it.
  double? get surfSpeedFactor => null;

  /// Whether this map has a dance floor with a disco over it.
  ///
  /// A bool rather than a list of components, because a `GameMap` is a value
  /// and knows nothing about Flame — the same reason [bots] is a list of specs
  /// and not a list of components. Only the beach has a pub.
  bool get hasDisco => false;

  /// The beans standing around this map who are not people.
  ///
  /// **Client-side scenery, and nothing else.** Every client builds these from
  /// the same constants, exactly the way it builds the furniture — no session,
  /// no registry, no bytes on the wire, and the server is never told they
  /// exist. See `BotSpec`.
  ///
  /// They are deliberately kept out of the head count and out of the crowd
  /// glow's census: a badge reading "12 online" when eleven of them are
  /// painted is worse than a badge reading "1". They *are* counted as
  /// swimmers, because that is a rendering input — a splash is a picture, not
  /// a claim about attendance.
  List<BotSpec> get bots => const [];

  /// The lines this map's screen cycles through, or empty if it has no
  /// screen.
  ///
  /// Only the conference has a stage. Empty here is the whole of "there is
  /// nothing on this map to say it on" — the same shape as [hintBean] being
  /// `null` and [surfSpeedFactor] being `null`, and for the same reason: one
  /// field that cannot contradict itself beats a flag beside a value.
  List<String> get stageLines => const [];

  /// Whether this map has a screen on a stage at all.
  ///
  /// Asked instead of `stageLines.isNotEmpty`, because the lines are config
  /// and config changes while the game is running: a hall whose programme
  /// happened to be empty when somebody walked in still has a screen on its
  /// back wall, and it has to be there to light up when a programme arrives.
  bool get hasStageScreen => false;

  /// Takes the parts of [config] this map paints.
  ///
  /// The default is to take none of them, which is the honest answer for a
  /// map with no projector and no stage.
  ///
  /// This is the one place a `GameMap` is allowed to change after it is
  /// built, and it is deliberate: the alternative is rebuilding the map when
  /// a moderator edits a line, and rebuilding the map means rebuilding the
  /// collision, the floor, the water and the camera — which is the world
  /// blinking out from under somebody mid-conversation over one typo.
  void applyConfig(AppConfig config) {}

  /// Where this map's hint bean stands, or `null` if it has none.
  ///
  /// Client-side scenery with nothing behind it: no player, no session, no
  /// bytes on the wire. Only the beach has one.
  HintBeanSpot? get hintBean => null;

  /// The things on this map a tap can land on.
  ///
  /// Empty on a map with no secret in it, which is the conference. Short by
  /// design — the tap path is a linear scan, and it is a linear scan because
  /// two entries do not deserve a spatial index.
  List<TapTarget> get tapTargets => const [];

  /// Whether ([x], [y]) is in the water.
  ///
  /// A dry platform wins over the water under it — see [dryPlatforms].
  bool isWater(double x, double y) {
    for (final platform in dryPlatforms) {
      if (platform.contains(x, y)) return false;
    }
    for (final region in waterRegions) {
      if (region.contains(x, y)) return true;
    }
    return false;
  }

  /// The speed multiplier that applies at ([x], [y]).
  double speedFactorAt(double x, double y) =>
      isWater(x, y) ? swimSpeedFactor : 1;

  /// The booth nearest to ([x], [y]) within [radius], or `null`.
  ///
  /// Nearest wins rather than first-found: booths sit close enough together
  /// that two radii overlap in the aisle, and "whichever one happens to be
  /// earlier in the JSON" is not an answer a player can predict.
  Sponsor? nearestSponsor(double x, double y, double radius) {
    Sponsor? best;
    var bestDistance = radius * radius;
    for (final sponsor in sponsors) {
      final distance = sponsor.distanceSquaredTo(x, y);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = sponsor;
      }
    }
    return best;
  }

  /// Draws one zone's floor texture into [rect], inside an existing clip.
  ///
  /// Called once, at record time, into the floor's [Picture] — never per
  /// frame.
  void paintZoneFloor(Canvas canvas, WorldZone zone, Rect rect);

  /// Draws everything standing on the floor, once, into the recording canvas.
  ///
  /// Anything that *moves* — water, splashes, the crowd glow, the string
  /// lights — is deliberately not here. A display list is a recording, and
  /// putting an animation in one freezes its first frame.
  void paintFurniture(Canvas canvas);
}
