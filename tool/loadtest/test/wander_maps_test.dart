import 'dart:math';

import 'package:loadtest/loadtest.dart';
import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  /// Runs [seconds] of walking at the client's send rate.
  void walk(Wanderer wanderer, double seconds) {
    for (var i = 0; i < (seconds * 10).round(); i++) {
      wanderer.update(0.1);
    }
  }

  // The existing wander tests are the conference's. These are the same
  // questions asked of **every** spec, which is the point of `--map`: a load
  // run against the beach that quietly walked the conference's floor plan
  // would put every bot in the sea and measure nothing anybody will ever do.
  for (final spec in MapSpec.values) {
    group('wandering the ${spec.id.id}', () {
      Wanderer wanderer({int seed = 1, double? cluster}) =>
          Wanderer(random: Random(seed), spec: spec, clusterRadius: cluster);

      test('starts inside the map', () {
        for (var seed = 0; seed < 50; seed++) {
          final bot = wanderer(seed: seed);

          expect(bot.x, inInclusiveRange(0, spec.width));
          expect(bot.y, inInclusiveRange(0, spec.height));
        }
      });

      test('never starts off the floor', () {
        // A bot standing in a void would occupy an interest cell no real
        // player can ever be in, which quietly flatters the culling numbers.
        for (var seed = 0; seed < 200; seed++) {
          final bot = wanderer(seed: seed);

          expect(spec.isOnFloor(bot.x, bot.y), isTrue);
        }
      });

      test('never aims off the floor', () {
        for (var seed = 0; seed < 200; seed++) {
          final target = wanderer(seed: seed).target;

          expect(spec.isOnFloor(target.x, target.y), isTrue);
        }
      });

      test('stays inside the map while it walks', () {
        final bot = wanderer(seed: 5);

        for (var i = 0; i < 40; i++) {
          walk(bot, 20);
          expect(bot.x, inInclusiveRange(0, spec.width));
          expect(bot.y, inInclusiveRange(0, spec.height));
          expect(spec.isOnFloor(bot.target.x, bot.target.y), isTrue);
        }
      });

      test('a clustered bot stays near this map own spawn point', () {
        for (var seed = 0; seed < 100; seed++) {
          final bot = wanderer(seed: seed, cluster: 150);
          final dx = bot.x - spec.spawnCenterX;
          final dy = bot.y - spec.spawnCenterY;

          expect(sqrt(dx * dx + dy * dy), lessThanOrEqualTo(150));
          expect(spec.isOnFloor(bot.x, bot.y), isTrue);
        }
      });

      test('an impossible cluster still produces a walking bot', () {
        final bot = wanderer(cluster: 0.0001);

        expect(spec.isOnFloor(bot.x, bot.y), isTrue);
      });
    });
  }

  group('a swarm split across maps', () {
    final url = Uri.parse('ws://localhost:8080/ws');

    test('defaults to the conference, and leaves the URL alone', () {
      // A single-map run has to open exactly the URL it opened before Phase
      // 10, or every existing script quietly changes what it measures.
      final swarm = Swarm(url: url, count: 4, random: Random(1));

      expect(swarm.maps, equals([MapId.conference]));
      expect(swarm.urlFor(0), equals(url));
      expect(swarm.urlFor(3), equals(url));
    });

    test('puts the map in the query string when one is named', () {
      final swarm = Swarm(
        url: url,
        count: 4,
        maps: const [MapId.beach],
        random: Random(1),
      );

      expect(swarm.urlFor(0).queryParameters['map'], equals('beach'));
    });

    test('splits evenly and repeatably across two maps', () {
      // Round-robin rather than random: a random split of 200 bots lands
      // anywhere from 85 to 115 a side, and a load number you cannot repeat
      // is not a measurement.
      final swarm = Swarm(
        url: url,
        count: 10,
        maps: const [MapId.conference, MapId.beach],
        random: Random(1),
      );

      final counts = <MapId, int>{};
      for (var i = 0; i < 10; i++) {
        counts.update(swarm.mapFor(i), (n) => n + 1, ifAbsent: () => 1);
      }

      expect(counts[MapId.conference], equals(5));
      expect(counts[MapId.beach], equals(5));
      expect(swarm.urlFor(1).queryParameters['map'], equals('beach'));
      expect(
        swarm.urlFor(0).queryParameters['map'],
        equals('conference'),
      );
    });

    test('an empty map list is the conference, not a crash', () {
      final swarm = Swarm(
        url: url,
        count: 2,
        maps: const [],
        random: Random(1),
      );

      expect(swarm.maps, equals([MapId.conference]));
    });

    test('a bot walks the map it was sent to', () {
      final swarm = Swarm(
        url: url,
        count: 4,
        maps: const [MapId.conference, MapId.beach],
        random: Random(1),
      );

      expect(swarm.mapFor(1), equals(MapId.beach));
      expect(MapSpec.of(swarm.mapFor(1)), equals(MapSpec.beach));
    });
  });
}
