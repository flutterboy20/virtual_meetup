import 'package:client/game/bean_component.dart';
import 'package:client/game/bot_component.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/game/joystick_side.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// A key-down event for [key], as the framework would deliver it.
KeyDownEvent _keyDown(LogicalKeyboardKey key, PhysicalKeyboardKey physical) {
  return KeyDownEvent(
    logicalKey: key,
    physicalKey: physical,
    timeStamp: Duration.zero,
  );
}

/// Runs [steps] frames of the game loop.
void _tick(ConferenceGame game, {int steps = 30, double dt = 1 / 60}) {
  for (var i = 0; i < steps; i++) {
    game.update(dt);
  }
}

void main() {
  group('ConferenceGame', () {
    testWithGame<ConferenceGame>(
      'starts on the atrium spawn ring, clear of the credit pillar',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();

        // Not the exact centre of the world any more: the credit pillar
        // stands there, and forty people spawning inside it would be both
        // invisible and stuck.
        expect(
          WorldZone.at(game.bean.position.x, game.bean.position.y),
          equals(WorldZone.atrium),
        );
        expect(
          game.collision.isFree(game.bean.position.x, game.bean.position.y),
          isTrue,
        );
        expect(game.bean.velocity.isZero(), isTrue);
        // Exactly one bean that is a *person*. Phase 12's bots are
        // `BeanComponent`s too — that is where their body, bob and swimming
        // come from — so the count has to exclude them or it counts scenery.
        expect(
          game.world.children
              .whereType<BeanComponent>()
              .where((bean) => bean is! BotComponent)
              .length,
          1,
        );
      },
    );

    testWithGame<ConferenceGame>(
      'spreads arrivals around the ring rather than stacking them',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();
        final other = ConferenceGame(spawnAngle: 3.14159);
        await other.onLoad();

        expect(game.bean.position.x, isNot(equals(other.bean.position.x)));
      },
    );

    testWithGame<ConferenceGame>(
      'follows the bean at a fixed zoom',
      ConferenceGame.new,
      (game) async {
        await game.ready();

        expect(
          game.camera.viewfinder.zoom,
          closeTo(ConferenceGame.cameraZoom, 1e-6),
        );

        final before = game.camera.viewfinder.position.clone();
        game.onKeyEvent(
          _keyDown(
            LogicalKeyboardKey.arrowRight,
            PhysicalKeyboardKey.arrowRight,
          ),
          {LogicalKeyboardKey.arrowRight},
        );
        _tick(game);

        expect(game.camera.viewfinder.position.x, greaterThan(before.x));
        expect(
          game.camera.viewfinder.zoom,
          closeTo(ConferenceGame.cameraZoom, 1e-6),
        );
      },
    );

    testWithGame<ConferenceGame>(
      'moves the bean while a direction key is held and stops on release',
      ConferenceGame.new,
      (game) async {
        await game.ready();
        final start = game.bean.position.clone();

        game.onKeyEvent(
          _keyDown(LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.keyD),
          {LogicalKeyboardKey.arrowRight},
        );
        _tick(game);

        expect(game.bean.position.x, greaterThan(start.x));
        expect(game.bean.position.y, start.y);
        expect(game.bean.velocity.x, greaterThan(0));

        game.onKeyEvent(
          _keyDown(LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.keyD),
          const {},
        );
        _tick(game, steps: 120);

        expect(game.bean.velocity.length, closeTo(0, 0.01));
      },
    );

    testWithGame<ConferenceGame>(
      'ignores keys it does not use',
      ConferenceGame.new,
      (game) async {
        await game.ready();

        final result = game.onKeyEvent(
          _keyDown(LogicalKeyboardKey.keyQ, PhysicalKeyboardKey.keyQ),
          {LogicalKeyboardKey.keyQ},
        );

        expect(result, KeyEventResult.ignored);
      },
    );

    testWithGame<ConferenceGame>(
      'keeps the bean on the floor, whatever it is walked into',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();

        // Thirty seconds of holding up-and-left from the atrium: through the
        // hall, into the stage, and out at the north-west corner of the map.
        game.onKeyEvent(
          _keyDown(LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.keyA),
          {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowUp},
        );
        _tick(game, steps: 60 * 30);

        expect(
          game.collision.isFree(game.bean.position.x, game.bean.position.y),
          isTrue,
          reason: 'the bean ended up inside a wall or off the map',
        );
      },
    );

    testWithGame<ConferenceGame>(
      'drives the bean animation from its velocity',
      ConferenceGame.new,
      (game) async {
        await game.ready();

        game.onKeyEvent(
          _keyDown(LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.keyA),
          {LogicalKeyboardKey.arrowLeft},
        );
        _tick(game);

        expect(game.bean.animation.facing, -1);
        expect(game.bean.animation.speedRatio, greaterThan(0));
      },
    );

    testWithGame<ConferenceGame>(
      'puts the joystick on the right by default and can move it left',
      ConferenceGame.new,
      (game) async {
        await game.ready();

        expect(game.joystickSide, JoystickSide.right);
        final right = game.joystick.position.x;
        expect(right, greaterThan(game.size.x / 2));

        game.joystickSide = JoystickSide.left;
        await game.ready();

        expect(game.joystick.position.x, lessThan(game.size.x / 2));
      },
    );
  });

  group('ConferenceGame joystick', () {
    testWithGame<ConferenceGame>(
      'draws the ring concentric with the knob it sits under',
      ConferenceGame.new,
      (game) async {
        await game.ready();

        // The regression this pins: Flame re-anchors the *knob* to centre and
        // leaves the background alone, so a centre-anchored `JoystickBase`
        // renders half its width up and to the left of the knob. The control
        // still worked — the touch area is the parent — but the ring was
        // visibly off the thumb, which is what "the joystick is broken" meant.
        final background = game.joystick.background!;
        final knob = game.joystick.knob!;

        expect(
          background.absoluteCenter.x,
          closeTo(knob.absoluteCenter.x, 0.001),
        );
        expect(
          background.absoluteCenter.y,
          closeTo(knob.absoluteCenter.y, 0.001),
        );
        // And both sit at the centre of the control's own box, which is what
        // the drag maths measures the knob's travel from.
        expect(
          background.absoluteCenter.x,
          closeTo(game.joystick.absoluteCenter.x, 0.001),
        );
      },
    );

    // The joystick recomputes its delta from real drag events every frame, so
    // this one goes through a widget test and an actual finger drag.
    testWidgets('drags the bean and never exceeds the top speed', (
      tester,
    ) async {
      final game = ConferenceGame();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameWidget(game: game)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final start = game.bean.position.clone();
      final knob = Offset(game.joystick.position.x, game.joystick.position.y);

      final gesture = await tester.startGesture(knob);
      // Push past the knob radius, diagonally: this also proves a diagonal
      // is clamped to the same speed as a straight push.
      await gesture.moveBy(const Offset(80, 80));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(game.bean.position.x, greaterThan(start.x));
      expect(game.bean.position.y, greaterThan(start.y));
      expect(
        game.bean.velocity.length,
        lessThanOrEqualTo(ConferenceGame.beanMaxSpeed + 0.001),
      );

      await gesture.up();
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(game.bean.velocity.length, closeTo(0, 0.1));
    });
  });
}
