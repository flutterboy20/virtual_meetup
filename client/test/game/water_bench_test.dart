@Tags(['bench'])
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/water_component.dart';
import 'package:client/game/water_lod.dart';
import 'package:client/game/world_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

// A repeatable bench for the water, in the shape task 9.3 set.
//
// Three hundred frames, median rather than mean, one `PictureRecorder` per
// frame so the recording cost is measured the way the engine pays it. The
// median is the honest number here: a mean over 300 frames is moved by one GC
// pause, and this is a comparison between two implementations rather than a
// latency budget.
//
// It **records** a display list rather than rasterising one. That is the right
// measurement for this change: the task removed *our* per-frame work — the
// lattice walk, the arc calls, the shader allocation — and left the
// rasteriser's job alone. Rasterising here would drown the difference in
// Skia's own cost and in whatever GPU the host machine happens to have.
//
// Tagged `bench` so a normal `flutter test` run skips it: 300 recordings of a
// sea is CPU a CI run does not need to spend on every commit. Run it with:
//
//   fvm flutter test --tags bench test/game/water_bench_test.dart

/// How many frames each measurement runs for.
const int _frames = 300;

/// How many frames are thrown away first, so a cache built on frame one is
/// not one of the samples.
const int _warmup = 30;

/// The beach's sea: 1200x480, which is 13.8x the pool's area.
const WorldRect _sea = WorldRect(0, 420, 1200, 900);

/// What a phone shows at zoom 1.6: about 244x527 world units.
Rect _viewAt(double x, double y) =>
    Rect.fromCenter(center: Offset(x, y), width: 244, height: 527);

Rect _rectOf(WorldRect region) =>
    Rect.fromLTRB(region.left, region.top, region.right, region.bottom);

/// A map holding one water rect and nothing else.
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

/// Times [frame] over [_frames] runs and returns the median, in milliseconds.
double _median(void Function() frame) {
  for (var i = 0; i < _warmup; i++) {
    frame();
  }
  final samples = <int>[];
  for (var i = 0; i < _frames; i++) {
    final watch = Stopwatch()..start();
    frame();
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2] / 1000;
}

/// One frame of the real component: advance it, then record it.
void Function() _after(WaterComponent water) => () {
  final recorder = PictureRecorder();
  water
    ..update(1 / 60)
    ..render(Canvas(recorder));
  recorder.endRecording().dispose();
};

/// Draws water the way Phase 9 did: a fixed 40 crests over the **whole** rect,
/// and a fresh gradient shader every frame.
///
/// Kept here rather than left in the git history, so the "before" number can
/// be re-measured on whatever machine is reading the task note instead of
/// being taken on trust from a machine nobody has.
class _PhaseNineWater {
  _PhaseNineWater(this.rect, {this.crestCount = 40});

  final Rect rect;

  /// How many crests to scatter over the whole rect.
  ///
  /// Forty is literally what Phase 9 drew. The area-scaled figure is the
  /// obvious "fix" for a sea that looks dead, and measuring it is the point:
  /// it is the slideshow this task exists to avoid.
  final int crestCount;

  static const int bandCount = 7;
  static const Color deep = Color(0xFF1C6E8C);
  static const Color shallow = Color(0xFF57BEDA);
  static const Color crestColor = Color(0x59EAFBFF);

  double _phase = 0;

  void frame() {
    _phase = (_phase + (1 / 60) * 0.9) % (2 * math.pi);
    final recorder = PictureRecorder();
    _render(Canvas(recorder));
    recorder.endRecording().dispose();
  }

  void _render(Canvas canvas) {
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(26));
    canvas
      ..save()
      ..clipRRect(shape)
      // Rebuilt every frame, which is what the cached paint replaced.
      ..drawRect(
        rect,
        Paint()
          ..shader = Gradient.linear(
            rect.topCenter,
            rect.bottomCenter,
            const [shallow, deep],
          ),
      );

    for (var i = 0; i < bandCount; i++) {
      final t = (_phase + i * 2 * math.pi / bandCount) % (2 * math.pi);
      final y = rect.top + rect.height * (0.5 + 0.5 * math.sin(t));
      final alpha = 0.05 + 0.05 * (1 + math.cos(t)) / 2;
      canvas.drawRect(
        Rect.fromLTRB(rect.left, y - 9, rect.right, y + 9),
        Paint()..color = shallow.withValues(alpha: alpha),
      );
    }

