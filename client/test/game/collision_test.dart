import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/collision.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

void main() {
  const booth = Sponsor(
    id: 'a',
    name: 'A',
    blurb: '',
    x: 1130,
    y: 478,
    color: Color(0xFF54C5F8),
  );

  final empty = WorldCollision(WorldLayout.of(const []));
  final furnished = WorldCollision(WorldLayout.of(const [booth]));

  group('what counts as floor', () {
    test('the atrium is open', () {
      expect(empty.isFree(spawnCenterX, spawnCenterY - 100), isTrue);
    });

    test('the corners of the bounding box are not', () {
      // The world is a cross inside a rectangle; the rectangle's corners are
      // outside the building.
      expect(empty.isFree(40, 40), isFalse);
      expect(empty.isFree(worldWidth - 40, worldHeight - 40), isFalse);
    });

    test('the walkways between zones are open', () {
      final seam = WorldZone.atrium.rect;
      expect(empty.isFree(spawnCenterX, seam.top), isTrue);
      expect(empty.isFree(seam.right, spawnCenterY), isTrue);
    });

    test('the stage is solid', () {
      expect(
        empty.isFree(WorldLayout.stage.centerX, WorldLayout.stage.centerY),
        isFalse,
      );
    });

    test('the pool is swimmable, not solid', () {
      // Phase 9 took the pool out of the obstacle list. It is a water region
      // now: walkable, and slow — see `swim_test.dart` for the rest of it.
      expect(
        empty.isFree(WorldLayout.pool.centerX, WorldLayout.pool.centerY),
        isTrue,
      );
    });

    test('the credit pillar is solid, and only just', () {
      expect(empty.isFree(WorldLayout.pillarX, WorldLayout.pillarY), isFalse);
      expect(
        empty.isFree(
          WorldLayout.pillarX + WorldLayout.pillarRadius + 1,
          WorldLayout.pillarY,
        ),
        isTrue,
      );
    });

    test('a booth is solid, and only when there is a booth there', () {
      expect(furnished.isFree(booth.x, booth.y), isFalse);
      // Same spot, no config entry: booths are data, so an empty config is an
      // empty sponsor row rather than an invisible wall.
      expect(empty.isFree(booth.x, booth.y), isTrue);
    });

    test('the aisle between the booth rows stays walkable', () {
      // The thing that would quietly ruin the east arm: booths sized or
      // placed so the corridor between the rows closes up.
      for (var x = 1030.0; x < worldWidth - 40; x += 10) {
        expect(
          furnished.isFree(x, 600),
          isTrue,
          reason: 'the sponsor row aisle is blocked at x=$x',
        );
      }
    });
  });

  group('resolving a move', () {
    test('an unobstructed move is taken whole', () {
      final from = Vector2(spawnCenterX, spawnCenterY - 100);
      final to = Vector2(spawnCenterX + 5, spawnCenterY - 95);

      expect(empty.resolve(from: from, to: to), equals(to));
    });

    test('walking straight into a wall stops at it', () {
      final from = Vector2(
        WorldLayout.stage.centerX,
        WorldLayout.stage.bottom + 4,
      );
      final to = Vector2(from.x, WorldLayout.stage.bottom - 4);

      final result = empty.resolve(from: from, to: to);

      expect(result.y, equals(from.y));
      expect(result.x, equals(from.x));
    });

    test('walking diagonally into a wall slides along it', () {
      // The reason the axes are resolved separately. Without sliding, a
      // player has to steer around every wall by hand, which reads as the
      // controls being broken rather than as a wall being there.
      final from = Vector2(
        WorldLayout.stage.centerX,
        WorldLayout.stage.bottom + 4,
      );
      final to = Vector2(from.x + 6, from.y - 8);

      final result = empty.resolve(from: from, to: to);

      expect(result.x, equals(to.x), reason: 'the sideways half was dropped');
      expect(result.y, equals(from.y), reason: 'it walked into the stage');
    });

    test('a move off the edge of the world is refused', () {
      final from = Vector2(spawnCenterX, worldEdgeInset + 1);
      final to = Vector2(spawnCenterX, -20);

      expect(empty.resolve(from: from, to: to).y, equals(from.y));
    });

    test('a bean that starts somewhere illegal can always walk out', () {
      // A booth moved in config onto where somebody was standing. Sealing
      // them in would leave a player with no way to report it and no way to
      // fix it, so an illegal start means every move is allowed.
      final inside = Vector2(booth.x, booth.y);
      final out = Vector2(booth.x, booth.y + 200);

      expect(furnished.resolve(from: inside, to: out), equals(out));
    });
  });

  group('nearestFreePoint', () {
    test('leaves an already-legal point alone', () {
      final at = Vector2(spawnCenterX, spawnCenterY - 100);

      expect(furnished.nearestFreePoint(at.x, at.y), equals(at));
    });

    test('walks a bean out of the credit pillar', () {
      final rescued = empty.nearestFreePoint(
        WorldLayout.pillarX,
        WorldLayout.pillarY,
      );

      expect(empty.isFree(rescued.x, rescued.y), isTrue);
    });

    test('walks a bean out of a booth', () {
      final rescued = furnished.nearestFreePoint(booth.x, booth.y);

      expect(furnished.isFree(rescued.x, rescued.y), isTrue);
    });

    test('falls back to the atrium when there is nowhere near', () {
      final nowhere = empty.nearestFreePoint(-5000, -5000);

      expect(nowhere, equals(Vector2(spawnCenterX, spawnCenterY)));
    });
  });
}
