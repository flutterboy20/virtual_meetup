import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/core/world_palette.dart';
import 'package:client/game/beach_layout.dart';
import 'package:client/game/beach_map.dart';
import 'package:client/game/collision.dart';
import 'package:client/game/floor_component.dart';
import 'package:client/game/furniture_component.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// The bounding box of an obstacle, whichever shape it is.
Rect _boundsOf(Obstacle obstacle) => switch (obstacle) {
  RectObstacle(:final rect) => Rect.fromLTRB(
    rect.left,
    rect.top,
    rect.right,
    rect.bottom,
  ),
  CircleObstacle(:final x, :final y, :final radius) => Rect.fromCircle(
    center: Offset(x, y),
    radius: radius,
  ),
};

/// Renders [component] once into a throwaway picture.
Picture _renderOnce(Component component) {
  final recorder = PictureRecorder();
  component.render(Canvas(recorder));
  return recorder.endRecording();
}

void main() {
  const beach = BeachMap();

  group('BeachMap', () {
    test('is the beach, and knows it', () {
      expect(beach.spec, equals(MapSpec.beach));
      expect(beach.spec.id, equals(MapId.beach));
      expect(gameMapFor(MapId.beach), isA<BeachMap>());
      expect(gameMapFor(MapId.conference), isA<ConferenceMap>());
    });

    test('has no booths, and drops any it is handed', () {
      // Not a feature switched off: a sponsor footprint is a coordinate in
      // the *conference's* space, so placing one here would put a booth in
      // the sea.
      expect(beach.sponsors, isEmpty);
      expect(
        gameMapFor(
          MapId.beach,
          sponsors: [
            const Sponsor(
              id: 'acme',
              name: 'Acme',
              blurb: 'Anvils',
              color: Color(0xFF54C5F8),
              x: 100,
              y: 100,
            ),
          ],
        ).sponsors,
        isEmpty,
      );
    });

    test('has no voids: the three bands tile the whole box', () {
      expect(beach.voids, isEmpty);
      for (var x = 4.0; x < beach.spec.width; x += 20) {
        for (var y = 4.0; y < beach.spec.height; y += 20) {
          expect(
            beach.spec.zoneAt(x, y),
            isNotNull,
            reason: 'a hole in the beach at $x, $y',
          );
        }
      }
    });
  });

  group('the beach floor plan', () {
    test('no obstacle sits outside the walkable floor', () {
      // The bug this catches is a prop drawn somewhere a bean can never reach
      // it, or worse, one straddling the map edge so that walking into it
      // pins somebody against a wall they cannot see.
      const collision = WorldCollision(beach);

      for (final obstacle in beach.obstacles) {
        final bounds = _boundsOf(obstacle);
        for (final corner in [
          bounds.topLeft,
          bounds.topRight,
          bounds.bottomLeft,
          bounds.bottomRight,
          bounds.center,
        ]) {
          expect(
            beach.spec.isOnFloor(corner.dx, corner.dy),
            isTrue,
            reason: '$obstacle reaches $corner, which is off the floor',
          );
        }
        // And the obstacle really does block: the collision map and the prop
        // list cannot have drifted apart.
        expect(collision.isFree(bounds.center.dx, bounds.center.dy), isFalse);
      }
    });

    test('sea and obstacles do not overlap', () {
      // Nothing solid in the water, on purpose — see `BeachLayout`. Being
      // stopped dead by a raft mid-swim is the most irritating thing this
      // map could do, and the landmarks work as landmarks without it.
      for (final water in beach.waterRegions) {
        final wet = Rect.fromLTRB(
          water.left,
          water.top,
          water.right,
          water.bottom,
        );
        for (final obstacle in beach.obstacles) {
          expect(
            wet.overlaps(_boundsOf(obstacle)),
            isFalse,
            reason: '$obstacle is standing in the sea',
          );
        }
      }
    });

    test('the whole spawn ring is clear of furniture', () {
      const collision = WorldCollision(beach);
      final spec = beach.spec;

      for (var i = 0; i < 180; i++) {
        final angle = i / 180 * 2 * math.pi;
        final x = spec.spawnCenterX + spec.spawnRingRadius * math.cos(angle);
        final y = spec.spawnCenterY + spec.spawnRingRadius * math.sin(angle);
        expect(
          collision.isFree(x, y),
          isTrue,
          reason: 'a new arrival at $x, $y lands inside something',
        );
      }
    });

    test('nobody spawns wet', () {
      // A first frame spent underwater is a first frame spent confused, and
      // it is why the beach's ring is 80 where the conference's is 120.
      final spec = beach.spec;
      for (var i = 0; i < 180; i++) {
        final angle = i / 180 * 2 * math.pi;
        final x = spec.spawnCenterX + spec.spawnRingRadius * math.cos(angle);
        final y = spec.spawnCenterY + spec.spawnRingRadius * math.sin(angle);
        expect(beach.isWater(x, y), isFalse);
        expect(spec.zoneAt(x, y), equals(WorldZone.beachSand));
      }
    });

    test('the sea is walkable, and slow', () {
      // Water is floor. That is what makes swimming free: no new mechanic,
      // no new message, just a speed multiplier and a boolean.
      const collision = WorldCollision(beach);
      const middleOfTheSea = Offset(600, 700);

      expect(
        collision.isFree(middleOfTheSea.dx, middleOfTheSea.dy),
        isTrue,
      );
      expect(beach.isWater(middleOfTheSea.dx, middleOfTheSea.dy), isTrue);
      expect(
        beach.speedFactorAt(middleOfTheSea.dx, middleOfTheSea.dy),
        equals(beach.swimSpeedFactor),
      );
      expect(beach.speedFactorAt(600, 310), equals(1));
    });

    test('the raft is dry land in the middle of the sea', () {
      // The point of the platform: you swim out, climb on, and walk. The
      // deck is inside the sea rect — the water is drawn under it — so the
      // only thing keeping the bean out of the water is `dryPlatforms`.
      const collision = WorldCollision(beach);
      const raft = BeachLayout.raft;
      final sea = beach.waterRegions.single;

      expect(sea.contains(raft.centerX, raft.centerY), isTrue);
      expect(beach.isWater(raft.centerX, raft.centerY), isFalse);
      expect(beach.speedFactorAt(raft.centerX, raft.centerY), equals(1));
      // And you are never blocked by it: it is a floor, not an obstacle.
      expect(collision.isFree(raft.centerX, raft.centerY), isTrue);
      for (final obstacle in beach.obstacles) {
        expect(
          _boundsOf(obstacle).overlaps(
            Rect.fromLTRB(raft.left, raft.top, raft.right, raft.bottom),
          ),
          isFalse,
          reason: '$obstacle would stop a bean climbing onto the raft',
        );
      }

      // Every corner of the deck is dry, and one step off any edge is wet.
      for (final corner in [
        Offset(raft.left + 1, raft.top + 1),
        Offset(raft.right - 1, raft.top + 1),
        Offset(raft.left + 1, raft.bottom - 1),
        Offset(raft.right - 1, raft.bottom - 1),
      ]) {
        expect(beach.isWater(corner.dx, corner.dy), isFalse);
      }
      expect(beach.isWater(raft.left - 4, raft.centerY), isTrue);
      expect(beach.isWater(raft.right + 4, raft.centerY), isTrue);
      expect(beach.isWater(raft.centerX, raft.top - 4), isTrue);
      expect(beach.isWater(raft.centerX, raft.bottom + 4), isTrue);
    });

    test('the conference has no dry platforms', () {
      // The base class default, not something every map has to switch off.
      expect(const BeachMap().dryPlatforms, equals([BeachLayout.raft]));
      expect(ConferenceMap.empty.dryPlatforms, isEmpty);
    });

    test('the sea really is most of the map', () {
      // The reason the water perf task had to land first.
      final sea = beach.waterRegions.single;
      final share =
          (sea.width * sea.height) / (beach.spec.width * beach.spec.height);
      expect(share, greaterThan(0.5));
    });

    test('the band seams are walkable, so it is one place not three', () {
      const collision = WorldCollision(beach);
      for (final y in [200.0, 420.0]) {
        var free = 0;
        for (var x = 40.0; x < beach.spec.width - 40; x += 20) {
          if (collision.isFree(x, y)) free++;
        }
        // Not every point — the rail posts and the shacks are allowed to sit
        // on a seam — but the great majority of it has to be open.
        expect(free, greaterThan(40));
      }
    });
  });

  group('the beach palette', () {
    test('the three bands are far apart in value, not just in hue', () {
      // The readability test for this world is a phone at arm's length in the
      // sun, where hue is the first thing to go. Dark planks, bright sand,
      // deep water is a ladder you can read without colour at all.
      double luminance(WorldZone zone) =>
          WorldPalette.of(zone).floor.computeLuminance();

      final boardwalk = luminance(WorldZone.beachBoardwalk);
      final sand = luminance(WorldZone.beachSand);
      final sea = luminance(WorldZone.beachSea);

      expect(sand, greaterThan(boardwalk));
      expect(boardwalk, greaterThan(sea));
      expect(sand - sea, greaterThan(0.35));
    });

    test('every beach zone has its own colours', () {
      final floors = MapSpec.beach.zones
          .map((zone) => WorldPalette.of(zone).floor)
          .toSet();
      expect(floors.length, equals(MapSpec.beach.zones.length));
    });
  });

  group('the beach as static art', () {
    test('the floor records once and replays', () async {
      final floor = FloorComponent(map: beach);
      await floor.onLoad();

      for (var i = 0; i < 3; i++) {
        _renderOnce(floor).dispose();
      }

      floor.onRemove();
    });

    test('the furniture records once and replays', () async {
      final furniture = FurnitureComponent(layout: beach);
      await furniture.onLoad();

      expect(() => _renderOnce(furniture).dispose(), returnsNormally);

      furniture.onRemove();
    });

    test('the floor sizes itself from the spec', () {
      final floor = FloorComponent(map: beach);

      expect(floor.size.x, equals(MapSpec.beach.width));
      expect(floor.size.y, equals(MapSpec.beach.height));
    });
  });
}
