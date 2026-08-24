import 'dart:math';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  PlayerState playerAt(String id, double x, double y) => PlayerState(
    id: id,
    name: id,
    color: 0xFF000000,
    cosmetic: PlayerCosmetic.none,
    x: x,
    y: y,
  );

  /// The obvious implementation, kept as the thing to be correct against.
  ///
  /// The heap is a performance change, so the test that matters is that it
  /// picks the same people a plain sort would.
  List<PlayerState> bySorting(
    List<PlayerState> candidates, {
    required double x,
    required double y,
    required int cap,
    Set<String> known = const {},
  }) {
    double rank(PlayerState player) {
      final dx = player.x - x;
      final dy = player.y - y;
      final distance = dx * dx + dy * dy;
      return known.contains(player.id)
          ? distance * NearestPlayers.incumbentDiscount
          : distance;
    }

    final sorted = List<PlayerState>.of(candidates)
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    return sorted.take(cap).toList(growable: false);
  }

  group('NearestPlayers', () {
    test('hands back a short list untouched', () {
      final selector = NearestPlayers(cap: 40);
      final candidates = [playerAt('a', 0, 0), playerAt('b', 500, 500)];

      final kept = selector.select(
        candidates,
        x: 0,
        y: 0,
        isKnown: (_) => false,
      );

      expect(identical(kept, candidates), isTrue);
    });

    test('keeps the nearest and drops the rest', () {
      final selector = NearestPlayers(cap: 3);
      final candidates = [
        for (var i = 0; i < 10; i++) playerAt('p$i', i * 10, 0),
      ];

      final kept = selector.select(
        candidates,
        x: 0,
        y: 0,
        isKnown: (_) => false,
      );

      expect(kept.map((p) => p.id).toSet(), equals({'p0', 'p1', 'p2'}));
    });

    test('measures distance in both axes, not just one', () {
      final selector = NearestPlayers(cap: 1);

      final kept = selector.select(
        [playerAt('far', 0, 100), playerAt('near', 30, 30)],
        x: 0,
        y: 0,
        isKnown: (_) => false,
      );

      expect(kept.single.id, equals('near'));
    });

    test('an incumbent keeps its place against a marginally closer face', () {
      final selector = NearestPlayers(cap: 1);

      final kept = selector.select(
        [playerAt('incumbent', 100, 0), playerAt('newcomer', 95, 0)],
        x: 0,
        y: 0,
        isKnown: (id) => id == 'incumbent',
      );

      expect(kept.single.id, equals('incumbent'));
    });

    test('an incumbent loses to somebody decisively closer', () {
      final selector = NearestPlayers(cap: 1);

      final kept = selector.select(
        [playerAt('incumbent', 100, 0), playerAt('newcomer', 50, 0)],
        x: 0,
        y: 0,
        isKnown: (id) => id == 'incumbent',
      );

      expect(kept.single.id, equals('newcomer'));
    });

    test('picks exactly who a plain sort would, over random crowds', () {
      // The whole justification for the heap is that it is the same answer,
      // cheaper. A hundred random crowds is the check on that claim.
      final random = Random(7);
      final selector = NearestPlayers(cap: 40);

      for (var run = 0; run < 100; run++) {
        final crowd = [
          for (var i = 0; i < 200; i++)
            playerAt(
              'p$i',
              random.nextDouble() * worldWidth,
              random.nextDouble() * worldHeight,
            ),
        ];
        final known = {
          for (var i = 0; i < 200; i++)
            if (random.nextBool()) 'p$i',
        };
        final me = (x: random.nextDouble() * worldWidth, y: 600.0);

        final kept = selector.select(
          List<PlayerState>.of(crowd),
          x: me.x,
          y: me.y,
          isKnown: known.contains,
        );
        final expected = bySorting(
          crowd,
          x: me.x,
          y: me.y,
          cap: 40,
          known: known,
        );

        expect(
          kept.map((p) => p.id).toSet(),
          equals(expected.map((p) => p.id).toSet()),
          reason: 'run $run',
        );
      }
    });

    test('reusing one selector does not leak the last crowd into the next', () {
      // The buffers are reused on purpose, so this is the failure mode that
      // reuse invites and the reason the test exists.
      final selector = NearestPlayers(cap: 2);
      final first = [
        for (var i = 0; i < 10; i++) playerAt('first$i', i * 10, 0),
      ];
      final second = [
        for (var i = 0; i < 10; i++) playerAt('second$i', i * 10, 0),
      ];

      selector.select(first, x: 0, y: 0, isKnown: (_) => false);
      final kept = selector.select(second, x: 0, y: 0, isKnown: (_) => false);

      expect(kept.map((p) => p.id).toSet(), equals({'second0', 'second1'}));
    });

    test('a cap of nothing is not a crash', () {
      final selector = NearestPlayers(cap: 0);

      expect(
        selector.select(
          [playerAt('a', 0, 0)],
          x: 0,
          y: 0,
          isKnown: (_) => false,
        ),
        hasLength(1),
      );
    });
  });
}
