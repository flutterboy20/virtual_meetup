import 'dart:ui';

import 'package:client/game/static_art.dart';
import 'package:client/game/world_layout.dart';
import 'package:client/game/zone_floor_art.dart';
import 'package:client/game/zone_props.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

Rect _rect(WorldZone zone) => ZoneProps.rect(zone.rect);

void main() {
  // Paragraphs and pictures need a real engine.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the garden', () {
    final garden = _rect(WorldZone.garden);
    final walk = ZoneFloorArt.gardenWalk(garden);
    final deck = ZoneProps.rect(WorldLayout.gardenDeck);
    final fountain = Offset(WorldLayout.fountain.x, WorldLayout.fountain.y);
    final stones = ZoneFloorArt.steppingStones(garden);
    const r = ZoneFloorArt.stoneRadius;

    test('the stepping stones lead from the fountain to the deck', () {
      expect(stones, isNotEmpty);
      expect(stones.first.dx, lessThan(walk.left), reason: 'fountain side');
      expect(stones.last.dx, greaterThan(walk.right), reason: 'deck side');
      for (var i = 1; i < stones.length; i++) {
        expect(stones[i].dx, greaterThan(stones[i - 1].dx));
      }
    });

    test('no stone sits on the walk, the deck or the gravel', () {
      for (final stone in stones) {
        final box = Rect.fromCircle(center: stone, radius: r);

        expect(garden.contains(stone), isTrue, reason: '$stone');
        expect(box.overlaps(walk), isFalse, reason: '$stone on the walk');
        expect(box.overlaps(deck), isFalse, reason: '$stone under a step');
        expect(
          (stone - fountain).distance - r,
          greaterThanOrEqualTo(ZoneFloorArt.gravelRadius),
          reason: '$stone in the gravel',
        );
      }
    });

    test('no two stones overlap', () {
      for (var i = 1; i < stones.length; i++) {
        expect(stones[i].dx - stones[i - 1].dx, greaterThanOrEqualTo(2 * r));
      }
    });

    test('the gravel is wider than the basin and short of the walk', () {
      expect(
        ZoneFloorArt.gravelRadius,
        greaterThan(WorldLayout.fountain.radius),
      );
      expect(
        fountain.dx + ZoneFloorArt.gravelRadius,
        lessThanOrEqualTo(walk.left),
      );
    });
  });

  test('the compass rose sits inside the medallion, under the ring', () {
    // The medallion's inner ring is at 112, and the atrium is 400 across.
    expect(ZoneFloorArt.compassPoint, lessThan(112));
    expect(ZoneFloorArt.compassRing, greaterThan(148));
    expect(
      ZoneFloorArt.compassRing,
      lessThan(_rect(WorldZone.atrium).width / 2),
    );
  });

  test('the checker and the terracotta are never cut at a wall', () {
    for (final (zone, size) in [
      (WorldZone.sponsorRow, ZoneFloorArt.expoSquare),
      (WorldZone.foodCourt, ZoneFloorArt.terracottaTile),
    ]) {
      final rect = _rect(zone);

      expect(rect.width % size, isZero, reason: '${zone.name} wide');
      expect(rect.height % size, isZero, reason: '${zone.name} deep');
    }
  });

  test('carpet tiles are laid quarter-turned', () {
    for (var row = 0; row < 4; row++) {
      for (var column = 0; column < 4; column++) {
        final here = ZoneFloorArt.carpetRunsVertically(column, row);

        expect(ZoneFloorArt.carpetRunsVertically(column + 1, row), isNot(here));
        expect(ZoneFloorArt.carpetRunsVertically(column, row + 1), isNot(here));
      }
    }
  });

  test('every conference floor records', () {
    final picture = recordPicture((canvas) {
      for (final zone in WorldZone.values) {
        ZoneFloorArt.paint(canvas, zone, _rect(zone));
      }
    });
    addTearDown(picture.dispose);
  });
}
