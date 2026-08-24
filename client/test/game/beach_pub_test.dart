import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:client/game/beach_layout.dart';
import 'package:client/game/beach_map.dart';
import 'package:client/game/collision.dart';
import 'package:client/game/disco_component.dart';
import 'package:client/game/world_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// A world rectangle, as a drawable one.
Rect _rect(WorldRect r) => Rect.fromLTRB(r.left, r.top, r.right, r.bottom);

void main() {
  const beach = BeachMap();

  group('the pub', () {
    test('the middle shack is the pub now', () {
      expect(BeachLayout.shackNames, equals(['JUICE', 'PUB', 'SHOP']));
      expect(
        BeachLayout.shackNames[BeachLayout.pubIndex],
        equals('PUB'),
      );
    });

    test('the dance floor and the booth clear the spawn ring', () {
      // The whole reason the floor is east of the booth rather than south of
      // it: the ring is at (600, 310) with a radius of 80, and a floor
      // directly south of the pub would have been painted under everybody's
      // first frame.
      final spec = beach.spec;
      final ring = Rect.fromCircle(
        center: Offset(spec.spawnCenterX, spec.spawnCenterY),
        radius: spec.spawnRingRadius,
      );

      expect(_rect(BeachLayout.danceFloor).overlaps(ring), isFalse);
      expect(_rect(BeachLayout.djBooth).overlaps(ring), isFalse);
    });

    test('nobody arriving lands on the floor or the booth', () {
      final spec = beach.spec;
      for (var i = 0; i < 360; i++) {
        final angle = i / 360 * 2 * math.pi;
        final x = spec.spawnCenterX + spec.spawnRingRadius * math.cos(angle);
        final y = spec.spawnCenterY + spec.spawnRingRadius * math.sin(angle);
        expect(BeachLayout.danceFloor.contains(x, y), isFalse);
        expect(BeachLayout.djBooth.contains(x, y), isFalse);
      }
    });

    test('neither is solid, and neither sits on a rail post', () {
      // Drawn and not collided, like the awning and the net: the boardwalk is
      // 200 units deep and it is the strip everybody arrives facing, so a
      // solid box in the middle of it would narrow the way in.
      const collision = WorldCollision(beach);
      for (final at in [
        BeachLayout.danceFloor,
        BeachLayout.djBooth,
      ]) {
        expect(collision.isFree(at.centerX, at.centerY), isTrue);
      }

      for (final post in BeachLayout.railPosts) {
        expect(
          BeachLayout.danceFloor.contains(post.x, post.y),
          isFalse,
          reason: 'a rail post stands on the dance floor',
        );
      }
    });

    test('the DJ stands behind the decks, on floor, not in the shack', () {
      const collision = WorldCollision(beach);

      expect(collision.isFree(BeachLayout.djX, BeachLayout.djY), isTrue);
      expect(
        beach.spec.isOnFloor(BeachLayout.djX, BeachLayout.djY),
        isTrue,
      );
      // North of the decks, so the booth is between the DJ and the floor.
      expect(BeachLayout.djY, lessThan(BeachLayout.djBooth.centerY));
    });

    test('the DJ is a bot, not a special case built into the pub', () {
      // Building the bot twice — once specially for the pub — is how two
      // things that should be one drift apart.
      final dj = beach.bots.firstWhere(
        (bot) => bot.x == BeachLayout.djX && bot.y == BeachLayout.djY,
      );
      expect(dj.cosmetic, equals(PlayerCosmetic.headphones));
      expect(dj.waypoints, isEmpty);
    });

    test('the disco turns, and does it without a blur', () {
      final disco = DiscoComponent();
      final before = disco.recordPhase;
      final sweepBefore = disco.sweepPhase;

      for (var i = 0; i < 60; i++) {
        disco.update(1 / 60);
      }

      expect(disco.recordPhase, isNot(equals(before)));
      expect(disco.sweepPhase, isNot(equals(sweepBefore)));
      // The sweep is deliberately slower than the record: a strobe is a
      // headache and, on a phone in a pocket, a battery.
      expect(
        DiscoComponent.sweepRevolutions,
        lessThan(DiscoComponent.recordRevolutions),
      );

      final recorder = PictureRecorder();
      disco.render(Canvas(recorder));
      recorder.endRecording().dispose();
    });

    test('no MaskFilter or blur anywhere in the disco', () {
      // Asserted on the source, because the failure is a real raster cost on
      // CanvasKit that no unit test would ever feel. Flat gradient wedges —
      // the same call `ZoneProps.paintHall` already made for the stage wash.
      final code = File('lib/game/disco_component.dart')
          .readAsLinesSync()
          // Comments only say what the code does; this asserts on what it
          // *is*, and the class doc names `MaskFilter` to say it avoids it.
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('MaskFilter')));
      expect(code, isNot(contains('ImageFilter')));
      expect(code, isNot(contains('saveLayer')));
    });
  });

  group('the bonfire is gone', () {
    test('nothing named bonfire survives in the client', () {
      // Art, obstacle, constants, all of it. A dead constant nobody draws is
      // a thing the next person has to work out is dead.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().toLowerCase().contains('bonfire')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('the obstacle it used to be is out of the collision list', () {
      const collision = WorldCollision(beach);
      // (820, 330) was the fire. It is open sand now.
      expect(collision.isFree(820, 330), isTrue);
    });
  });

  group('the beach glow', () {
    test('there is exactly one, and it is over the dance floor', () {
      // A map gets exactly one gather-here glow: two are two places to stand,
      // which is the opposite of what one is for.
      final glow = beach.crowdGlow;

      expect(glow.x, equals(BeachLayout.danceFloor.centerX));
      expect(glow.y, equals(BeachLayout.danceFloor.centerY));
      expect(
        glow.zone,
        anyOf(WorldZone.beachSand, WorldZone.beachBoardwalk),
      );
      expect(beach.spec.zoneAt(glow.x, glow.y), equals(glow.zone));
    });

    test('it is a place, not a prop — nothing solid stands on it', () {
      const collision = WorldCollision(beach);
      final glow = beach.crowdGlow;

      expect(collision.isFree(glow.x, glow.y), isTrue);
    });
  });

  group('the conference is untouched by any of this', () {
    test('it has no disco and its glow has not moved', () {
      expect(ConferenceMap.empty.hasDisco, isFalse);
      expect(
        ConferenceMap.empty.crowdGlow.x,
        equals(WorldLayout.courtGlowX),
      );
      expect(
        ConferenceMap.empty.crowdGlow.y,
        equals(WorldLayout.courtGlowY),
      );
    });
  });
}
