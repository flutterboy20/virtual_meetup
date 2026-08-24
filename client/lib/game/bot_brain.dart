import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:protocol/protocol.dart';

/// What one bot does with its time.
enum BotBehaviour {
  /// Stands where it was put, breathing, and never leaves.
  ///
  /// The DJ behind the decks, the bean behind the food counter, the one under
  /// an umbrella. Most of the roster, because a room full of beans all
  /// pacing reads as a fire drill.
  idle,

  /// Walks a loop of waypoints, pausing at each.
  patrol,

  /// Walks a loop that runs in and out of water.
  ///
  /// Identical steering to [patrol] — the difference is entirely in where the
  /// waypoints are. It is its own value because a swimming bot travels at the
  /// map's swim speed, and because "this bot is meant to get wet" is worth
  /// saying out loud next to a list of coordinates.
  swim,
}

/// One bot, as a place on the map and a job.
///
/// Client-side scenery, exactly like `HintBeanComponent` and exactly like
/// every prop on both maps: every client draws the same bots in the same
/// places from these same constants, and **the server is never told they
/// exist**. Not one byte, not one message type.
typedef BotSpec = ({
  /// Where it starts, and where an [BotBehaviour.idle] bot stays.
  double x,
  double y,

  /// The name over its head.
  ///
  /// Bots used to have none, on the theory that a named bean standing still
  /// is somebody AFK. The names are what *fixed* that: they appear only when
  /// you walk up, exactly as a player's does, and none of them says "bot" —
  /// so the room reads as full of people rather than full of props.
  String name,

  /// What it does.
  BotBehaviour behaviour,

  /// The loop it walks, for a patrol or a swim. Empty for an idle bot.
  List<({double x, double y})> waypoints,

  /// The body colour. Pastel by convention, so bots read as scenery.
  int color,

  /// The hat, if any.
  PlayerCosmetic cosmetic,
});

/// The decision-making of one bot: where to head, and when to react.
///
/// **Pure maths.** No Flame component, no `Canvas`, no map, no collision —
/// it is handed a position and answers with a direction, which is what lets
/// the whole behaviour be unit-tested at whatever timestep a test likes
/// without running a game loop. The same trade `BeanAnimation`,
/// `JoystickFade` and `LineCycler` all make.
///
/// There is **no pathfinding**. A waypoint loop steered straight at, with the
/// same collision the player uses doing the stopping. A bot briefly stuck
/// against a stool is a bot leaning on a stool, and a pathfinder would be a
/// graph, a search and a per-frame cost for a bean nobody is watching.
class BotBrain {
  /// Creates a brain for [spec], with [random] deciding the dwell times.
  ///
  /// [random] is injectable so a test can pin the timings. Seeded per bot by
  /// the caller, so two bots on the same waypoint loop do not march in step.
  BotBrain({
    required this.spec,
    required math.Random random,
    this.speed = 46,
    this.arriveRadius = 10,
    this.minDwell = 1.4,
    this.maxDwell = 4.2,
    this.minEmoteGap = 20,
    this.maxEmoteGap = 40,
  }) : // A named parameter cannot be private, so this cannot be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _random = random {
    _dwell = _nextDwell();
    _untilEmote = _nextEmoteGap();
  }

  /// Who this brain belongs to.
  final BotSpec spec;

  /// How fast a bot walks, in world units per second.
  ///
  /// A third of `ConferenceGame.beanMaxSpeed`. A bot moving at a player's top
  /// speed reads as another player, and a bot that reads as another player is
  /// a bot somebody will try to talk to.
  final double speed;

  /// How close counts as having arrived at a waypoint, in world units.
  final double arriveRadius;

  /// The shortest pause at a waypoint, in seconds.
  final double minDwell;

  /// The longest pause at a waypoint, in seconds.
  final double maxDwell;

  /// The shortest gap between two of this bot's reactions, in seconds.
  final double minEmoteGap;

  /// The longest gap between two of this bot's reactions, in seconds.
  final double maxEmoteGap;

  final math.Random _random;

  int _target = 0;
  double _dwell = 0;
  double _untilEmote = 0;

  /// Which waypoint this bot is heading for.
  int get targetIndex => _target;

  /// Whether the bot is standing still at a waypoint right now.
  bool get isDwelling => _dwell > 0;

  /// The waypoint this bot is heading for, or `null` if it has none.
  ({double x, double y})? get target {
    if (spec.behaviour == BotBehaviour.idle || spec.waypoints.isEmpty) {
      return null;
    }
    return spec.waypoints[_target % spec.waypoints.length];
  }

  /// Advances the brain by [dt] and returns the velocity to walk at.
  ///
  /// Writes into [out] rather than allocating, because this runs per bot per
  /// frame and a `Vector2` per bot per frame is the cheapest possible way to
  /// hand the garbage collector work it did not need.
  void steer(double dt, Vector2 from, Vector2 out) {
    out.setZero();
    final to = target;
    if (to == null) return;

    if (_dwell > 0) {
      _dwell -= dt;
      return;
    }

    final dx = to.x - from.x;
    final dy = to.y - from.y;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance <= arriveRadius) {
      // Arrived: pause, then head for the next one. Wrapping here rather than
      // reversing is what makes the loop a *loop* — a bot that ping-ponged
      // would walk the same aisle back and forth forever.
      _target = (_target + 1) % spec.waypoints.length;
      _dwell = _nextDwell();
      return;
    }

    out.setValues(dx / distance * speed, dy / distance * speed);
  }

  /// Whether this bot should throw a reaction on this frame.
  ///
  /// One every 20–40 s. It is the difference between a room with scenery in it
  /// and a room with people in it, and it costs one enum pick on a timer.
  bool shouldEmote(double dt) {
    _untilEmote -= dt;
    if (_untilEmote > 0) return false;
    _untilEmote = _nextEmoteGap();
    return true;
  }

  /// Picks a reaction to throw.
  EmoteKind pickEmote() =>
      EmoteKind.values[_random.nextInt(EmoteKind.values.length)];

  double _nextDwell() =>
      minDwell + _random.nextDouble() * (maxDwell - minDwell);

  double _nextEmoteGap() =>
      minEmoteGap + _random.nextDouble() * (maxEmoteGap - minEmoteGap);
}
