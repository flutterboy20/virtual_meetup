import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/beach_map.dart';
import 'package:client/game/bean_art.dart';
import 'package:client/game/bean_component.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/game/emote_layer.dart';
import 'package:client/game/furniture_component.dart';
import 'package:client/game/nametag_layer.dart';
import 'package:client/game/water_component.dart';
import 'package:client/game/world_layout.dart';
import 'package:client/game/zone_props.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts every call made on it, and keeps the colour of every circle.
class _CountingCanvas implements Canvas {
  final List<Symbol> calls = [];
  final Set<int> circleColors = {};

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    calls.add(#drawCircle);
    circleColors.add(paint.color.toARGB32());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    return null;
  }
}

const _booth = Sponsor(
  id: 'a',
  name: 'A Corp',
  blurb: '',
  x: 1130,
  y: 478,
  color: Color(0xFF54C5F8),
);

/// The three leaf colours of a tree canopy, darkest first.
const _leaves = {0xFF3C7A34, 0xFF4E9440, 0xFF67AE52};

void main() {
  // Paragraphs need a real engine to lay out, and `ConferenceGame.onLoad`
  // registers a frame-timings callback on the scheduler.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the overhead picture', () {
    test('is replayed with one drawPicture and nothing else', () async {
      // The whole perf argument: whatever is in it, a frame costs one call,
      // and nothing is sorted.
      final overhead = FurnitureComponent.overhead(
        layout: WorldLayout.of(const [_booth]),
      );
      await overhead.onLoad();
      addTearDown(overhead.onRemove);
      final canvas = _CountingCanvas();

      overhead.render(canvas);

      expect(canvas.calls, equals([#drawPicture]));
    });

    test('holds the tree canopies, and the furniture does not', () {
      final map = WorldLayout.of(const []);
      final furniture = _CountingCanvas();
      final overhead = _CountingCanvas();

      map
        ..paintFurniture(furniture)
        ..paintOverhead(overhead);

      expect(overhead.circleColors, containsAll(_leaves));
      expect(furniture.circleColors.intersection(_leaves), isEmpty);
    });

    test('is empty on a map with no tall props', () {
      final canvas = _CountingCanvas();

      const BeachMap().paintOverhead(canvas);

      expect(canvas.calls, isEmpty);
    });
  });

  group('a booth', () {
    final footprint = ZoneProps.rect(_booth.footprint);
    final above = ZoneProps.boothOverhead(footprint);

    test('hides only what stands north of it', () {
      // The collider is a point at a bean's feet, so a visitor can stand
      // right at the counter. Their head, cap and all, must stay clear of
      // the part of the wall drawn over the beans.
      expect(above.bottom, equals(footprint.top));
      expect(
        above.bottom,
        lessThanOrEqualTo(footprint.bottom - BeanArt.bodyHeight * 1.5),
      );
    });

    test('the overhead takes in the whole top of the wall', () {
      // Any of the wall north of the booth outside the clip would be drawn
      // by neither half.
      final face = ZoneProps.boothWall(footprint);
      final wallTop = face.top - 6;

      expect(above.top, lessThan(wallTop));
      expect(above.left, lessThan(face.left));
      expect(above.right, greaterThan(face.right));
    });
  });

  test('the canopy shadows stay on the floor', () {
    // A shadow in the overhead picture would be painted across the beans
    // standing in it.
    final canvas = _CountingCanvas();

    WorldLayout.of(const [_booth]).paintOverhead(canvas);

    expect(
      canvas.calls.where((call) => call == #drawPath),
      isEmpty,
      reason: 'every cast shadow is a path',
    );
  });

  testWithGame<ConferenceGame>(
    'the overhead sits over every bean but your own, under the names',
    ConferenceGame.new,
    (game) async {
      await game.ready();
      final overhead = game.overhead.priority;

      final others = game.world.children.whereType<BeanComponent>().where(
        (bean) => !identical(bean, game.bean),
      );
      expect(others, isNotEmpty);
      for (final bean in others) {
        expect(bean.priority, lessThan(overhead));
      }
      expect(game.remotePlayers.priority, lessThan(overhead));
      expect(game.bean.priority, greaterThan(overhead));
      expect(
        game.world.children.whereType<SplashLayer>().single.priority,
        greaterThan(game.bean.priority),
        reason: 'you dive through your own droplets',
      );
      expect(
        game.world.children.whereType<EmoteLayer>().single.priority,
        greaterThan(game.bean.priority),
      );
      expect(
        game.world.children.whereType<NametagLayer>().single.priority,
        greaterThan(game.bean.priority),
      );
    },
  );
}
