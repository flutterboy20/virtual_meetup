import 'dart:math' as math;

import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

/// The pairs of zones that share a full edge.
///
/// Written out once, and every adjacency test below reads from it. The
/// walkable insets are decided per zone from exactly this list, so a test that
/// re-typed the coordinates would only ever restate the bug.
const seams = <({WorldZone a, WorldZone b})>[
  (a: WorldZone.foodCourt, b: WorldZone.atrium),
  (a: WorldZone.atrium, b: WorldZone.sponsorRow),
  (a: WorldZone.hall, b: WorldZone.atrium),
  (a: WorldZone.atrium, b: WorldZone.lounge),
  (a: WorldZone.hall, b: WorldZone.codeLab),
  (a: WorldZone.codeLab, b: WorldZone.sponsorRow),
  (a: WorldZone.foodCourt, b: WorldZone.garden),
  (a: WorldZone.garden, b: WorldZone.lounge),
];

/// Points spread along the seam [a] and [b] share, endpoints excluded.
///
/// The corners are skipped: a seam's endpoint is also the endpoint of some
/// other zone's outward-facing edge, which is legitimately inset.
Iterable<({double x, double y})> alongSeam(WorldZone a, WorldZone b) sync* {
  final ra = a.rect;
  final rb = b.rect;
  if (ra.right == rb.left) {
    final top = math.max(ra.top, rb.top);
    final bottom = math.min(ra.bottom, rb.bottom);
    for (var i = 1; i < 12; i++) {
      yield (x: ra.right, y: top + (bottom - top) * i / 12);
    }
  } else if (ra.bottom == rb.top) {
    final left = math.max(ra.left, rb.left);
    final right = math.min(ra.right, rb.right);
    for (var i = 1; i < 12; i++) {
      yield (x: left + (right - left) * i / 12, y: ra.bottom);
    }
  } else {
    fail('${a.id} and ${b.id} do not share an edge at all');
  }
}

