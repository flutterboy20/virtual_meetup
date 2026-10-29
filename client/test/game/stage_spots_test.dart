import 'dart:ui';

import 'package:client/game/conference_game.dart';
import 'package:client/game/stage_spots_component.dart';
import 'package:client/game/world_layout.dart';
import 'package:client/game/zone_props.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// Counts every call made on it.
class _CountingCanvas implements Canvas {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    return null;
  }
}

final Rect _hall = ZoneProps.rect(WorldZone.hall.rect);

StageSpotsComponent _spots({
  Rect camera = const Rect.fromLTWH(640, 100, 300, 300),
  bool still = false,
}) => StageSpotsComponent(
  visibleWorldRect: () => camera,
  reduceMotion: () => still,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the sweep', () {
    const p = StageSpotsComponent.period;
    final samples = [for (var i = 0; i <= 90; i++) p * i / 90];

    test('every pool of light stays on the hall floor', () {
      // A pool over the side wall would light the next room.
      for (final t in samples) {
        for (var beam = 0; beam < 2; beam++) {
          final pool = Rect.fromCircle(
            center: StageSpotsComponent.pool(beam, t),
            radius: StageSpotsComponent.poolRadius * 1.25,
          );

          expect(_hall.intersect(pool), equals(pool), reason: 'beam $beam @$t');
        }
      }
    });

    test('the pools land in front of the stage, not on it', () {
      final stage = ZoneProps.rect(WorldLayout.stage);
      for (final t in samples) {
        for (var beam = 0; beam < 2; beam++) {
          expect(
            StageSpotsComponent.pool(beam, t).dy,
            greaterThan(stage.bottom),
          );
        }
      }
    });

    test('the beams mirror each other across the aisle', () {
      final aisle = _hall.center.dx;
      for (final t in samples) {
        final west = StageSpotsComponent.pool(0, t);
        final east = StageSpotsComponent.pool(1, -t);

        expect(west.dx - aisle, closeTo(aisle - east.dx, 1e-6));
        expect(west.dy, closeTo(east.dy, 1e-6));
      }
    });

    test('a sweep repeats after one period', () {
      for (var beam = 0; beam < 2; beam++) {
        expect(
          StageSpotsComponent.angle(beam, 1.3),
          closeTo(StageSpotsComponent.angle(beam, 1.3 + p), 1e-9),
        );
      }
    });

    test('the clock wraps instead of growing', () {
      final spots = _spots()..update(p * 40 + 1.5);

      expect(spots.time, closeTo(1.5, 1e-6));
    });
  });

  group('drawing', () {
    test('draws when the hall is on camera', () {
      final canvas = _CountingCanvas();

      _spots().render(canvas);

      expect(canvas.calls, greaterThan(0));
    });

    test('draws nothing when the hall is off camera', () {
      final canvas = _CountingCanvas();

      _spots(camera: const Rect.fromLTWH(100, 900, 300, 300)).render(canvas);

      expect(canvas.calls, isZero);
    });

    test('draws nothing under reduce-motion', () {
      final canvas = _CountingCanvas();

      _spots(still: true).render(canvas);

      expect(canvas.calls, isZero);
    });
  });

  testWithGame<ConferenceGame>(
    'the conference has spots, under the beans and the screen',
    ConferenceGame.new,
    (game) async {
      await game.ready();
      final spots = game.world.children.whereType<StageSpotsComponent>().single;

      expect(spots.priority, greaterThan(game.furniture.priority));
      expect(spots.priority, lessThan(game.stageScreen!.priority));
      expect(spots.priority, lessThan(0));

      game.reduceMotion = true;
      final canvas = _CountingCanvas();
      spots.render(canvas);
      expect(canvas.calls, isZero, reason: 'reads the flag live');
    },
  );
}
