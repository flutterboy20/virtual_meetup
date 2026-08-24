import 'dart:io';
import 'dart:ui';

import 'package:client/game/collision.dart';
import 'package:client/game/furniture_component.dart';
import 'package:client/game/world_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

void main() {
  group('the rename', () {
    test('the zone is the food court, by id and by label', () {
      // Safe because the zone id is read in exactly one place — the `byId`
      // lookup in `world_map.dart`. Nothing persists it and the server never
      // branches on it.
      expect(WorldZone.foodCourt.id, equals('foodCourt'));
      expect(WorldZone.foodCourt.label, equals('Food Court'));
      expect(WorldZone.fromId('foodCourt'), equals(WorldZone.foodCourt));
      expect(WorldZone.fromId('chaiYard'), isNull);
    });

    test('the conference still has seven zones', () {
      expect(MapSpec.conference.zones, hasLength(7));
      expect(MapSpec.conference.zones, contains(WorldZone.foodCourt));
    });

    test('nothing named chai survives in client, protocol or server', () {
      final offenders = <String>[];
      for (final root in const [
        '../client/lib',
        '../protocol/lib',
        '../server/lib',
      ]) {
        final directory = Directory(root);
        if (!directory.existsSync()) continue;
        for (final entity in directory.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.readAsStringSync().toLowerCase().contains('chai')) {
            offenders.add(entity.path);
          }
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('every footprint kept its coordinates', () {
    // This is the review of the rename. New art on top of old rectangles is a
    // rename; new art on top of *moved* rectangles is a redesign wearing one,
    // and the numbers below are the Phase 9 numbers unchanged.
    test('the counter, the awning, the cart and the stools have not moved', () {
      expect(
        WorldLayout.foodCounter,
        equals(const WorldRect(58, 470, 132, 706)),
      );
      expect(
        WorldLayout.courtAwning,
        equals(const WorldRect(44, 448, 200, 728)),
      );
      expect(
        WorldLayout.snackCart,
        equals(const WorldRect(292, 452, 404, 502)),
      );
      expect(WorldLayout.courtStools, hasLength(4));
      expect(WorldLayout.courtStools.first.x, equals(178));
      expect(WorldLayout.courtStools.first.y, equals(512));
      expect(WorldLayout.courtStools.last.y, equals(674));
    });

    test('the crowd glow has not moved either', () {
      expect(WorldLayout.courtGlowX, equals(268));
      expect(WorldLayout.courtGlowY, equals(600));
      expect(WorldLayout.courtGlowRadius, equals(68));
      expect(
        WorldZone.at(WorldLayout.courtGlowX, WorldLayout.courtGlowY),
        equals(WorldZone.foodCourt),
      );
    });

    test('the three stall bays all sit on the counter, and none collide', () {
      // Drawn but not collided: the bays stand on the counter, which is
      // already solid, and a second obstacle inside the first is a second
      // thing to keep in sync.
      final collision = WorldCollision(ConferenceMap.empty);
      for (var bay = 0; bay < 3; bay++) {
        final y = WorldLayout.tawaY + bay * WorldLayout.bayPitch;
        expect(
          WorldLayout.foodCounter.contains(WorldLayout.tawaX, y),
          isTrue,
          reason: 'stall bay $bay hangs off the counter at y=$y',
        );
        // Already solid because the counter is, not because the bay is.
        expect(collision.isFree(WorldLayout.tawaX, y), isFalse);
      }
    });

    test('the lane past the counter is still walkable', () {
      final collision = WorldCollision(ConferenceMap.empty);
      for (var y = 470.0; y < 706; y += 6) {
        expect(
          collision.isFree(152, y),
          isTrue,
          reason: 'the lane past the food counter is blocked at y=$y',
        );
      }
    });
  });

  group('the new art', () {
    test('the food court records into the furniture picture', () async {
      final furniture = FurnitureComponent(layout: ConferenceMap.empty);
      await furniture.onLoad();

      final recorder = PictureRecorder();
      furniture.render(Canvas(recorder));
      recorder.endRecording().dispose();

      furniture.onRemove();
    });

    test('it is still static art, with no component behind it', () {
      // Everything in this room is recorded once. The only live things on
      // this map are the water, the crowd glow, the string lights and the
      // stage screen — a display list is a recording.
      final source = File('lib/game/zone_props.dart').readAsStringSync();
      expect(source, contains('paintFoodCourt'));
      expect(source, isNot(contains('paintChaiYard')));
    });
  });
}