void main() {
  group('WorldRect', () {
    const rect = WorldRect(10, 20, 110, 220);

    test('reports its own measurements', () {
      expect(rect.width, equals(100));
      expect(rect.height, equals(200));
      expect(rect.centerX, equals(60));
      expect(rect.centerY, equals(120));
    });

    test('contains its own edges', () {
      // Inclusive edges are what lets two zones share a walkway instead of
      // growing a one-unit crack between them.
      expect(rect.contains(10, 20), isTrue);
      expect(rect.contains(110, 220), isTrue);
      expect(rect.contains(9.9, 20), isFalse);
      expect(rect.contains(10, 220.1), isFalse);
    });

    test('deflates and inflates', () {
      expect(
        rect.deflate(left: 5, bottom: 20),
        equals(const WorldRect(15, 20, 110, 200)),
      );
      expect(rect.inflate(10), equals(const WorldRect(0, 10, 120, 230)));
    });
  });

  group('the seven zones', () {
    test('every zone has a unique id that round-trips', () {
      final ids = WorldZone.values.map((zone) => zone.id).toSet();
      expect(ids, hasLength(WorldZone.values.length));
      for (final zone in WorldZone.values) {
        expect(WorldZone.fromId(zone.id), equals(zone));
      }
      // The new rooms and the rename, by name: these ids appear in config and
      // in logs, so a silent change to one is a silent break.
      expect(WorldZone.fromId('codeLab'), equals(WorldZone.codeLab));
      expect(WorldZone.fromId('garden'), equals(WorldZone.garden));
      expect(WorldZone.fromId('foodCourt'), equals(WorldZone.foodCourt));
      expect(WorldZone.fromId('photoWall'), isNull);
      expect(WorldZone.fromId('nowhere'), isNull);
      expect(WorldZone.fromId(null), isNull);
    });

    test('every zone is reachable from the atrium', () {
      // A breadth-first walk over the seams. A room joined to nothing is a
      // room nobody can get to, and it would look perfectly fine on screen.
      final reached = <WorldZone>{}..add(WorldZone.atrium);
      var grew = true;
      while (grew) {
        grew = false;
        for (final seam in seams) {
          if (reached.contains(seam.a) && reached.add(seam.b)) grew = true;
          if (reached.contains(seam.b) && reached.add(seam.a)) grew = true;
        }
      }
      // Scoped to the conference since Phase 10: the beach's three bands
      // are their own map and share no seam with the atrium by design.
      expect(reached, containsAll(WorldZone.of(MapId.conference)));
    });

    test('no two zones overlap', () {
      // Per map. The beach's rectangles overlap the conference's numerically
      // and are meant to — they are a separate coordinate space.
      final zones = WorldZone.of(MapId.conference);
      for (var i = 0; i < zones.length; i++) {
        for (var j = i + 1; j < zones.length; j++) {
          final a = zones[i].rect;
          final b = zones[j].rect;
          final overlaps =
              a.left < b.right &&
              b.left < a.right &&
              a.top < b.bottom &&
              b.top < a.bottom;
          expect(
            overlaps,
            isFalse,
            reason: '${zones[i].id} overlaps ${zones[j].id}',
          );
        }
      }
    });

    test('the zones tile everything that is not a void', () {
      // A gap between two zones would be a crack a bean can see across and
      // not walk across, and nothing on screen would show it.
      const voids = [
        WorldRect(0, 0, 600, 400),
        WorldRect(1000, 800, 1600, 1200),
      ];
      for (var x = 20.0; x < worldWidth; x += 40) {
        for (var y = 20.0; y < worldHeight; y += 40) {
          final zone = WorldZone.at(x, y);
          final isVoid = voids.any((rect) => rect.contains(x, y));
          expect(
            zone == null,
            equals(isVoid),
            reason: '$x,$y is ${zone?.id ?? "nowhere"}',
          );
        }
      }
    });

    test('the whole map fits inside the world', () {
      for (final zone in WorldZone.values) {
        expect(zone.rect.left, greaterThanOrEqualTo(0));
        expect(zone.rect.top, greaterThanOrEqualTo(0));
        expect(zone.rect.right, lessThanOrEqualTo(worldWidth));
        expect(zone.rect.bottom, lessThanOrEqualTo(worldHeight));
      }
    });

    test('locates a point in its zone', () {
      expect(
        WorldZone.at(spawnCenterX, spawnCenterY),
        equals(WorldZone.atrium),
      );
      expect(WorldZone.at(spawnCenterX, 40), equals(WorldZone.hall));
      expect(
        WorldZone.at(worldWidth - 40, spawnCenterY),
        equals(WorldZone.sponsorRow),
      );
      expect(
        WorldZone.at(spawnCenterX, worldHeight - 40),
        equals(WorldZone.lounge),
      );
      expect(WorldZone.at(40, spawnCenterY), equals(WorldZone.foodCourt));
      expect(WorldZone.at(worldWidth - 40, 40), equals(WorldZone.codeLab));
      expect(WorldZone.at(40, worldHeight - 40), equals(WorldZone.garden));
      // The two remaining corners are outside the building entirely.
      expect(WorldZone.at(40, 40), isNull);
      expect(WorldZone.at(worldWidth - 40, worldHeight - 40), isNull);
    });
  });

  group('isOnFloor', () {
    test('the spawn ring is entirely on the floor', () {
      for (var step = 0; step < 32; step++) {
        final angle = step / 32 * 2 * math.pi;
        final x = spawnCenterX + spawnRingRadius * math.cos(angle);
        final y = spawnCenterY + spawnRingRadius * math.sin(angle);
        expect(
          isOnFloor(x, y),
          isTrue,
          reason: 'spawn at $x,$y is off the floor',
        );
      }
    });

    test('no shared edge is walled off', () {
      // The single easiest way to turn this map back into a maze: inset an
      // edge a neighbour is standing on the other side of. Three zones gained
      // a newly shared edge in this phase, so every seam is walked.
      for (final seam in seams) {
        for (final point in alongSeam(seam.a, seam.b)) {
          expect(
            isOnFloor(point.x, point.y),
            isTrue,
            reason:
                'the ${seam.a.id}/${seam.b.id} walkway is walled off at '
                '${point.x},${point.y}',
          );
        }
      }
    });

    test('standing on a seam still counts as being in a room', () {
      // `at` is what the floor art and the minimap colour a position by, so
      // a seam that read as limbo would flicker both.
      for (final seam in seams) {
        for (final point in alongSeam(seam.a, seam.b)) {
          expect(
            WorldZone.at(point.x, point.y),
            anyOf(equals(seam.a), equals(seam.b)),
          );
        }
      }
    });

    test('the two voids are not floor', () {
      expect(isOnFloor(300, 200), isFalse);
      expect(isOnFloor(20, 20), isFalse);
      expect(isOnFloor(1300, 1000), isFalse);
      expect(isOnFloor(worldWidth - 20, worldHeight - 20), isFalse);
    });

    test('the outer edges keep a bean off the rim', () {
      expect(isOnFloor(spawnCenterX, 0), isFalse);
      expect(isOnFloor(spawnCenterX, worldEdgeInset), isTrue);
      expect(isOnFloor(worldWidth, spawnCenterY), isFalse);
      expect(isOnFloor(worldWidth - worldEdgeInset, spawnCenterY), isTrue);
      // The two new rooms own an outer corner each.
      expect(isOnFloor(worldWidth - worldEdgeInset, worldEdgeInset), isTrue);
      expect(isOnFloor(worldEdgeInset, worldHeight - worldEdgeInset), isTrue);
      expect(isOnFloor(worldWidth, worldEdgeInset), isFalse);
      expect(isOnFloor(worldEdgeInset, worldHeight), isFalse);
    });
  });

  group('EmoteKind', () {
    test('every kind round-trips its wire name', () {
      for (final kind in EmoteKind.values) {
        expect(EmoteKind.fromWireName(kind.wireName), equals(kind));
      }
    });

    test('an unknown reaction is null, never a default', () {
      // Defaulting would put a reaction over somebody's head that they did
      // not choose, which is worse than dropping the message.
      expect(EmoteKind.fromWireName('shrug'), isNull);
      expect(EmoteKind.fromWireName(null), isNull);
    });

    test('every kind has a glyph and they are all different', () {
      final glyphs = EmoteKind.values.map((kind) => kind.glyph).toSet();
      expect(glyphs, hasLength(EmoteKind.values.length));
      expect(glyphs.every((glyph) => glyph.isNotEmpty), isTrue);
    });
  });
}
