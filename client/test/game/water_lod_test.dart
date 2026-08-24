import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/splash_field.dart';
import 'package:client/game/water_component.dart';
import 'package:client/game/water_lod.dart';
import 'package:client/game/water_watcher.dart';
import 'package:client/game/world_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// A water rect the size of the beach's sea, for the cost tests.
const WorldRect _sea = WorldRect(0, 420, 1200, 900);

/// The conference's pool, for the "nothing got worse" comparisons.
const WorldRect _pool = WorldRect(690, 900, 910, 1090);

/// Roughly what a phone shows at zoom 1.6: 244x527 world units.
Rect _phoneView(double centerX, double centerY) =>
    Rect.fromCenter(center: Offset(centerX, centerY), width: 244, height: 527);

/// A map with the given water in it and nothing else.
class _WaterOnlyMap extends GameMap {
  _WaterOnlyMap(this.waterRegions);

  @override
  MapSpec get spec => MapSpec.beach;

  @override
  final List<WorldRect> waterRegions;

  @override
  List<Sponsor> get sponsors => const [];

  @override
  List<Obstacle> get obstacles => const [];

  @override
  List<Rect> get voids => const [];

  @override
  List<LightRun> get lightRuns => const [];

  @override
  GlowSpot get crowdGlow =>
      (x: 600, y: 310, radius: 60, zone: WorldZone.beachSand);

  @override
  double get swimSpeedFactor => 0.55;

  @override
  void paintZoneFloor(Canvas canvas, WorldZone zone, Rect rect) {}

  @override
  void paintFurniture(Canvas canvas) {}
}

/// The water component under test, over [region], seen through [view].
WaterComponent _water(WorldRect region, {Rect? view, SplashField? field}) =>
    WaterComponent(
      swimmers: () => const [],
      map: _WaterOnlyMap([region]),
      field: field,
      visibleWorldRect: view == null ? null : () => view,
    );

/// The rect [region] covers, as the component sees it.
Rect _rectOf(WorldRect region) =>
    Rect.fromLTRB(region.left, region.top, region.right, region.bottom);

/// Every crest centre, as world points.
Set<Offset> _crests(WaterComponent water, WorldRect region, Rect view) => water
    .crestLattice(_rectOf(region), view)
    .map((point) => Offset(point.x, point.y))
    .toSet();

