import 'dart:math' as math;
import 'dart:ui';

import 'package:client/game/bean_animation.dart';
import 'package:client/game/bean_appearance.dart';
import 'package:client/game/bean_component.dart';
import 'package:client/game/bot_brain.dart';
import 'package:client/game/collision.dart';
import 'package:client/game/game_map.dart';
import 'package:flame/components.dart';

/// One of the beans standing around the world who is not a person.
///
/// **Scenery, drawn by every client from the same constants.** No session, no
/// registry, no bytes on the wire, and the server is never told bots exist —
/// exactly the way `HintBeanComponent` works and exactly the way every prop on
/// both maps already works.
///
/// It extends [BeanComponent] rather than reimplementing one, and that is
/// where most of this feature came from for free: the body art, the walk bob,
/// the lean, the contact shadow and — the good one — [BeanComponent.swim].
/// The pool bot dives, surfaces and leaves a waterline because it is a bean
/// standing in water, and `SwimState` works that out from its own position.
///
/// Three rules it does not break:
///
/// - **No nametag.** A named bean that never moves is somebody AFK; an unnamed
///   pastel bean pottering about the garden is a bean pottering about.
/// - **No collision of its own.** Bots are not obstacles. They walk through
///   each other and you walk through them, exactly as players do.
/// - **Camera-culled.** Outside the visible rectangle a bot skips both
///   `update` and `render` — the same trick `WaterComponent` uses to make the
///   sea cost O(screen) instead of O(sea).
class BotComponent extends BeanComponent {
  /// Creates the bot described by [brain], walking on [map].
  BotComponent({
    required this.brain,
    required GameMap map,
    required this.isVisible,
    this.onEmote,
    double maxSpeed = 140,
  }) : collision = WorldCollision(map),
       super(
         position: Vector2(brain.spec.x, brain.spec.y),
         animation: BeanAnimation(maxSpeed: maxSpeed),
         map: map,
         appearance: BeanAppearance(
           bodyColor: Color(brain.spec.color),
           cosmetic: brain.spec.cosmetic,
           cosmeticColor: BeanAppearance.darken(
             Color(brain.spec.color),
             0.34,
           ),
         ),
       );

  /// What this bot is trying to do.
  final BotBrain brain;

  /// The same collision the player walks against.
  ///
  /// Not a softer one, and not none: a bot that strolled through the stage
  /// would say, louder than any tutorial, that the walls here are a suggestion.
  final WorldCollision collision;

  /// Whether this bot is on screen, asked once per frame.
  ///
  /// A callback rather than a rectangle, because the camera moves and this
  /// component must not hold a stale copy of where it was looking.
  final bool Function(double x, double y) isVisible;

  /// Called when the bot throws a reaction, if anybody wants to draw it.
  final void Function(BotComponent bot)? onEmote;

  final Vector2 _wanted = Vector2.zero();
  final Vector2 _from = Vector2.zero();

  @override
  void update(double dt) {
    // Camera culling. A bot the camera cannot see costs one rectangle test
    // per frame and nothing else — no brain, no collision, no animation, no
    // draw. This is what keeps a roster of twenty-one a rounding error.
    if (!isVisible(position.x, position.y)) return;

    brain.steer(dt, position, _wanted);
    if (!_wanted.isZero()) {
      // Water slows a bot down exactly as it slows a player down, from the
      // same map. A swim bot that crossed the pool at walking pace would be
      // the one bean on screen visibly cheating.
      final travel = _wanted * map.speedFactorAt(position.x, position.y);
      _from.setFrom(position);
      final resolved = collision.resolve(
        from: _from,
        to: _from + travel * dt,
      );
      position.setValues(
        map.spec.clampX(resolved.x),
        map.spec.clampY(resolved.y),
      );
      velocity.setFrom(travel);
      // Refused by a wall: drop the velocity on the axis that did not move,
      // or the bot moonwalks on the spot against a stool. Same rule the
      // player's own movement follows.
      if (resolved.x == _from.x) velocity.x = 0;
      if (resolved.y == _from.y) velocity.y = 0;
    } else {
      velocity.setZero();
    }

    if (brain.shouldEmote(dt)) onEmote?.call(this);

    // Deliberately last, and deliberately `super`: the bob, the lean and the
    // submersion all read the velocity this frame just wrote.
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    if (!isVisible(position.x, position.y)) return;
    super.render(canvas);
  }
}

/// Builds the components for [specs] on [map].
///
/// A free function rather than a method on the map, because the map is a
/// value with no idea what a Flame component is — and because the two things
/// a bot needs from outside it (the camera rectangle and somewhere to put a
/// reaction) belong to the game.
List<BotComponent> buildBots({
  required List<BotSpec> specs,
  required GameMap map,
  required bool Function(double x, double y) isVisible,
  void Function(BotComponent bot)? onEmote,
  int seed = 12,
}) => [
  for (var i = 0; i < specs.length; i++)
    BotComponent(
      // Seeded per bot rather than shared, so two bots on the same loop do
      // not pause and set off in lockstep — which reads as a machine, which
      // is the one thing scenery must not read as.
      brain: BotBrain(
        spec: specs[i],
        random: math.Random(seed * 1000 + i),
      ),
      map: map,
      isVisible: isVisible,
      onEmote: onEmote,
    ),
];
