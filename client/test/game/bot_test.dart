import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/beach_layout.dart';
import 'package:client/game/beach_map.dart';
import 'package:client/game/bot_brain.dart';
import 'package:client/game/bot_component.dart';
import 'package:client/game/collision.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/game/nametag_layer.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// A brain with the dice pinned, so timings are the test's and not chance's.
BotBrain _brain(BotSpec spec) => BotBrain(spec: spec, random: math.Random(7));

/// Every point a bot's life visits: where it starts, and every waypoint.
Iterable<({double x, double y})> _placesOf(BotSpec spec) sync* {
  yield (x: spec.x, y: spec.y);
  yield* spec.waypoints;
}

void main() {
  // `testWithGame` runs the loop, and `ConferenceGame.onLoad` reaches for
  // `SchedulerBinding.instance` to read frame timings.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('where the bots stand', () {
    final maps = <String, GameMap>{
      'conference': ConferenceMap.empty,
      'beach': const BeachMap(),
    };

    for (final entry in maps.entries) {
      final name = entry.key;
      final map = entry.value;

      test('every $name bot spawns and walks on walkable floor', () {
        // The failure this catches is a bean placed inside a desk, in a wall,
        // or off the map entirely — which on screen is a bean standing in the
        // void, and is the single most obvious thing a player would notice.
        final collision = WorldCollision(map);
        expect(map.bots, isNotEmpty, reason: '$name has no bots at all');

        for (final spec in map.bots) {
          for (final at in _placesOf(spec)) {
            expect(
              map.spec.isOnFloor(at.x, at.y),
              isTrue,
              reason: 'a $name bot stands off the floor at ${at.x},${at.y}',
            );
            expect(
              collision.isFree(at.x, at.y),
              isTrue,
              reason: 'a $name bot stands inside furniture at ${at.x},${at.y}',
            );
          }
        }
      });

      test('no $name bot stands on the spawn ring', () {
        // A bean materialising on top of one would be somebody's first frame
        // spent inside scenery.
        final spec = map.spec;
        for (final bot in map.bots) {
          for (final at in _placesOf(bot)) {
            final dx = at.x - spec.spawnCenterX;
            final dy = at.y - spec.spawnCenterY;
            final distance = math.sqrt(dx * dx + dy * dy);
            expect(
              (distance - spec.spawnRingRadius).abs(),
              greaterThan(24),
              reason: 'a $name bot is on the spawn ring at ${at.x},${at.y}',
            );
          }
        }
      });

      test('every $name patrol has somewhere to go', () {
        for (final bot in map.bots) {
          if (bot.behaviour == BotBehaviour.idle) {
            expect(bot.waypoints, isEmpty);
          } else {
            expect(
              bot.waypoints.length,
              greaterThanOrEqualTo(2),
              reason: 'a walking bot with one waypoint never walks',
            );
          }
        }
      });
    }

    test('the roster is the size the phase says it is', () {
      // Fourteen, down from twenty-one: the hall lost three of its seven, and
      // the four who used to stand in the sponsor aisle are now placed from
      // the booth list instead of written down here.
      expect(ConferenceMap.empty.bots, hasLength(14));
      expect(const BeachMap().bots, hasLength(6));
    });

    test('everybody has a name, and nobody admits to being scenery', () {
      for (final map in maps.values) {
        for (final bot in map.bots) {
          expect(bot.name.trim(), isNotEmpty, reason: 'a nameless bean');
          // The names are the whole reason these beans read as a crowd. One
          // that says "bot" undoes it in a single glance.
          expect(bot.name.toLowerCase(), isNot(contains('bot')));
        }
      }
    });

    test('no two beans in one room answer to the same name', () {
      for (final entry in maps.entries) {
        final names = entry.value.bots.map((bot) => bot.name).toSet();
        expect(
          names,
          hasLength(entry.value.bots.length),
          reason: 'two ${entry.key} beans share a name',
        );
      }
    });

    test('the swim bots are the ones whose loop is actually in water', () {
      for (final map in maps.values) {
        for (final bot in map.bots) {
          if (bot.behaviour != BotBehaviour.swim) continue;
          expect(
            bot.waypoints.any((at) => map.isWater(at.x, at.y)),
            isTrue,
            reason: 'a swim bot never gets wet',
          );
        }
      }
    });
  });

  group('BotBrain', () {
    test('an idle bot never moves', () {
      final brain = _brain(
        ConferenceBots.idle(100, 100, color: 0, name: 'Test Bean'),
      );
      final out = Vector2.zero();

      for (var i = 0; i < 600; i++) {
        brain.steer(1 / 60, Vector2(100, 100), out);
        expect(out.isZero(), isTrue);
      }
      expect(brain.target, isNull);
    });

    test('a patrol visits its waypoints in order and loops', () {
      final brain = _brain(
        ConferenceBots.patrol(
          const [(x: 0, y: 0), (x: 100, y: 0), (x: 100, y: 100)],
          color: 0,
          name: 'Test Bean',
        ),
      );
      final at = Vector2.zero();
      final out = Vector2.zero();
      final visited = <int>[];

      for (var i = 0; i < 60 * 60; i++) {
        final before = brain.targetIndex;
        brain.steer(1 / 60, at, out);
        at.add(out * (1 / 60));
        if (brain.targetIndex != before) visited.add(before);
      }

      expect(
        visited.take(6),
        equals([0, 1, 2, 0, 1, 2]),
        reason: 'a patrol has to loop, not ping-pong',
      );
    });

    test('it pauses on arrival rather than turning on a sixpence', () {
      final brain = _brain(
        ConferenceBots.patrol(
          const [(x: 0, y: 0), (x: 40, y: 0)],
          color: 0,
          name: 'Test Bean',
        ),
      );
      final out = Vector2.zero();

      // Standing right on the first waypoint: arriving flips the target and
      // starts the dwell.
      brain.steer(1 / 60, Vector2.zero(), out);
      expect(brain.isDwelling, isTrue);
      expect(out.isZero(), isTrue);

      brain.steer(1 / 60, Vector2.zero(), out);
      expect(out.isZero(), isTrue, reason: 'it walked off mid-pause');
    });

    test('it walks at bot pace, not at player pace', () {
      // A bot moving at a player's top speed reads as another player, and a
      // bot that reads as another player is one somebody tries to talk to.
      final brain = _brain(
        ConferenceBots.patrol(
          const [(x: 0, y: 0), (x: 400, y: 0)],
          color: 0,
          name: 'Test Bean',
        ),
      );
      final out = Vector2.zero();
      // Past the opening dwell: a brain starts paused, so a bot dropped into
      // the world stands still for a beat before setting off rather than
      // striding away the instant the map loads.
      for (var i = 0; i < 60 * 6; i++) {
        brain.steer(1 / 60, Vector2(200, 0), out);
      }

      expect(out.length, closeTo(brain.speed, 1e-6));
      expect(brain.speed, lessThan(ConferenceGame.beanMaxSpeed / 2));
    });

    test('it reacts every 20 to 40 seconds, and never faster', () {
      final brain = _brain(
        ConferenceBots.idle(0, 0, color: 0, name: 'Test Bean'),
      );
      const step = 1 / 60;
      var elapsed = 0.0;
      final gaps = <double>[];
      var since = 0.0;

      for (var i = 0; i < 60 * 300; i++) {
        elapsed += step;
        since += step;
        if (brain.shouldEmote(step)) {
          gaps.add(since);
          since = 0;
        }
      }

      expect(gaps, isNotEmpty);
      expect(elapsed, closeTo(300, 0.1));
      for (final gap in gaps) {
        expect(gap, greaterThanOrEqualTo(brain.minEmoteGap - 0.02));
        expect(gap, lessThanOrEqualTo(brain.maxEmoteGap + 0.02));
      }
      // Nothing like a per-frame reaction: 300 s at 20–40 s apart is 8–15.
      expect(gaps.length, lessThan(16));
    });

    test('it picks a reaction the protocol actually has', () {
      final brain = _brain(
        ConferenceBots.idle(0, 0, color: 0, name: 'Test Bean'),
      );
      for (var i = 0; i < 200; i++) {
        expect(EmoteKind.values, contains(brain.pickEmote()));
      }
    });
  });

  group('BotComponent', () {
    /// A bot on the conference map, always on camera.
    BotComponent botAt(BotSpec spec) => BotComponent(
      brain: _brain(spec),
      map: ConferenceMap.empty,
      isVisible: (_, _) => true,
    );

    test('is stopped by the same collision the player is', () {
      // Aimed straight through the credit pillar from the west. A bot that
      // strolled through it would say, louder than any tutorial, that the
      // walls here are a suggestion.
      final bot = botAt(
        ConferenceBots.patrol(
          const [
            (x: WorldLayout.pillarX - 120, y: WorldLayout.pillarY),
            (x: WorldLayout.pillarX + 120, y: WorldLayout.pillarY),
          ],
          color: 0,
          name: 'Test Bean',
        ),
      );
      final collision = WorldCollision(ConferenceMap.empty);

      for (var i = 0; i < 60 * 20; i++) {
        bot.update(1 / 60);
        expect(
          collision.isFree(bot.position.x, bot.position.y),
          isTrue,
          reason: 'a bot walked into the pillar at ${bot.position}',
        );
      }
    });

    test('a bot off camera costs nothing but the test that says so', () {
      final bot = BotComponent(
        brain: _brain(
          ConferenceBots.patrol(
            const [(x: 700, y: 520), (x: 900, y: 520)],
            color: 0,
            name: 'Test Bean',
          ),
        ),
        map: ConferenceMap.empty,
        isVisible: (_, _) => false,
      );
      final before = bot.position.clone();

      for (var i = 0; i < 600; i++) {
        bot.update(1 / 60);
      }

      expect(bot.position, equals(before));
    });

    test('a swim bot in the water is submerged, and slowed', () {
      final bot = botAt(
        ConferenceBots.patrol(
          const [(x: 800, y: 950), (x: 800, y: 1050)],
          color: 0,
          name: 'Test Bean',
          behaviour: BotBehaviour.swim,
        ),
      );

      for (var i = 0; i < 120; i++) {
        bot.update(1 / 60);
      }

      expect(
        ConferenceMap.empty.isWater(bot.position.x, bot.position.y),
        isTrue,
      );
      expect(bot.swim.submersion, greaterThan(0));
      expect(
        bot.velocity.length,
        lessThan(bot.brain.speed),
        reason: 'a bot crossing the pool at walking pace is visibly cheating',
      );
    });

    test('a bot carries no board', () {
      final bot = botAt(
        ConferenceBots.idle(700, 520, color: 0, name: 'Test Bean'),
      );
      expect(bot.hasBoard, isFalse);
    });
  });

  group('booth staff', () {
    /// The booth list the app actually ships with.
    const sponsors = [
      Sponsor(
        id: 'a',
        name: 'A',
        blurb: '',
        x: 1130,
        y: 478,
        color: Color(0xFF54C5F8),
      ),
      Sponsor(
        id: 'b',
        name: 'B',
        blurb: '',
        x: 1330,
        y: 478,
        color: Color(0xFF7ED9B6),
      ),
      Sponsor(
        id: 'c',
        name: 'C',
        blurb: '',
        x: 1130,
        y: 722,
        color: Color(0xFFF2B33D),
      ),
      Sponsor(
        id: 'd',
        name: 'D',
        blurb: '',
        x: 1330,
        y: 722,
        color: Color(0xFFB78BE8),
      ),
    ];

    test('there is exactly one of them per booth', () {
      final map = ConferenceMap(sponsors);

      expect(map.bots, hasLength(ConferenceBots.roster.length + 4));
    });

    test('each one is at their own booth, not in the aisle', () {
      // The bug this replaces: four staff at fixed coordinates, left standing
      // in a line in an empty aisle because the booths moved in config and
      // they could not follow.
      final staff = ConferenceBots.boothStaff(sponsors);

      for (var i = 0; i < sponsors.length; i++) {
        final booth = sponsors[i].footprint;
        final gap = math.min(
          (staff[i].y - booth.bottom).abs(),
          (staff[i].x - booth.right).abs(),
        );
        expect(
          gap,
          lessThanOrEqualTo(ConferenceBots.staffStandoff),
          reason: 'booth ${sponsors[i].id} has staff nowhere near it',
        );
      }
    });

    test('nobody is stood in front of the logo they are selling', () {
      // A booth's face is the branded band across its top edge — the one part
      // of a booth a walking player actually reads. Staff go behind it or
      // beside it, never on it.
      for (var i = 0; i < sponsors.length; i++) {
        final place = ConferenceBots.staffPlace(sponsors[i]);
        final booth = sponsors[i].footprint;
        final onTheFace =
            place.y < booth.top &&
            place.x > booth.left &&
            place.x < booth.right;

        expect(onTheFace, isFalse, reason: 'staff in front of booth $i');
      }
    });

    test('none of them is standing inside the booth they are working', () {
      final map = ConferenceMap(sponsors);
      final collision = WorldCollision(map);

      for (final bot in ConferenceBots.boothStaff(sponsors)) {
        expect(
          map.spec.isOnFloor(bot.x, bot.y),
          isTrue,
          reason: 'booth staff off the floor at ${bot.x},${bot.y}',
        );
        expect(
          collision.isFree(bot.x, bot.y),
          isTrue,
          reason: 'booth staff inside furniture at ${bot.x},${bot.y}',
        );
      }
    });

    test('a booth list of any length gets named without running out', () {
      final many = [
        for (var i = 0; i < ConferenceBots.staffNames.length * 2 + 1; i++)
          Sponsor(
            id: 's$i',
            name: 'S$i',
            blurb: '',
            x: 1130,
            y: 478,
            color: const Color(0xFF54C5F8),
          ),
      ];

      for (final bot in ConferenceBots.boothStaff(many)) {
        expect(bot.name, isNotEmpty);
      }
    });
  });

  group('bots in the game', () {
    testWithGame<ConferenceGame>(
      'are mounted, but are not people',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();

        expect(game.bots, hasLength(ConferenceMap.empty.bots.length));
        for (final bot in game.bots) {
          expect(bot.isMounted, isTrue);
        }

        // The head count is the server's number and the server has never
        // heard of a bot. A badge reading "22 online" with one person in the
        // room is worse than a badge reading "0".
        expect(game.hud.online.value, isZero);
      },
    );

    testWithGame<ConferenceGame>(
      'introduce themselves when you walk up, and only then',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();
        final tags = game.world.children.whereType<NametagLayer>().single;
        final bot = game.bots.first;

        // Standing across the map from every one of them.
        game.bean.position.setValues(
          WorldLayout.pool.centerX,
          WorldLayout.pool.centerY,
        );
        expect(
          tags.visibleTags().where((tag) => tag.name == bot.brain.spec.name),
          isEmpty,
          reason: 'a name readable from across the map is a label',
        );

        // Now standing next to one.
        game.bean.position.setFrom(bot.position);
        final near = tags.visibleTags().singleWhere(
          (tag) => tag.name == bot.brain.spec.name,
        );

        expect(near.alpha, equals(1));
        expect(near.id, startsWith(NametagLayer.botTagPrefix));
      },
    );

    testWithGame<ConferenceGame>(
      'do not light the gather-here glow',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();
        // Two bots parked right on the glow, and nobody else anywhere near it.
        game.bots[0].position.setValues(
          WorldLayout.courtGlowX,
          WorldLayout.courtGlowY,
        );
        game.bots[1].position.setValues(
          WorldLayout.courtGlowX + 8,
          WorldLayout.courtGlowY,
        );

        for (var i = 0; i < 120; i++) {
          game.update(1 / 60);
        }

        // A glow lit by scenery is a glow that is always on, which is a glow
        // that says nothing.
        expect(game.crowdGlow.glow, lessThan(0.02));
      },
    );

    testWithGame<ConferenceGame>(
      'the pool bot swims when there is somebody there to see it',
      () => ConferenceGame(spawnAngle: 0),
      (game) async {
        await game.ready();
        final swimmer = game.bots.firstWhere(
          (bot) => bot.brain.spec.behaviour == BotBehaviour.swim,
        );

        // Both of them in the pool: the bot to swim, the player so the camera
        // is looking at it — a culled bot skips its whole update, which is
        // the point of culling and worth proving does not break the swimming.
        game.bean.position.setValues(
          WorldLayout.pool.centerX,
          WorldLayout.pool.centerY,
        );
        swimmer.position.setValues(
          WorldLayout.pool.centerX,
          WorldLayout.pool.centerY,
        );
        for (var i = 0; i < 300; i++) {
          game.update(1 / 60);
        }

        // `_swimmers` is a rendering input, not a census: a splash is a
        // picture, not a claim about attendance. Bots belong in it.
        expect(
          game.layout.isWater(swimmer.position.x, swimmer.position.y),
          isTrue,
        );
        expect(swimmer.swim.submersion, greaterThan(0));
      },
    );

    testWithGame<ConferenceGame>(
      'the beach has its own roster and one disco',
      () => ConferenceGame(map: const BeachMap(), spawnAngle: 0),
      (game) async {
        await game.ready();

        expect(game.bots, hasLength(BeachBots.roster.length));
        expect(game.layout.hasDisco, isTrue);
        expect(ConferenceMap.empty.hasDisco, isFalse);
      },
    );
  });
}