void main() {
  group('WaterLod', () {
    test('starts at full: most devices can afford everything', () {
      final lod = WaterLod();

      expect(lod.detail, equals(WaterDetail.full));
      expect(lod.crestCount, equals(WaterLod.fullCrests));
      expect(lod.emitsParticles, isTrue);
    });

    test('drops a tier only after a sustained run over budget', () {
      final lod = WaterLod();
      const bad = 24.0;

      // Half a second of jank is a scene, not a verdict.
      for (var i = 0; i < 30; i++) {
        lod.update(1 / 60, p95Millis: bad);
      }
      expect(lod.detail, equals(WaterDetail.full));

      for (var i = 0; i < 40; i++) {
        lod.update(1 / 60, p95Millis: bad);
      }
      expect(lod.detail, equals(WaterDetail.reduced));
    });

    test('walks all the way down to flat, and stops there', () {
      final lod = WaterLod();
      for (var i = 0; i < 600; i++) {
        lod.update(1 / 60, p95Millis: 40);
      }

      expect(lod.detail, equals(WaterDetail.flat));
      expect(lod.crestCount, equals(0));
      expect(lod.emitsParticles, isFalse);
      expect(lod.isAnimated, isFalse);
      expect(lod.wakeInterval, equals(double.infinity));
    });

    test('does not oscillate at the boundary', () {
      // The failure this class exists to prevent: a frame time parked on the
      // budget flipping the surface between two levels of detail forever.
      final lod = WaterLod();
      var changes = 0;
      var previous = lod.detail;

      for (var i = 0; i < 2000; i++) {
        // Straddling the budget, one frame either side of it.
        lod.update(1 / 60, p95Millis: i.isEven ? 16.5 : 16.9);
        if (lod.detail != previous) {
          changes++;
          previous = lod.detail;
        }
      }

      expect(changes, isZero);
    });

    test('a run inside the dead band changes nothing either way', () {
      final lod = WaterLod();
      // Under budget, but not comfortably: neither timer should run.
      for (var i = 0; i < 600; i++) {
        lod.update(1 / 60, p95Millis: 15);
      }
      expect(lod.detail, equals(WaterDetail.full));

      lod.force(WaterDetail.reduced);
      for (var i = 0; i < 600; i++) {
        lod.update(1 / 60, p95Millis: 15);
      }
      expect(lod.detail, equals(WaterDetail.reduced));
    });

    test('climbs back, but slower and against a stricter bar', () {
      final lod = WaterLod()..force(WaterDetail.flat);

      // Comfortably under budget for one second is not enough to climb.
      for (var i = 0; i < 60; i++) {
        lod.update(1 / 60, p95Millis: 8);
      }
      expect(lod.detail, equals(WaterDetail.flat));

      for (var i = 0; i < 200; i++) {
        lod.update(1 / 60, p95Millis: 8);
      }
      expect(lod.detail, equals(WaterDetail.reduced));
    });

    test('an unmeasured profile is not evidence of a good frame', () {
      // A fresh `FrameProfile` reports zero. Treating that as a perfect frame
      // would let a headless or just-started game climb tiers on nothing.
      final lod = WaterLod()..force(WaterDetail.flat);
      for (var i = 0; i < 600; i++) {
        lod.update(1 / 60, p95Millis: 0);
      }

      expect(lod.detail, equals(WaterDetail.flat));
    });

    test('remote wakes drop a tier early while the local bean is under', () {
      final lod = WaterLod();

      expect(
        lod.remoteWakeInterval(localIsSubmerged: false),
        equals(WaterLod.wakeIntervalAt(WaterDetail.full)),
      );
      expect(
        lod.remoteWakeInterval(localIsSubmerged: true),
        equals(WaterLod.wakeIntervalAt(WaterDetail.reduced)),
      );

      // ...and the local bean's own wake is never cheapened with them.
      expect(
        lod.wakeInterval,
        equals(WaterLod.wakeIntervalAt(WaterDetail.full)),
      );
    });

    test('spacing is clamped at both ends', () {
      expect(
        WaterLod.spacingFor(1, WaterLod.fullCrests),
        equals(WaterLod.minSpacing),
      );
      expect(
        WaterLod.spacingFor(1000000000, WaterLod.fullCrests),
        equals(WaterLod.maxSpacing),
      );
      expect(WaterLod.spacingFor(0, 0), equals(WaterLod.maxSpacing));
    });
  });

  group('the crest lattice', () {
    test('a crest does not swim as you walk', () {
      // Anchored at the world origin, so a point on screen from two different
      // camera positions is at the *same* world coordinate in both.
      final before = _phoneView(600, 640);
      final after = before.translate(40, 0);
      final water = _water(_sea, view: before);

      final was = _crests(water, _sea, before);
      final now = _crests(water, _sea, after);
      final shared = was.intersection(now);

      expect(
        shared,
        isNotEmpty,
        reason: 'walking 40 units should not replace every crest',
      );
      // A lattice generated relative to the camera would share nothing at all
      // between two views; one anchored to the world shares most of it.
      expect(shared.length, greaterThan(was.length ~/ 2));
    });

    test('cost is bounded by the screen, not by the size of the sea', () {
      // The whole point of the task. The sea is 13.8x the pool's area and
      // must not cost 13.8x the arcs.
      final view = _phoneView(600, 640);
      final onSea = _crests(_water(_sea, view: view), _sea, view);

      expect(onSea.length, lessThanOrEqualTo(WaterLod.fullCrests * 3));
      expect(
        onSea.length,
        greaterThan(9),
        reason: 'an area-scoped lattice would show about nine crests here',
      );
    });

    test('the sea is no sparser on screen than the pool is', () {
      // The failure mode this replaced: 40 crests over 13.8x the area reads
      // as flat blue paint. Both are measured through the same viewport.
      final atSea = _phoneView(600, 640);
      final atPool = _phoneView(800, 995);

      final seaCount = _crests(_water(_sea, view: atSea), _sea, atSea).length;
      final poolCount = _crests(
        _water(_pool, view: atPool),
        _pool,
        atPool,
      ).length;

      expect(seaCount, greaterThanOrEqualTo(poolCount));
    });

    test('the reduced tier keeps every crest exactly where it was', () {
      final view = _phoneView(600, 640);
      final water = _water(_sea, view: view);

      final full = _crests(water, _sea, view);
      water.lod.force(WaterDetail.reduced);
      final reduced = _crests(water, _sea, view);

      expect(reduced.length, lessThan(full.length));
      expect(
        full.containsAll(reduced),
        isTrue,
        reason: 'a tier change must not move a crest sideways',
      );
    });

    test('flat draws no crests at all', () {
      final view = _phoneView(600, 640);
      final water = _water(_sea, view: view)..lod.force(WaterDetail.flat);

      expect(_crests(water, _sea, view), isEmpty);
    });

    test('water off screen costs nothing to walk', () {
      // The boardwalk, looking away from the sea.
      final view = _phoneView(600, 100);
      final water = _water(_sea, view: view);

      expect(_crests(water, _sea, view), isEmpty);
    });

    test('every crest is inside the water region it belongs to', () {
      final view = _phoneView(600, 640);
      final rect = _rectOf(_sea);

      for (final point in _water(_sea, view: view).crestLattice(rect, view)) {
        expect(rect.contains(Offset(point.x, point.y)), isTrue);
      }
    });
  });

  group('particles under LOD', () {
    SwimSample at(double x, double y, {String id = 'a'}) =>
        (id: id, x: x, y: y);

    test('flat emits no particles at all', () {
      final field = SplashField();
      final water = WaterComponent(
        swimmers: () => [at(600, 700)],
        map: _WaterOnlyMap(const [_sea]),
        field: field,
        watcher: WaterWatcher(regions: const [_sea]),
      )..lod.force(WaterDetail.flat);

      // Ten seconds of somebody swimming: a dive on the first frame and
      // wakes on every one after it, all of which must be suppressed.
      for (var i = 0; i < 600; i++) {
        water.update(1 / 60);
      }

      expect(field.liveCount, isZero);
    });

    test('full emits a dive splash and a stream of wakes', () {
      final field = SplashField();
      final water = WaterComponent(
        swimmers: () => [at(600, 700)],
        map: _WaterOnlyMap(const [_sea]),
        field: field,
        watcher: WaterWatcher(regions: const [_sea]),
      );

      for (var i = 0; i < 60; i++) {
        water.update(1 / 60);
      }

      expect(field.liveCount, greaterThan(0));
    });

    test('a submerged local bean thins out remote wakes, not its own', () {
      final field = SplashField();
      final water = WaterComponent(
        swimmers: () => [at(600, 700, id: 'me'), at(620, 700, id: 'them')],
        map: _WaterOnlyMap(const [_sea]),
        field: field,
        watcher: WaterWatcher(regions: const [_sea]),
        localSwimmerId: 'me',
        isLocalSubmerged: () => true,
      )..update(1 / 60);

      expect(water.watcher.wakeInterval, equals(0.35));
      expect(water.watcher.remoteWakeInterval, equals(0.6));
      expect(water.watcher.localId, equals('me'));
    });

    test('the pool still behaves exactly as Phase 9 left it', () {
      // A conference map through the new code path: the default water
      // regions, the default LOD, no camera.
      final water = WaterComponent(swimmers: () => const []);
      expect(water.map.waterRegions, equals(const [WorldLayout.pool]));
      expect(water.lod.detail, equals(WaterDetail.full));
      expect(water.watcher.wakeInterval, equals(0.35));
    });
  });
}
