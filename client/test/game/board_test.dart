import 'dart:ui';

import 'package:client/game/beach_layout.dart';
import 'package:client/game/beach_map.dart';
import 'package:client/game/bean_animation.dart';
import 'package:client/game/bean_component.dart';
import 'package:client/game/hint_bean_component.dart';
import 'package:client/game/swim_state.dart';
import 'package:client/game/tap_target.dart';
import 'package:client/game/tap_unlock.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

const _beach = BeachMap();
final ConferenceMap _conference = ConferenceMap.empty;

/// The middle of the big board, in world units.
double get _boardX =>
    (BeachLayout.bigBoard.left + BeachLayout.bigBoard.right) / 2;

/// The middle of the big board, in world units.
double get _boardY =>
    (BeachLayout.bigBoard.top + BeachLayout.bigBoard.bottom) / 2;

/// A point out in the open sea.
const double _seaX = 300;

/// A point out in the open sea.
const double _seaY = 700;

/// Advances [tick] by [seconds] in 60Hz steps.
void _run(double seconds, void Function(double dt) tick) {
  const dt = 1 / 60;
  for (var t = 0.0; t < seconds; t += dt) {
    tick(dt);
  }
}

void main() {
  group('where the secret sits', () {
    test('the board stands on the beach floor, in the sand', () {
      for (final corner in [
        (BeachLayout.bigBoard.left, BeachLayout.bigBoard.top),
        (BeachLayout.bigBoard.right, BeachLayout.bigBoard.bottom),
      ]) {
        expect(
          MapSpec.beach.isOnFloor(corner.$1, corner.$2),
          isTrue,
          reason: '$corner should be inside the walkable beach',
        );
      }
      expect(WorldZone.beachSand.rect.contains(_boardX, _boardY), isTrue);
      // Far east: you cannot see it, and therefore cannot tap it, without
      // walking to it. That is the whole of the proximity rule.
      expect(_boardX, greaterThan(MapSpec.beach.width * 0.85));
    });

    test('the hint bean stands on the beach floor, far to the west', () {
      expect(
        MapSpec.beach.isOnFloor(BeachLayout.hintBeanX, BeachLayout.hintBeanY),
        isTrue,
      );
      expect(
        WorldZone.beachSand.rect.contains(
          BeachLayout.hintBeanX,
          BeachLayout.hintBeanY,
        ),
        isTrue,
      );
      expect(BeachLayout.hintBeanX, lessThan(MapSpec.beach.width * 0.15));
    });

    test('the hint and the board are a walk apart', () {
      // A hint you can read from where the thing is is not a hint.
      expect(_boardX - BeachLayout.hintBeanX, greaterThan(900));
    });

    test('both are clear of the spawn ring', () {
      const spec = MapSpec.beach;
      final clearance = spec.spawnRingRadius + 60;

      for (final at in [
        (_boardX, _boardY),
        (BeachLayout.hintBeanX, BeachLayout.hintBeanY),
      ]) {
        final dx = at.$1 - spec.spawnCenterX;
        final dy = at.$2 - spec.spawnCenterY;
        expect(
          dx * dx + dy * dy,
          greaterThan(clearance * clearance),
          reason: 'arriving inside $at would be a bad first second',
        );
      }
    });

    test('neither is an obstacle', () {
      for (final at in [
        (_boardX, _boardY),
        (BeachLayout.hintBeanX, BeachLayout.hintBeanY),
      ]) {
        expect(
          _beach.obstacles.any((o) => o.contains(at.$1, at.$2)),
          isFalse,
          reason: 'a solid prop in the only dry band is worse than an odd one',
        );
      }
    });

    test('the conference has neither, and no surfing', () {
      expect(_conference.hintBean, isNull);
      expect(_conference.tapTargets, isEmpty);
      // The single statement of "the board is a beach thing".
      expect(_conference.surfSpeedFactor, isNull);
      expect(_beach.surfSpeedFactor, equals(0.9));
    });

    test('the hint bean draws without throwing', () {
      final hint = HintBeanComponent(
        x: BeachLayout.hintBeanX,
        y: BeachLayout.hintBeanY,
      )..update(1 / 60);

      expect(hint.priority, equals(0));
      expect(() => hint.update(1 / 60), returnsNormally);
    });
  });

  group('tap targets', () {
    test('the beach has exactly two, and they do not overlap', () {
      final targets = _beach.tapTargets;

      expect(
        targets.map((t) => t.id).toSet(),
        equals(TapTargetId.values.toSet()),
      );
      expect(targets, hasLength(2));

      final board = targets.firstWhere((t) => t.id == TapTargetId.board);
      final hint = targets.firstWhere((t) => t.id == TapTargetId.hint);
      expect(
        board.contains(BeachLayout.hintBeanX, BeachLayout.hintBeanY),
        isFalse,
      );
      expect(hint.contains(_boardX, _boardY), isFalse);
    });

    test('a tap in the middle of the board hits the board', () {
      final hit = _beach.tapTargets.where((t) => t.contains(_boardX, _boardY));

      expect(hit.single.id, equals(TapTargetId.board));
    });

    test('a tap on the hint bean hits the hint', () {
      final hit = _beach.tapTargets.where(
        (t) => t.contains(BeachLayout.hintBeanX, BeachLayout.hintBeanY - 20),
      );

      expect(hit.single.id, equals(TapTargetId.hint));
    });

    test('a tap in the open sea hits nothing at all', () {
      expect(
        _beach.tapTargets.where((t) => t.contains(_seaX, _seaY)),
        isEmpty,
      );
    });

    test('the list is the same object every time it is read', () {
      // Read on every tap event, so a fresh list per read would be an
      // allocation on the input path for nothing.
      expect(identical(_beach.tapTargets, _beach.tapTargets), isTrue);
    });
  });

  group('TapUnlock', () {
    test('three taps inside the window arm it', () {
      final unlock = TapUnlock();

      expect(unlock.tap(), equals(TapUnlockResult.counting));
      expect(unlock.tap(), equals(TapUnlockResult.counting));
      expect(unlock.tap(), equals(TapUnlockResult.armed));
      expect(unlock.isArmed, isTrue);
    });

    test('two taps and a pause do not', () {
      final unlock = TapUnlock()
        ..tap()
        ..tap();

      _run(2.5, unlock.update);

      expect(unlock.taps, isZero);
      expect(unlock.tap(), equals(TapUnlockResult.counting));
      expect(unlock.isArmed, isFalse);
    });

    test('a run that lapses without any ticks still resets', () {
      // A backgrounded tab does not tick, so the lapse has to be checked on
      // the tap as well as in update.
      final unlock = TapUnlock()
        ..tap()
        ..tap()
        ..update(9);

      expect(unlock.tap(), equals(TapUnlockResult.counting));
      expect(unlock.isArmed, isFalse);
    });

    test('taps just inside the window keep counting', () {
      final unlock = TapUnlock()..tap();
      _run(1.5, unlock.update);
      unlock.tap();
      _run(1.5, unlock.update);

      expect(unlock.tap(), equals(TapUnlockResult.armed));
    });

    test('one tap disarms it, not three', () {
      final unlock = TapUnlock(armed: true);

      expect(unlock.tap(), equals(TapUnlockResult.disarmed));
      expect(unlock.isArmed, isFalse);
    });

    test('arming and disarming can be done again', () {
      final unlock = TapUnlock()
        ..tap()
        ..tap()
        ..tap()
        ..tap();

      expect(unlock.isArmed, isFalse);
      unlock
        ..tap()
        ..tap()
        ..tap();
      expect(unlock.isArmed, isTrue);
    });

    test('restore sets the state without any taps', () {
      final unlock = TapUnlock()
        ..tap()
        ..restore(armed: true);

      expect(unlock.isArmed, isTrue);
      expect(unlock.taps, isZero);
    });
  });

  group('the pose', () {
    test('a board holds the body out of the water', () {
      final swim = SwimState();
      _run(1, (dt) => swim.update(dt, inWater: true));
      final sunkSwimming = swim.sinkFraction;

      swim.onBoard = true;

      expect(sunkSwimming, greaterThan(0.3));
      expect(swim.sinkFraction, isZero);
      // The wobble stays: a board on water still rocks, and losing it would
      // make the bean read as standing on glass.
      expect(swim.wobble.abs(), greaterThan(0));
    });

    test('a board on dry land is not surfing', () {
      final swim = SwimState()..onBoard = true;
      _run(1, (dt) => swim.update(dt, inWater: false));

      expect(swim.isSurfing, isFalse);
    });

    test('the dive arc still fires on entry with a board', () {
      final swim = SwimState()
        ..onBoard = true
        ..update(1 / 60, inWater: true);

      // Splashing in and popping up on the board reads far better than
      // gliding in upright, so the arc is deliberately kept.
      expect(swim.isDiving, isTrue);
      expect(swim.diveLift, greaterThan(0));
    });

    test('surfing needs both the board and the water', () {
      final swim = SwimState();
      _run(1, (dt) => swim.update(dt, inWater: true));

      expect(swim.isSurfing, isFalse);
      swim.onBoard = true;
      expect(swim.isSurfing, isTrue);
    });
  });

  group('the bean', () {
    BeanComponent beanAt(double x, double y, {required GameMap map}) =>
        BeanComponent(
          position: Vector2(x, y),
          animation: BeanAnimation(maxSpeed: 140),
          map: map,
        );

    test('a board in the sea puts the bean on it', () {
      final bean = beanAt(_seaX, _seaY, map: _beach)..hasBoard = true;
      _run(1, bean.update);

      expect(bean.hasBoard, isTrue);
      expect(bean.swim.isSurfing, isTrue);
      expect(bean.swim.sinkFraction, isZero);
    });

    test('a board in the conference pool is no board at all', () {
      final bean = beanAt(
        WorldLayout.pool.centerX,
        WorldLayout.pool.centerY,
        map: _conference,
      )..hasBoard = true;
      _run(1, bean.update);

      // The map said `null`, so nothing here draws one — the whole of what
      // "no surfing on the conference" costs.
      expect(bean.hasBoard, isTrue);
      expect(bean.swim.onBoard, isFalse);
      expect(bean.swim.isSurfing, isFalse);
      expect(bean.swim.sinkFraction, greaterThan(0.3));
    });

    test('stepping onto the raft leaves the board behind', () {
      const raft = BeachLayout.raft;
      final bean = beanAt(
        (raft.left + raft.right) / 2,
        (raft.top + raft.bottom) / 2,
        map: _beach,
      )..hasBoard = true;
      _run(1, bean.update);

      // A dry platform wins over the water under it, exactly as it already
      // does for swimming.
      expect(bean.swim.isSurfing, isFalse);
    });

    test('walking out of the sea puts the board away', () {
      final bean = beanAt(_seaX, _seaY, map: _beach)..hasBoard = true;
      _run(1, bean.update);
      expect(bean.swim.isSurfing, isTrue);

      bean.position.setValues(BeachLayout.hintBeanX, BeachLayout.hintBeanY);
      _run(1, bean.update);

      expect(bean.swim.isSurfing, isFalse);
    });

    test('renders without throwing, on the board and off it', () {
      for (final hasBoard in [true, false]) {
        final bean = beanAt(_seaX, _seaY, map: _beach)..hasBoard = hasBoard;
        _run(1, bean.update);
        expect(() => bean.renderTree(_throwawayCanvas()), returnsNormally);
      }
    });
  });
}

/// A canvas that records into nothing, for a render smoke test.
Canvas _throwawayCanvas() => Canvas(PictureRecorder());
