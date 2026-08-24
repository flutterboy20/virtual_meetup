import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/collision.dart';
import 'package:client/game/world_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

Sponsor _sponsor(String id, double x, double y) => Sponsor(
  id: id,
  name: id,
  blurb: '',
  x: x,
  y: y,
  color: const Color(0xFF54C5F8),
);

void main() {
  group('the venue', () {
    test('every fixed prop stands on a floor, not outside the cross', () {
      // A prop drawn outside the cross would float on the backdrop, and its
      // collision box would be an invisible wall in a place with no wall.
      for (final obstacle in WorldLayout.fixedObstacles) {
        final (x, y) = switch (obstacle) {
          RectObstacle(:final rect) => (rect.centerX, rect.centerY),
          CircleObstacle(:final x, :final y) => (x, y),
        };
        expect(
          WorldZone.at(x, y),
          isNotNull,
          reason: '$obstacle is outside the cross',
        );
      }
    });

    test('every fixed prop stands where a bean could have stood', () {
      // Stronger than "inside a zone": a prop sitting in the 24-unit outer
      // inset is drawn half outside the building, and its collision box is a
      // wall in a place with no floor behind it.
      for (final obstacle in WorldLayout.fixedObstacles) {
        final corners = switch (obstacle) {
          RectObstacle(:final rect) => [
            (rect.left, rect.top),
            (rect.right, rect.top),
            (rect.left, rect.bottom),
            (rect.right, rect.bottom),
          ],
          CircleObstacle(:final x, :final y, :final radius) => [
            (x - radius, y),
            (x + radius, y),
            (x, y - radius),
            (x, y + radius),
          ],
        };
        for (final (x, y) in corners) {
          expect(
            isOnFloor(x, y),
            isTrue,
            reason: '$obstacle overhangs the edge of the building at $x,$y',
          );
        }
      }
    });

    test('the seat rows leave a centre aisle', () {
      final aisle = WorldZone.hall.rect.centerX;
      for (final seat in WorldLayout.seatRows) {
        expect(
          seat.contains(aisle, seat.rect.centerY),
          isFalse,
          reason: 'a seat row blocks the aisle',
        );
      }
    });

    test('no prop stands in a walkway between two rooms', () {
      // The geometry test in `protocol/` proves the *floor* is continuous
      // across every seam. This proves nothing has since been parked on one.
      // Three zones gained a newly shared edge in Phase 9, and two of them
      // gained a room full of furniture at the same time.
      final collision = WorldCollision(WorldLayout.of(const []));
      const seams = [
        // (fixed axis value, from, to, isVertical)
        (600.0, 424.0, 776.0, true), // chai yard | atrium
        (1000.0, 424.0, 776.0, true), // atrium | sponsor row
        (400.0, 624.0, 976.0, false), // hall | atrium
        (800.0, 624.0, 976.0, false), // atrium | lounge
        (1000.0, 40.0, 380.0, true), // hall | code lab
        (400.0, 1024.0, 1560.0, false), // code lab | sponsor row
        (800.0, 40.0, 580.0, false), // chai yard | garden
        (600.0, 824.0, 1160.0, true), // garden | lounge
      ];

      for (final (fixed, from, to, vertical) in seams) {
        for (var t = from; t <= to; t += 8) {
          final x = vertical ? fixed : t;
          final y = vertical ? t : fixed;
          expect(
            collision.isFree(x, y),
            isTrue,
            reason: 'a prop is standing in the walkway at $x,$y',
          );
        }
      }
    });

    test('the code lab desks leave an aisle', () {
      // A solid 480-unit bench is the one prop guaranteed to trap somebody,
      // which is why the hall's seating is split. The lab has three rows of
      // exactly that shape.
      final collision = WorldCollision(WorldLayout.of(const []));
      for (var y = 120.0; y < 380; y += 6) {
        expect(
          collision.isFree(WorldLayout.labAisleX, y),
          isTrue,
          reason: 'the code lab aisle is blocked at y=$y',
        );
      }
    });

    test('the stepped deck is flat and walkable, not an obstacle', () {
      // It is **fake depth**. If this ever fails, somebody has read the
      // drawn treads as a real elevation and given them a collision box.
      final collision = WorldCollision(WorldLayout.of(const []));
      const deck = WorldLayout.gardenDeck;

      for (var x = deck.left; x <= deck.right; x += 10) {
        for (var y = deck.top; y <= deck.bottom; y += 10) {
          expect(
            collision.isFree(x, y),
            isTrue,
            reason: 'the stepped deck is solid at $x,$y',
          );
        }
      }
    });

    test('the deck looks out over the pool it is meant to overlook', () {
      // Stairs that lead nowhere read as decoration. This is the one
      // relationship that makes the deck a place instead of a texture.
      const deck = WorldLayout.gardenDeck;
      const pool = WorldLayout.pool;

      expect(deck.top, lessThan(pool.bottom));
      expect(deck.bottom, greaterThan(pool.top));
      expect(
        pool.left - deck.right,
        lessThan(200),
        reason: 'the pool is too far from the deck to be a view',
      );
    });

    test('the credit pillar is smaller than the spawn ring', () {
      // Otherwise everybody arrives inside it: invisible, and stuck until the
      // collision escape hatch walks them out.
      expect(WorldLayout.pillarRadius, lessThan(spawnRingRadius * 0.75));
    });

    test('the crowd glow is inside the chai yard', () {
      expect(
        WorldZone.at(WorldLayout.courtGlowX, WorldLayout.courtGlowY),
        equals(WorldZone.foodCourt),
      );
    });

    test('the glow is not solid — it is a place, not a prop', () {
      final onGlow = WorldLayout.fixedObstacles.any(
        (obstacle) =>
            obstacle.contains(WorldLayout.courtGlowX, WorldLayout.courtGlowY),
      );
      expect(onGlow, isFalse);
    });

    test('the chai stall leaves room to walk past it', () {
      // The counter runs most of the west wall, so the lane between it and
      // the stools is the only way along that side. Closing it would wall off
      // a third of the yard, and nothing on screen would say so.
      final collision = WorldCollision(WorldLayout.of(const []));
      for (var y = 470.0; y < 706; y += 6) {
        expect(
          collision.isFree(152, y),
          isTrue,
          reason: 'the lane past the chai counter is blocked at y=$y',
        );
      }
    });
  });

  group('booths', () {
    test('each one adds exactly one obstacle', () {
      final layout = WorldLayout.of([_sponsor('a', 1130, 478)]);

      expect(
        layout.obstacles,
        hasLength(WorldLayout.fixedObstacles.length + 1),
      );
    });

    test('nearest wins when two are in range', () {
      // Booths sit close enough that two radii overlap in the aisle, and
      // "whichever came first in the JSON" is not an answer a walking player
      // can predict.
      final layout = WorldLayout.of([
        _sponsor('near', 1130, 478),
        _sponsor('far', 1330, 478),
      ]);

      final chosen = layout.nearestSponsor(1160, 478, Sponsor.approachRadius);

      expect(chosen?.id, equals('near'));
    });

    test('nothing is returned from outside every radius', () {
      final layout = WorldLayout.of([_sponsor('a', 1130, 478)]);

      expect(
        layout.nearestSponsor(
          spawnCenterX,
          spawnCenterY,
          Sponsor.approachRadius,
        ),
        isNull,
      );
    });

    test('an empty config is an empty sponsor row', () {
      final layout = WorldLayout.of(const []);

      expect(layout.sponsors, isEmpty);
      expect(layout.nearestSponsor(1130, 478, 999), isNull);
    });
  });
}
