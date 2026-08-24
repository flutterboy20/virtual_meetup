import 'dart:math';

import 'package:loadtest/loadtest.dart';
import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  Wanderer newWanderer({int seed = 1}) => Wanderer(random: Random(seed));

  /// Runs [seconds] of walking at the client's send rate.
  void walk(Wanderer wanderer, double seconds) {
    for (var i = 0; i < (seconds * 10).round(); i++) {
      wanderer.update(0.1);
    }
  }

  group('placement', () {
    test('starts inside the world', () {
      for (var seed = 0; seed < 50; seed++) {
        final wanderer = newWanderer(seed: seed);

        expect(wanderer.x, inInclusiveRange(0, worldWidth));
        expect(wanderer.y, inInclusiveRange(0, worldHeight));
      }
    });

    test('aims somewhere inside the world', () {
      for (var seed = 0; seed < 50; seed++) {
        final target = newWanderer(seed: seed).target;

        expect(target.x, inInclusiveRange(0, worldWidth));
        expect(target.y, inInclusiveRange(0, worldHeight));
      }
    });

    test('different seeds start in different places', () {
      final first = newWanderer();
      final second = newWanderer(seed: 2);

      expect(first.x, isNot(equals(second.x)));
    });

    test('the same seed replays exactly', () {
      // A load run that cannot be repeated is an anecdote, not a measurement.
      final first = newWanderer(seed: 7);
      final second = newWanderer(seed: 7);
      walk(first, 20);
      walk(second, 20);

      expect(first.x, equals(second.x));
      expect(first.y, equals(second.y));
    });
  });

  group('walking, not teleporting', () {
    test('never moves further in one step than its speed allows', () {
      final wanderer = newWanderer();

      for (var i = 0; i < 600; i++) {
        final fromX = wanderer.x;
        final fromY = wanderer.y;
        wanderer.update(0.1);
        final moved = sqrt(
          pow(wanderer.x - fromX, 2) + pow(wanderer.y - fromY, 2),
        );

        // A bot that jumped across the map every tick would thrash the
        // interest grid and hand back numbers describing a world nobody is
        // going to build.
        expect(moved, lessThanOrEqualTo(wanderer.speed * 0.1 + 0.001));
      }
    });

    test('stays inside the world for a long run', () {
      final wanderer = newWanderer();

      walk(wanderer, 300);

      expect(wanderer.x, inInclusiveRange(0, worldWidth));
      expect(wanderer.y, inInclusiveRange(0, worldHeight));
    });

    test('actually gets somewhere', () {
      final wanderer = newWanderer();
      final startX = wanderer.x;
      final startY = wanderer.y;

      walk(wanderer, 10);

      final travelled = sqrt(
        pow(wanderer.x - startX, 2) + pow(wanderer.y - startY, 2),
      );
      expect(travelled, greaterThan(50));
    });

    test('heads towards its target rather than away', () {
      final wanderer = newWanderer();
      final target = wanderer.target;
      double distanceToTarget() => sqrt(
        pow(wanderer.x - target.x, 2) + pow(wanderer.y - target.y, 2),
      );
      final before = distanceToTarget();

      wanderer.update(0.1);

      expect(distanceToTarget(), lessThan(before));
    });

    test('picks a new target on arriving', () {
      final wanderer = newWanderer();
      final first = wanderer.target;

      // Long enough to cross the world diagonal several times over.
      walk(wanderer, 60);

      expect(wanderer.target, isNot(equals(first)));
    });

    test('stands still for a while after arriving', () {
      // One long step lands it on the target; the next starts the pause.
      final wanderer = Wanderer(random: Random(3), speed: 2000)
        ..update(1)
        ..update(0.01);
      final restingX = wanderer.x;

      wanderer.update(0.1);

      expect(wanderer.isPaused, isTrue);
      expect(wanderer.x, equals(restingX));
    });
  });

  group('the crowd', () {
    test('bots walk at different speeds', () {
      // 200 bots moving in lockstep is not a crowd, it is one organism, and
      // it makes the grid load look far more uniform than it will be.
      final speeds = {
        for (var seed = 0; seed < 20; seed++) newWanderer(seed: seed).speed,
      };

      expect(speeds.length, greaterThan(15));
    });

    test('nobody walks backwards or stands still forever', () {
      for (var seed = 0; seed < 20; seed++) {
        expect(newWanderer(seed: seed).speed, greaterThan(0));
      }
    });

    test('bots spread out rather than piling up', () {
      final wanderers = [
        for (var seed = 0; seed < 40; seed++) newWanderer(seed: seed),
      ];
      for (final wanderer in wanderers) {
        walk(wanderer, 30);
      }

      // Distinct 100-unit buckets: a crowd, not a queue.
      final buckets = wanderers
          .map((w) => '${(w.x / 100).floor()},${(w.y / 100).floor()}')
          .toSet();
      expect(buckets.length, greaterThan(10));
    });
  });

  group('the cross', () {
    test('never starts outside the building', () {
      // Half the world's bounding box is not floor. A bot standing in the
      // void would occupy an interest cell no real player can ever be in,
      // which quietly flatters the culling numbers.
      for (var seed = 0; seed < 200; seed++) {
        final wanderer = newWanderer(seed: seed);

        expect(isOnFloor(wanderer.x, wanderer.y), isTrue);
      }
    });

    test('never aims outside the building', () {
      for (var seed = 0; seed < 200; seed++) {
        final target = newWanderer(seed: seed).target;

        expect(isOnFloor(target.x, target.y), isTrue);
      }
    });

    test('walks to somewhere on the floor and picks another', () {
      final wanderer = newWanderer(seed: 5);

      for (var i = 0; i < 40; i++) {
        walk(wanderer, 20);
        expect(isOnFloor(wanderer.target.x, wanderer.target.y), isTrue);
      }
    });
  });

  group('clustering', () {
    Wanderer clustered({int seed = 1, double radius = 200}) =>
        Wanderer(random: Random(seed), clusterRadius: radius);

    test('stays near the atrium', () {
      for (var seed = 0; seed < 100; seed++) {
        final wanderer = clustered(seed: seed);
        final dx = wanderer.x - spawnCenterX;
        final dy = wanderer.y - spawnCenterY;

        expect(sqrt(dx * dx + dy * dy), lessThanOrEqualTo(200));
        expect(isOnFloor(wanderer.x, wanderer.y), isTrue);
      }
    });

    test('keeps aiming inside the cluster while it walks', () {
      final wanderer = clustered(seed: 3);

      for (var i = 0; i < 30; i++) {
        walk(wanderer, 10);
        final dx = wanderer.target.x - spawnCenterX;
        final dy = wanderer.target.y - spawnCenterY;
        expect(sqrt(dx * dx + dy * dy), lessThanOrEqualTo(200));
      }
    });

    test('an impossible cluster still produces a walking bot', () {
      // A radius so small that rejection sampling could fail: the bot ends up
      // on the spawn point rather than the run dying.
      final wanderer = Wanderer(random: Random(1), clusterRadius: 0.0001);

      expect(isOnFloor(wanderer.x, wanderer.y), isTrue);
    });
  });
}
