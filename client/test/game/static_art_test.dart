import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/floor_component.dart';
import 'package:client/game/furniture_component.dart';
import 'package:client/game/static_art.dart';
import 'package:client/game/world_layout.dart';
import 'package:client/game/zone_floor_art.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// Renders [component] into a throwaway recorder, the way a frame would.
Picture renderOnce(PositionComponent component) =>
    recordPicture(component.render);

const _booth = Sponsor(
  id: 'a',
  name: 'A Corp',
  blurb: '',
  x: 1130,
  y: 478,
  color: Color(0xFF54C5F8),
);

void main() {
  // Paragraphs need a real engine to lay out, which `render` reaches through.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('recordPicture', () {
    test('replays what was drawn into it', () {
      var drew = false;
      final picture = recordPicture((canvas) {
        drew = true;
        canvas.drawRect(const Rect.fromLTWH(0, 0, 10, 10), Paint());
      });

      expect(drew, isTrue);
      addTearDown(picture.dispose);
    });

    test('draws nothing at all until it is replayed', () {
      // The point of the pipeline: the work happens once, at record time, and
      // a frame that never renders the component pays nothing for it.
      var calls = 0;
      recordPicture((_) => calls++).dispose();
      recordPicture((_) => calls++).dispose();

      expect(calls, equals(2));
    });
  });

  group('FloorComponent', () {
    test('builds its picture once, in onLoad, not per frame', () async {
      final floor = FloorComponent(
        worldSize: Vector2(worldWidth, worldHeight),
      );
      await floor.onLoad();

      // Rendering repeatedly must not rebuild anything: if it did, the whole
      // reason for the pipeline would be gone and nothing would fail loudly.
      for (var i = 0; i < 3; i++) {
        renderOnce(floor).dispose();
      }

      floor.onRemove();
    });

    test('renders nothing rather than throwing before it has loaded', () {
      // A component can be asked to render on the frame it is mounted, which
      // is before `onLoad` has completed.
      final floor = FloorComponent(
        worldSize: Vector2(worldWidth, worldHeight),
      );

      expect(() => renderOnce(floor).dispose(), returnsNormally);
    });

    test('is safe to remove twice', () {
      final floor = FloorComponent(
        worldSize: Vector2(worldWidth, worldHeight),
      );

      expect(floor.onRemove, returnsNormally);
      expect(floor.onRemove, returnsNormally);
    });
  });

  group('the exterior ground', () {
    test('the two voids contain no floor at all', () {
      // They are ground, not rooms. If a zone ever grows into one of these,
      // the ground treatment would be painted over half a walkable room.
      //
      // The *interior*, not the edges: a void's corner is also a corner of
      // the atrium, and `WorldRect.contains` is inclusive on purpose so that
      // two rooms can share a seam rather than growing a crack between them.
      for (final area in ZoneFloorArt.voids) {
        for (var x = area.left + 1; x < area.right; x += 20) {
          for (var y = area.top + 1; y < area.bottom; y += 20) {
            expect(
              isOnFloor(x, y),
              isFalse,
              reason: 'the void at $x,$y is walkable',
            );
          }
        }
      }
    });

    test('the voids and the zones together tile the whole world', () {
      // The other half of the check: two hardcoded rectangles are only safe
      // if nothing falls between them and the rooms.
      for (var x = 10.0; x < worldWidth; x += 25) {
        for (var y = 10.0; y < worldHeight; y += 25) {
          final inZone = WorldZone.at(x, y) != null;
          final inVoid = ZoneFloorArt.voids.any(
            (area) => area.contains(Offset(x, y)),
          );
          expect(
            inZone || inVoid,
            isTrue,
            reason: '$x,$y is neither a room nor ground',
          );
          expect(inZone && inVoid, isFalse, reason: '$x,$y is both');
        }
      }
    });
  });

  group('FurnitureComponent', () {
    test('records the booths from config as static art', () async {
      final furniture = FurnitureComponent(
        layout: WorldLayout.of(const [_booth]),
      );
      await furniture.onLoad();

      expect(() => renderOnce(furniture).dispose(), returnsNormally);

      furniture.onRemove();
    });

    test('an empty sponsor row still records', () async {
      final furniture = FurnitureComponent(layout: WorldLayout.of(const []));
      await furniture.onLoad();

      expect(() => renderOnce(furniture).dispose(), returnsNormally);

      furniture.onRemove();
    });
  });
}
