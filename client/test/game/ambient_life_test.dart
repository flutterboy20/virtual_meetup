import 'dart:ui';

import 'package:client/game/ambient_life.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/game/diorama_art.dart';
import 'package:client/game/nametag_layer.dart';
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

const _camera = Rect.fromLTWH(40, 880, 900, 300);
const _away = Rect.fromLTWH(1100, 0, 300, 300);
final Rect _pool = ZoneProps.rect(WorldLayout.pool);
final ({Offset centre, double radius}) _surface = ConferenceMap.empty.fountain;
final List<double> _times = [for (var i = 0; i < 400; i++) i * 1.37];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dust', () {
    test('is capped, and every mote is on screen', () {
      for (final t in _times) {
        final motes = DustMotes.motes(_camera, t);

        expect(motes, hasLength(DustMotes.count));
        for (final mote in motes) {
          expect(_camera.inflate(0.01).contains(mote.at), isTrue);
        }
      }
    });

    test('drifts: the same mote is somewhere else a second later', () {
      final now = DustMotes.motes(_camera, 10).first.at;
      final later = DustMotes.motes(_camera, 11).first.at;

      expect(now, isNot(later));
    });

    test('is gone, and still, under reduce-motion', () {
      final dust = DustMotes(
        visibleWorldRect: () => _camera,
        reduceMotion: () => true,
      )..update(5);
      final canvas = _CountingCanvas();
      dust.render(canvas);

      expect(dust.time, isZero);
      expect(canvas.calls, isZero);
    });
  });

  group('the fountain jet', () {
    test('has a capped number of drops, all over its own water', () {
      final top = DioramaArt.cylinderTop(
        _surface.centre,
        height: FountainJet.height,
      );
      for (final t in _times) {
        final drops = FountainJet.dropsAt(_surface, t);

        expect(drops, hasLength(FountainJet.drops));
        for (final drop in drops) {
          expect(
            (drop.dx - _surface.centre.dx).abs(),
            lessThan(_surface.radius),
          );
          // No higher than the top of the jet, give or take the northward
          // spread a drop has already started on as it leaves it.
          expect(
            drop.dy,
            greaterThanOrEqualTo(top.dy - _surface.radius * 0.6 * 0.55),
          );
          expect(drop.dy, lessThan(_surface.centre.dy + _surface.radius));
        }
      }
    });

    test('draws nothing under reduce-motion or off camera', () {
      for (final (camera, still) in [(_camera, true), (_away, false)]) {
        final canvas = _CountingCanvas();
        FountainJet(
          surface: _surface,
          visibleWorldRect: () => camera,
          reduceMotion: () => still,
        ).render(canvas);

        expect(canvas.calls, isZero);
      }
    });

    test('draws when it is on camera', () {
      final canvas = _CountingCanvas();
      FountainJet(
        surface: _surface,
        visibleWorldRect: () => _camera,
        reduceMotion: () => false,
      ).render(canvas);

      expect(canvas.calls, greaterThan(0));
    });
  });

  group('the pool rings', () {
    test('never touch the rim', () {
      final water = RRect.fromRectAndRadius(
        _pool.deflate(PoolRings.margin / 2),
        ZoneProps.poolRimRadius,
      );
      for (final t in _times) {
        for (var i = 0; i < PoolRings.count; i++) {
          final at = PoolRings.ringAt(i, _pool, t);
          for (final edge in [
            at.translate(PoolRings.radius, 0),
            at.translate(-PoolRings.radius, 0),
            at.translate(0, PoolRings.radius),
            at.translate(0, -PoolRings.radius),
          ]) {
            expect(water.contains(edge), isTrue, reason: 'ring $i @$t');
          }
        }
      }
    });

    test('stay put, but stay, under reduce-motion', () {
      final rings = PoolRings(
        pool: _pool,
        visibleWorldRect: () => _camera,
        reduceMotion: () => true,
      )..update(5);
      final canvas = _CountingCanvas();
      rings.render(canvas);

      expect(rings.time, isZero);
      expect(canvas.calls, greaterThan(0), reason: 'a ring is a thing');
    });

    test('draw nothing off camera', () {
      final canvas = _CountingCanvas();
      PoolRings(
        pool: _pool,
        visibleWorldRect: () => _away,
        reduceMotion: () => false,
      ).render(canvas);

      expect(canvas.calls, isZero);
    });
  });

  testWithGame<ConferenceGame>(
    'the conference has all three, each in its layer',
    ConferenceGame.new,
    (game) async {
      await game.ready();
      final children = game.world.children;
      final names = children.whereType<NametagLayer>().single.priority;

      final dust = children.whereType<DustMotes>().single.priority;
      expect(dust, greaterThan(game.bean.priority));
      expect(dust, lessThan(names));

      for (final low in [
        children.whereType<FountainJet>().single.priority,
        children.whereType<PoolRings>().single.priority,
      ]) {
        expect(low, greaterThan(game.furniture.priority));
        expect(low, lessThan(0), reason: 'under every bean');
      }
    },
  );
}
