import 'dart:math';

import 'package:loadtest/loadtest.dart';
import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

/// A swarm that never connects to anything, for testing the share maths.
Swarm swarmWith({required double surferShare, int count = 200}) => Swarm(
  url: Uri.parse('ws://127.0.0.1:1/ws'),
  count: count,
  surferShare: surferShare,
  random: Random(1),
);

void main() {
  group('the surfer share', () {
    test('nobody surfs by default', () {
      final swarm = swarmWith(surferShare: 0);

      expect(swarm.surferShare, isZero);
      expect(
        List.generate(200, swarm.surfsAt).any((surfs) => surfs),
        isFalse,
      );
    });

    test('half the swarm at 0.5', () {
      final swarm = swarmWith(surferShare: 0.5);

      final surfers = List.generate(200, swarm.surfsAt).where((s) => s).length;

      expect(surfers, equals(100));
    });

    test('everybody at 1', () {
      final swarm = swarmWith(surferShare: 1);

      expect(List.generate(200, swarm.surfsAt).every((s) => s), isTrue);
    });

    test('the split is deterministic for a given share', () {
      // A load number you cannot repeat is not a measurement — the same
      // reason the map split is round-robin rather than random.
      final first = List.generate(200, swarmWith(surferShare: 0.3).surfsAt);
      final second = List.generate(200, swarmWith(surferShare: 0.3).surfsAt);

      expect(first, equals(second));
    });

    test('surfers are spread through the swarm, not bunched at the front', () {
      final swarm = swarmWith(surferShare: 0.5);

      // Both halves of a 200-bot run carry surfers, so a clustered run does
      // not put all of them in one corner.
      expect(
        List.generate(100, swarm.surfsAt).where((s) => s).length,
        equals(50),
      );
      expect(
        List.generate(
          100,
          (i) => swarm.surfsAt(100 + i),
        ).where((s) => s).length,
        equals(50),
      );
    });
  });

  group('a surfing bot', () {
    Bot surfer({bool surfs = true}) => Bot(
      url: Uri.parse('ws://127.0.0.1:1/ws'),
      index: 0,
      random: Random(1),
      spec: MapSpec.beach,
      surfs: surfs,
    );

    test('starts without a board until it has joined', () {
      expect(surfer().hasBoard, isFalse);
    });

    test('a bot with no board never sends one', () {
      final stats = SwarmStats();
      final bot = surfer(surfs: false);

      // No socket, so the step is a no-op past the wander — which is exactly
      // what has to stay true for a non-surfer.
      for (var i = 0; i < 2000; i++) {
        bot.step(0.1, stats);
      }

      expect(stats.boardsSent, isZero);
      expect(bot.hasBoard, isFalse);
    });

    test('the toggle window is a range, not a constant', () {
      // 200 bots flipping in lockstep would manufacture a spike the real
      // world never produces.
      expect(
        Bot.defaultMinimumToggleSeconds,
        lessThan(Bot.defaultMaximumToggleSeconds),
      );
      expect(Bot.defaultMinimumToggleSeconds, greaterThanOrEqualTo(30));
      expect(Bot.defaultMaximumToggleSeconds, lessThanOrEqualTo(90));
    });
  });

  group('the flood override', () {
    test('forces a fixed toggle gap when it is given', () {
      final bot = Bot(
        url: Uri.parse('ws://127.0.0.1:1/ws'),
        index: 0,
        random: Random(1),
        surfs: true,
        toggleSeconds: 0.25,
      );

      expect(bot.minimumToggle, equals(0.25));
      expect(bot.maximumToggle, equals(0.25));
    });

    test('the jittered default is what a run gets without it', () {
      final swarm = swarmWith(surferShare: 1);

      expect(swarm.surfToggleSeconds, isNull);
    });
  });

  group('the summary line', () {
    test('says nothing about boards when there are none', () {
      final stats = SwarmStats()..connected = 10;

      expect(
        stats.summary(const Duration(seconds: 10)),
        isNot(contains('boards')),
      );
    });

    test('reports them when there are', () {
      final stats = SwarmStats()
        ..connected = 10
        ..boardsSent = 7;

      expect(
        stats.summary(const Duration(seconds: 10)),
        contains('boards=7'),
      );
    });
  });
}
