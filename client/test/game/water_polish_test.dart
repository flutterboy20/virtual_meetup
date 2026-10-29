import 'dart:math' as math;
import 'dart:ui';

import 'package:client/game/beach_map.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/game/water_component.dart';
import 'package:client/game/water_lod.dart';
import 'package:client/game/world_layout.dart';
import 'package:client/game/zone_props.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts every call made on it.
class _CountingCanvas implements Canvas {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    return null;
  }
}

final ({Offset centre, double radius}) _surface = ConferenceMap.empty.fountain;

FountainShimmer _shimmer({
  WaterDetail detail = WaterDetail.full,
  bool still = false,
  Rect? camera,
}) => FountainShimmer(
  water: WaterComponent(swimmers: () => const [])..lod.force(detail),
  surface: _surface,
  visibleWorldRect: camera == null ? null : () => camera,
  reduceMotion: () => still,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('twinkle', () {
    final phases = [for (var i = 0; i < 720; i++) i * 2 * math.pi / 720];

    test('stays between dark and full', () {
      for (final phase in phases) {
        expect(WaterComponent.twinkle(phase, 0.3), inInclusiveRange(0, 1));
      }
    });

    test('is dark about half the time', () {
      // Only some glints lit at once is what makes it read as caustics.
      final dark = phases
          .where((phase) => WaterComponent.twinkle(phase / 2.3, 0.3) == 0)
          .length;

      expect(dark / phases.length, closeTo(0.5, 0.02));
    });
  });

  group('the caustic glints', () {
    final water = WaterComponent(swimmers: () => const []);
    const pool = Rect.fromLTRB(690, 900, 910, 1090);

    test('ride on the crests: never more glints than crests', () {
      final lattice = water.crestLattice(pool, pool);

      for (var phase = 0.0; phase < 6.3; phase += 0.3) {
        final glints = WaterComponent.causticGlints(lattice, phase);

        expect(glints.length, lessThanOrEqualTo(lattice.length));
        for (final glint in glints) {
          expect(glint.size, lessThanOrEqualTo(WaterComponent.maxGlint));
        }
      }
    });

    test('are gone at the flat tier', () {
      water.lod.force(WaterDetail.flat);
      final lattice = water.crestLattice(pool, pool);

      expect(WaterComponent.causticGlints(lattice, 1), isEmpty);
      water.lod.force(WaterDetail.full);
    });

    test('are the conference pool only: the beach is not polished', () {
      expect(ConferenceMap.empty.polishedWater, isTrue);
      expect(const BeachMap().polishedWater, isFalse);
      expect(const BeachMap().fountain, isNull);
    });
  });

  group('the fountain shimmer', () {
    test('sits on the water inside the basin', () {
      expect(_surface.centre, equals(ZoneProps.fountainWater));
      expect(
        _surface.radius,
        equals(WorldLayout.fountain.radius - ZoneProps.fountainWall),
      );
    });

    test('every glint stays on the water', () {
      for (var phase = 0.0; phase < 6.3; phase += 0.1) {
        for (final glint in FountainShimmer.glints(_surface, phase)) {
          expect(
            (glint.at - _surface.centre).distance + glint.size,
            lessThanOrEqualTo(_surface.radius),
          );
        }
      }
    });

    test('draws at full detail', () {
      final canvas = _CountingCanvas();

      _shimmer().render(canvas);

      expect(canvas.calls, greaterThan(0));
    });

    test('draws nothing at the flat tier', () {
      final canvas = _CountingCanvas();

      _shimmer(detail: WaterDetail.flat).render(canvas);

      expect(canvas.calls, isZero);
    });

    test('draws nothing under reduce-motion', () {
      final canvas = _CountingCanvas();

      _shimmer(still: true).render(canvas);

      expect(canvas.calls, isZero);
    });

    test('draws nothing off camera', () {
      final canvas = _CountingCanvas();

      _shimmer(camera: const Rect.fromLTWH(1200, 0, 300, 300)).render(canvas);

      expect(canvas.calls, isZero);
    });
  });

  testWithGame<ConferenceGame>(
    'the fountain shimmers over its basin and under the beans',
    ConferenceGame.new,
    (game) async {
      await game.ready();
      final shimmer = game.world.children.whereType<FountainShimmer>().single;

      expect(shimmer.priority, greaterThan(game.furniture.priority));
      expect(shimmer.priority, lessThan(0));
      expect(identical(shimmer.water, game.water), isTrue);
    },
  );
}