    final crest = Paint()
      ..color = crestColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < crestCount; i++) {
      final u = ((i * 7919) % 1000) / 1000;
      final v = ((i * 6337) % 997) / 997;
      final x = rect.left + 12 + u * (rect.width - 24);
      final y = rect.top + 12 + v * (rect.height - 24);
      final nod = math.sin(_phase * 1.6 + i * 0.7);
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(x, y + nod * 3),
          width: 20 + nod * 4,
          height: 9,
        ),
        math.pi * 1.08,
        math.pi * 0.84,
        false,
        crest,
      );
    }
    canvas.restore();
  }
}

/// How many crests an area-scaled lattice would put over the sea.
///
/// The pool is 220x190 and carried 40, so the same density over a 1200x480
/// sea is 40 x 13.8.
const int _areaScaledCrests = 550;

/// How many of a fixed, whole-rect lattice of [count] crests land in [view].
///
/// The readability half of the measurement. Cost means nothing on its own:
/// the cheapest possible water is a blue rectangle.
int _visibleCrests(Rect rect, Rect view, int count) {
  var visible = 0;
  for (var i = 0; i < count; i++) {
    final u = ((i * 7919) % 1000) / 1000;
    final v = ((i * 6337) % 997) / 997;
    final x = rect.left + 12 + u * (rect.width - 24);
    final y = rect.top + 12 + v * (rect.height - 24);
    if (view.contains(Offset(x, y))) visible++;
  }
  return visible;
}

/// Prints a bench line. Printing *is* the output of a bench.
// ignore: avoid_print
void _report(String line) => print(line);

void main() {
  group('water rendering cost', () {
    test('the sea: three ways of drawing it', () {
      // There are two "befores" here, and reporting only the first would be
      // dishonest. Phase 9's fixed forty crests over a sea 13.8x the pool's
      // area is *cheap*, and it looks like flat blue paint — about nine
      // crests fall on a phone screen. The comparison that matters is against
      // the version that looks right, which is the area-scaled one.
      final view = _viewAt(600, 640);
      final water = WaterComponent(
        swimmers: () => const [],
        map: _WaterOnlyMap(const [_sea]),
        visibleWorldRect: () => view,
      );

      final fixed = _median(_PhaseNineWater(_rectOf(_sea)).frame);
      final scaled = _median(
        _PhaseNineWater(_rectOf(_sea), crestCount: _areaScaledCrests).frame,
      );
      final after = _median(_after(water));

      final onScreenBefore = _visibleCrests(_rectOf(_sea), view, 40);
      final onScreenScaled = _visibleCrests(
        _rectOf(_sea),
        view,
        _areaScaledCrests,
      );
      final onScreenAfter = water.crestLattice(_rectOf(_sea), view).length;

      // Reported rather than asserted on: a threshold here would be a test
      // that fails on somebody else's laptop, and the number belongs in the
      // task note, not in an assertion.
      _report(
        'sea 1200x480, phone viewport 244x527:\n'
        '  Phase 9, fixed 40      ${fixed.toStringAsFixed(3)} ms  '
        '($onScreenBefore crests on screen — reads as flat paint)\n'
        '  area-scaled, $_areaScaledCrests      ${scaled.toStringAsFixed(3)}'
        ' ms  ($onScreenScaled crests on screen)\n'
        '  viewport-scoped        ${after.toStringAsFixed(3)} ms  '
        '($onScreenAfter crests on screen)',
      );

      // The two things the change had to buy, as facts rather than as a
      // printed number: it is cheaper than the version that looks right, and
      // it looks right.
      expect(after, lessThan(scaled));
      expect(onScreenAfter, greaterThan(onScreenBefore));
    });

    test('the pool, to show the small case did not regress', () {
      const pool = WorldLayout.pool;
      final before = _median(_PhaseNineWater(_rectOf(pool)).frame);
      final after = _median(
        _after(
          WaterComponent(
            swimmers: () => const [],
            map: _WaterOnlyMap(const [pool]),
            visibleWorldRect: () => _viewAt(800, 995),
          ),
        ),
      );

      _report(
        'pool  220x190  whole-rect ${before.toStringAsFixed(3)} ms  ->  '
        'viewport-scoped ${after.toStringAsFixed(3)} ms',
      );

      expect(after, greaterThan(0));
    });

    test('the reduced and flat tiers, which a struggling phone falls to', () {
      double at(WaterDetail detail) => _median(
        _after(
          WaterComponent(
            swimmers: () => const [],
            map: _WaterOnlyMap(const [_sea]),
            visibleWorldRect: () => _viewAt(600, 640),
          )..lod.force(detail),
        ),
      );

      final reduced = at(WaterDetail.reduced);
      final flat = at(WaterDetail.flat);

      _report(
        'sea  reduced ${reduced.toStringAsFixed(3)} ms  '
        'flat ${flat.toStringAsFixed(3)} ms',
      );

      expect(flat, greaterThan(0));
    });
  });
}
