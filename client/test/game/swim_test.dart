import 'package:client/game/collision.dart';
import 'package:client/game/splash_field.dart';
import 'package:client/game/swim_state.dart';
import 'package:client/game/water_watcher.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// A point in the middle of the pool.
final _inPool = Vector2(WorldLayout.pool.centerX, WorldLayout.pool.centerY);

/// A point on the lounge deck, clear of the pool and of the loungers.
final _onDeck = Vector2(
  WorldLayout.pool.centerX,
  WorldLayout.pool.bottom + 40,
);

/// Advances [tick] by [seconds] in 60Hz steps.
void run(double seconds, void Function(double dt) tick) {
  const dt = 1 / 60;
  for (var t = 0.0; t < seconds; t += dt) {
    tick(dt);
  }
}

void main() {
  group('the water region', () {
    test('the pool is water, and only the pool is', () {
      expect(WorldLayout.isWater(_inPool.x, _inPool.y), isTrue);
      expect(WorldLayout.isWater(_onDeck.x, _onDeck.y), isFalse);
      expect(WorldLayout.isWater(spawnCenterX, spawnCenterY), isFalse);
    });

    test('movement slows inside the water and only inside it', () {
      expect(
        WorldLayout.speedFactorAt(_inPool.x, _inPool.y),
        equals(WorldLayout.swimSpeedFactor),
      );
      expect(WorldLayout.speedFactorAt(_onDeck.x, _onDeck.y), equals(1));
      expect(WorldLayout.speedFactorAt(spawnCenterX, spawnCenterY), equals(1));
      // Slower, but not so slow that crossing the pool is a chore.
      expect(WorldLayout.swimSpeedFactor, inInclusiveRange(0.4, 0.7));
    });

    test('collision no longer blocks the pool', () {
      final collision = WorldCollision(WorldLayout.of(const []));

      expect(collision.isFree(_inPool.x, _inPool.y), isTrue);
      // And a walk straight in is taken whole rather than stopping at the lip.
      final from = Vector2(_inPool.x, WorldLayout.pool.top - 4);
      final to = Vector2(_inPool.x, WorldLayout.pool.top + 4);
      expect(collision.resolve(from: from, to: to), equals(to));
    });

    test('the pool is not in the obstacle list at all', () {
      final blocked = WorldLayout.fixedObstacles.any(
        (obstacle) => obstacle.contains(_inPool.x, _inPool.y),
      );

      expect(blocked, isFalse);
    });

    test('a resumed session in the water is free, not stuck', () {
      // `nearestFreePoint` will now happily hand back a spot in the pool,
      // because the pool is free. The thing that must hold is that the player
      // it hands it to can then swim out.
      final collision = WorldCollision(WorldLayout.of(const []));

      final placed = collision.nearestFreePoint(_inPool.x, _inPool.y);

      expect(placed, equals(_inPool));
      expect(collision.isFree(placed.x, placed.y), isTrue);
    });

    test('nothing can be trapped against the far wall of the pool', () {
      // Swim from one corner of the pool to the opposite one, a step at a
      // time at swimming pace, and confirm every single step is legal.
      final collision = WorldCollision(WorldLayout.of(const []));
      var at = Vector2(
        WorldLayout.pool.left + 2,
        WorldLayout.pool.top + 2,
      );
      const step = 140 * WorldLayout.swimSpeedFactor / 60;

      for (var i = 0; i < 600; i++) {
        final to = Vector2(at.x + step, at.y + step);
        at = collision.resolve(from: at, to: to);
        expect(
          collision.isFree(at.x, at.y),
          isTrue,
          reason: 'stranded at ${at.x},${at.y}',
        );
      }

      // And it actually got out the far side rather than grinding on a wall.
      expect(at.x, greaterThan(WorldLayout.pool.right));
      expect(at.y, greaterThan(WorldLayout.pool.bottom));
    });
  });

  group('SwimState', () {
    test('a dry bean is dry', () {
      final swim = SwimState();

      run(1, (dt) => swim.update(dt, inWater: false));

      expect(swim.submersion, isZero);
      expect(swim.isSwimming, isFalse);
      expect(swim.diveLift, isZero);
      expect(swim.wobble, isZero);
    });

    test('entering the water sinks the bean and plays the dive arc', () {
      final swim = SwimState()..update(1 / 60, inWater: true);

      expect(swim.isDiving, isTrue);
      // The arc peaks somewhere in the middle, so it has to be sampled.
      var peak = 0.0;
      run(swim.diveDuration, (dt) {
        swim.update(dt, inWater: true);
        if (swim.diveLift > peak) peak = swim.diveLift;
      });

      expect(peak, greaterThan(swim.diveHeight * 0.8));
      expect(swim.isDiving, isFalse, reason: 'the arc never ended');
      expect(swim.submersion, greaterThan(0.9));
      expect(swim.sinkFraction, greaterThan(0));
    });

    test('the dive fires once per entry, not once per frame', () {
      final swim = SwimState();

      run(2, (dt) => swim.update(dt, inWater: true));

      expect(swim.isDiving, isFalse);
      expect(swim.diveLift, isZero);
    });

    test('climbing out dries the bean off again', () {
      final swim = SwimState();
      run(1, (dt) => swim.update(dt, inWater: true));
      expect(swim.submersion, greaterThan(0.9));

      run(1, (dt) => swim.update(dt, inWater: false));

      expect(swim.submersion, lessThan(0.01));
      expect(swim.isSwimming, isFalse);
    });

    test('the face stays above the waterline', () {
      // Sink the body past its visor and a bean stops having a face, which is
      // the only thing that makes one bean yours.
      final swim = SwimState();
      run(3, (dt) => swim.update(dt, inWater: true));

      expect(swim.sinkFraction, lessThan(0.5));
    });
  });

  group('SplashField', () {
    test('a dive throws a bounded burst of droplets', () {
      final field = SplashField()..splash(100, 100);

      expect(field.liveCount, inInclusiveRange(10, 14));
      expect(
        field.live.every((p) => p.kind == SplashKind.droplet),
        isTrue,
      );
    });

    test('particles decay and the field empties itself', () {
      final field = SplashField()..splash(100, 100);

      run(SplashField.dropletLife + 0.1, field.update);

      expect(field.liveCount, isZero);
    });

    test('the hard cap holds under a flood', () {
      final field = SplashField();

      // Two hundred simultaneous dives — an order of magnitude past the worst
      // case the exit criteria ask for. Nothing may grow.
      for (var i = 0; i < 200; i++) {
        field.splash(100 + i.toDouble(), 100);
      }

      expect(field.liveCount, lessThanOrEqualTo(SplashField.defaultCapacity));
      expect(field.liveCount, equals(SplashField.defaultCapacity));
    });

    test('a flood overwrites the oldest, so the newest splash is intact', () {
      final field = SplashField();
      for (var i = 0; i < 40; i++) {
        field.splash(0, 0);
      }

      field.splash(999, 999);

      final newest = field.live.where((p) => p.x > 900 || p.vx != 0).toList();
      expect(newest, isNotEmpty, reason: 'the newest burst was eaten');
    });

    test('wakes and droplets share the one cap', () {
      final field = SplashField();

      for (var i = 0; i < 500; i++) {
        field.wake(50, 50);
      }

      expect(field.liveCount, lessThanOrEqualTo(SplashField.defaultCapacity));
    });

    test('clearing kills everything', () {
      final field = SplashField()..splash(1, 1);
      expect(field.liveCount, greaterThan(0));

      field.clear();

      expect(field.liveCount, isZero);
    });
  });

  group('WaterWatcher', () {
    SwimSample at(Vector2 v, {String id = 'p1'}) => (id: id, x: v.x, y: v.y);

    test('fires exactly one dive per crossing, twenty times over', () {
      // The failure this exists to prevent: a bean idling on the pool lip
      // whose interpolated position wobbles across the edge, machine-gunning
      // a fourteen-particle burst on every frame.
      // Started on dry land: a bean first *seen* already floating does not
      // splash, deliberately, so twenty crossings means twenty entries from
      // outside.
      final watcher = WaterWatcher()..update(1 / 60, [at(_onDeck)]);
      var dives = 0;

      for (var i = 0; i < 20; i++) {
        // In, held for a few frames, then out and held.
        for (var f = 0; f < 5; f++) {
          dives += watcher.update(1 / 60, [at(_inPool)]).dives.length;
        }
        for (var f = 0; f < 5; f++) {
          dives += watcher.update(1 / 60, [at(_onDeck)]).dives.length;
        }
      }

      expect(dives, equals(20));
    });

    test('a bean sitting on the edge never fires at all', () {
      // Straddling the boundary by a unit either way, sixty times a second
      // for two seconds. The dead band has to swallow every one of them.
      final watcher = WaterWatcher();
      final lip = WorldLayout.pool.top;
      var dives = 0;

      for (var i = 0; i < 120; i++) {
        final y = lip + (i.isEven ? -1.0 : 1.0);
        dives += watcher
            .update(1 / 60, [(id: 'p1', x: _inPool.x, y: y)])
            .dives
            .length;
      }

      expect(dives, isZero);
    });

    test('local and remote beans are treated identically', () {
      final watcher = WaterWatcher()
        ..update(1 / 60, [
          at(_onDeck, id: 'local:me'),
          at(_onDeck, id: 'remote-1'),
          at(_onDeck, id: 'remote-2'),
        ]);

      final events = watcher.update(1 / 60, [
        at(_inPool, id: 'local:me'),
        at(_inPool, id: 'remote-1'),
        at(_onDeck, id: 'remote-2'),
      ]);

      expect(events.dives, hasLength(2));
      expect(watcher.swimmerCount, equals(2));
      expect(watcher.isSwimming('remote-2'), isFalse);
    });

    test('somebody already floating when they appear does not splash', () {
      // A resumed session in the water, or a swimmer walking into interest
      // range. They did not just jump in, and a splash for them is a lie
      // every other client can see through.
      final events = WaterWatcher().update(1 / 60, [at(_inPool)]);

      expect(events.dives, isEmpty);
    });

    test('a swimming bean drops wakes at a steady rate', () {
      // Enter from dry land, so the wake clock starts at the dive.
      final watcher = WaterWatcher()..update(1 / 60, [at(_onDeck)]);
      var wakes = 0;

      run(1, (dt) {
        wakes += watcher.update(dt, [at(_inPool)]).wakes.length;
      });

      // One second at a 0.35s interval is two or three rings.
      expect(wakes, inInclusiveRange(2, 3));
    });

    test('a bean on dry land never wakes', () {
      final watcher = WaterWatcher();
      var wakes = 0;

      run(2, (dt) {
        wakes += watcher.update(dt, [at(_onDeck)]).wakes.length;
      });

      expect(wakes, isZero);
    });

    test('a raft counts as getting out of the water', () {
      // The beach's raft is a hole in the water: climb on and the wakes
      // stop, step off the far side and it is a fresh dive.
      const raft = WorldRect(540, 500, 700, 590);
      const sea = WorldRect(0, 420, 1200, 900);
      final offRaft = Vector2(raft.centerX, raft.bottom + 60);
      final onRaft = Vector2(raft.centerX, raft.centerY);

      final watcher = WaterWatcher(
        regions: const [sea],
        dryPlatforms: const [raft],
      )..update(1 / 60, [at(offRaft)]);

      expect(watcher.isSwimming('p1'), isTrue);

      var wakes = 0;
      run(1, (dt) {
        wakes += watcher.update(dt, [at(onRaft)]).wakes.length;
      });

      expect(watcher.isSwimming('p1'), isFalse);
      expect(wakes, isZero);

      // And swimming off it splashes again.
      final events = watcher.update(1 / 60, [at(offRaft)]);
      expect(events.dives, hasLength(1));
    });

    test('a bean shuffling on the raft edge never fires', () {
      const raft = WorldRect(540, 500, 700, 590);
      const sea = WorldRect(0, 420, 1200, 900);
      final watcher = WaterWatcher(
        regions: const [sea],
        dryPlatforms: const [raft],
      );
      var dives = 0;

      for (var i = 0; i < 120; i++) {
        final y = raft.bottom + (i.isEven ? -1.0 : 1.0);
        dives += watcher
            .update(1 / 60, [(id: 'p1', x: raft.centerX, y: y)])
            .dives
            .length;
      }

      expect(dives, isZero);
    });

    test('beans that go out of range stop being tracked', () {
      final watcher = WaterWatcher()..update(1 / 60, [at(_inPool)]);
      expect(watcher.swimmerCount, equals(1));

      watcher.update(1 / 60, const <SwimSample>[]);

      expect(watcher.swimmerCount, isZero);
      expect(watcher.isSwimming('p1'), isFalse);
    });
  });
}
