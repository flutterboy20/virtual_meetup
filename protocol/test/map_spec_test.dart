import 'dart:math' as math;

import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('MapId', () {
    test('round-trips through its wire id', () {
      for (final map in MapId.values) {
        expect(MapId.fromId(map.id), equals(map));
      }
    });

    test('an unknown, empty or missing id reads as the conference', () {
      expect(MapId.fromId('lagoon'), equals(MapId.conference));
      expect(MapId.fromId(''), equals(MapId.conference));
      expect(MapId.fromId(null), equals(MapId.conference));
      // Case matters: the ids are wire values, not free text.
      expect(MapId.fromId('Beach'), equals(MapId.conference));
    });

    test('tryFromId keeps "not a map" distinguishable from "conference"', () {
      expect(MapId.tryFromId('beach'), equals(MapId.beach));
      expect(MapId.tryFromId('lagoon'), isNull);
      expect(MapId.tryFromId(null), isNull);
    });

    test('every map has a distinct id and a label', () {
      final ids = MapId.values.map((map) => map.id).toSet();
      expect(ids.length, equals(MapId.values.length));
      for (final map in MapId.values) {
        expect(map.label, isNotEmpty);
      }
    });
  });

  group('MapSpec', () {
    test('the conference spec still says what the old constants said', () {
      // The one test that stops `world.dart` and `MapSpec.conference` drifting
      // apart while both exist.
      const spec = MapSpec.conference;
      expect(spec.width, equals(worldWidth));
      expect(spec.height, equals(worldHeight));
      expect(spec.edgeInset, equals(worldEdgeInset));
      expect(spec.spawnCenterX, equals(spawnCenterX));
      expect(spec.spawnCenterY, equals(spawnCenterY));
      expect(spec.spawnRingRadius, equals(spawnRingRadius));
      expect(spec.clampX(-500), equals(clampWorldX(-500)));
      expect(spec.clampY(99999), equals(clampWorldY(99999)));
    });

    test('of() maps every id to a spec that knows its own id', () {
      for (final id in MapId.values) {
        expect(MapSpec.of(id).id, equals(id));
      }
      expect(MapSpec.values.length, equals(MapId.values.length));
    });

    test('the hand-written zone lists match the enum', () {
      for (final spec in MapSpec.values) {
        expect(spec.zones, equals(WorldZone.of(spec.id)));
        for (final zone in spec.zones) {
          expect(zone.map, equals(spec.id));
        }
      }
      // And between them they account for every zone there is, so a new one
      // cannot be added to the enum and forgotten by both specs.
      expect(
        MapSpec.values.expand((spec) => spec.zones).toSet(),
        equals(WorldZone.values.toSet()),
      );
    });

    test('the beach is deliberately smaller than the conference', () {
      expect(
        MapSpec.beach.width * MapSpec.beach.height,
        lessThan(MapSpec.conference.width * MapSpec.conference.height),
      );
    });

    for (final spec in MapSpec.values) {
      group(spec.id.id, () {
        test('every zone sits inside the map', () {
          for (final zone in spec.zones) {
            expect(zone.rect.left, greaterThanOrEqualTo(0));
            expect(zone.rect.top, greaterThanOrEqualTo(0));
            expect(zone.rect.right, lessThanOrEqualTo(spec.width));
            expect(zone.rect.bottom, lessThanOrEqualTo(spec.height));
          }
        });

        test('no two zones overlap', () {
          for (var i = 0; i < spec.zones.length; i++) {
            for (var j = i + 1; j < spec.zones.length; j++) {
              final a = spec.zones[i].rect;
              final b = spec.zones[j].rect;
              final overlaps =
                  a.left < b.right &&
                  b.left < a.right &&
                  a.top < b.bottom &&
                  b.top < a.bottom;
              expect(
                overlaps,
                isFalse,
                reason: '${spec.zones[i].id} overlaps ${spec.zones[j].id}',
              );
            }
          }
        });

        test('zoneAt agrees with the rectangles', () {
          for (final zone in spec.zones) {
            expect(
              spec.zoneAt(zone.rect.centerX, zone.rect.centerY),
              equals(zone),
            );
          }
          // A zone from the *other* map is never returned, even though the
          // two coordinate spaces overlap numerically.
          for (var x = 10.0; x < spec.width; x += 60) {
            for (var y = 10.0; y < spec.height; y += 60) {
              expect(spec.zoneAt(x, y)?.map, anyOf(isNull, equals(spec.id)));
            }
          }
        });

        test('the whole spawn ring lands on the floor', () {
          for (var i = 0; i < 64; i++) {
            final angle = i / 64 * 2 * math.pi;
            final x =
                spec.spawnCenterX + spec.spawnRingRadius * math.cos(angle);
            final y =
                spec.spawnCenterY + spec.spawnRingRadius * math.sin(angle);
            expect(
              spec.isOnFloor(x, y),
              isTrue,
              reason: 'the ${spec.id.id} spawn ring leaves the floor',
            );
          }
        });

        test('clamping keeps a wild position inside the box', () {
          expect(spec.clampX(-99999), equals(spec.edgeInset));
          expect(spec.clampX(99999), equals(spec.width - spec.edgeInset));
          expect(spec.clampY(-99999), equals(spec.edgeInset));
          expect(spec.clampY(99999), equals(spec.height - spec.edgeInset));
        });

        test('the map has no unintended gaps', () {
          // Sampled rather than exhaustive; the step is finer than the
          // thinnest band on either map.
          for (var x = 4.0; x < spec.width; x += 20) {
            for (var y = 4.0; y < spec.height; y += 20) {
              if (spec.zoneAt(x, y) != null) continue;
              // Only the conference has deliberate voids, and only in its
              // two empty corners.
              expect(
                spec.id,
                equals(MapId.conference),
                reason: 'a hole in ${spec.id.id} at $x, $y',
              );
            }
          }
        });
      });
    }

    test('every shared edge on the beach is walkable from both sides', () {
      // The seams are what make three bands one place rather than three
      // rooms. Insetting a shared edge would put an invisible wall across
      // the whole width of the map.
      for (final y in [200.0, 420.0]) {
        for (var x = worldEdgeInset; x < beachWidth - worldEdgeInset; x += 40) {
          expect(
            MapSpec.beach.isOnFloor(x, y),
            isTrue,
            reason: 'the beach seam at y=$y is blocked at x=$x',
          );
        }
      }
    });

    test('the beach spawn ring is inside the sand, not the sea', () {
      const spec = MapSpec.beach;
      for (var i = 0; i < 64; i++) {
        final angle = i / 64 * 2 * math.pi;
        final x = spec.spawnCenterX + spec.spawnRingRadius * math.cos(angle);
        final y = spec.spawnCenterY + spec.spawnRingRadius * math.sin(angle);
        expect(spec.zoneAt(x, y), equals(WorldZone.beachSand));
      }
    });

    test('the conference spawn ring is inside the atrium', () {
      const spec = MapSpec.conference;
      for (var i = 0; i < 64; i++) {
        final angle = i / 64 * 2 * math.pi;
        final x = spec.spawnCenterX + spec.spawnRingRadius * math.cos(angle);
        final y = spec.spawnCenterY + spec.spawnRingRadius * math.sin(angle);
        expect(spec.zoneAt(x, y), equals(WorldZone.atrium));
      }
    });

    test('the unqualified helpers still answer for the conference', () {
      // Phase 10 added zones whose rectangles overlap the conference's. If
      // `isOnFloor` or `WorldZone.at` had been left scanning every zone, a
      // point in a void corner would now read as beach floor.
      expect(isOnFloor(1300, 1000), isFalse);
      expect(WorldZone.at(1300, 1000), isNull);
      expect(
        WorldZone.at(spawnCenterX, spawnCenterY),
        equals(WorldZone.atrium),
      );
      expect(WorldZone.at(100, 100), isNull);
    });
  });
}
