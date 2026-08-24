@Tags(['bench'])
library;

import 'dart:ui';

import 'package:client/game/beach_map.dart';
import 'package:client/game/bean_animation.dart';
import 'package:client/game/bean_component.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

// The render side of task 11.8, in the shape 10.4 set: 300 frames, median
// rather than mean, one `PictureRecorder` per frame so the recording cost is
// measured the way the engine pays it.
//
// The honest worst case for this phase is the neighbour cap's worth of beans
// all surfing at once — 40 boards drawn on top of a scene that already has 40
// beans in it. This measures exactly that against the same 40 beans swimming,
// which is the Phase 10 baseline for this comparison.
//
// It **records** a display list rather than rasterising one, for the same
// reason the water bench does: what this phase added is our own per-frame
// work — five more shapes per surfing bean — and rasterising would drown that
// in Skia's cost and in whatever GPU the host happens to have.
//
// Tagged `bench` so a normal `flutter test` run skips it. Run it with:
//
//   fvm flutter test --tags bench test/game/board_bench_test.dart

/// How many frames each measurement runs for.
const int _frames = 300;

/// How many frames are thrown away first.
const int _warmup = 30;

/// The neighbour cap: the most beans that can ever be on screen at once.
const int _beans = 40;

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

/// Forty beans scattered across the sea, on boards or not.
List<BeanComponent> _crowd({required bool onBoards}) {
  const beach = BeachMap();
  return [
    for (var i = 0; i < _beans; i++)
      BeanComponent(
        // Spread over the sea band (y 420..900) so no two overlap exactly.
        position: Vector2(40 + (i % 10) * 115, 470 + (i ~/ 10) * 100),
        animation: BeanAnimation(maxSpeed: 140),
        map: beach,
      )..hasBoard = onBoards,
  ];
}

/// One frame of the whole crowd: advance every bean, then record them all.
void Function() _frame(List<BeanComponent> beans) => () {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  for (final bean in beans) {
    bean
      ..update(1 / 60)
      ..render(canvas);
  }
  recorder.endRecording().dispose();
};

/// Prints a bench line. Printing *is* the output of a bench.
// ignore: avoid_print
void _report(String line) => print(line);

void main() {
  test('40 surfing beans against 40 swimming ones', () {
    final swimming = _crowd(onBoards: false);
    final surfing = _crowd(onBoards: true);

    // Settled first, so both crowds are fully in the water rather than one
    // of them still easing its submersion in from zero.
    for (var i = 0; i < 120; i++) {
      for (final bean in [...swimming, ...surfing]) {
        bean.update(1 / 60);
      }
    }

    final before = _median(_frame(swimming));
    final after = _median(_frame(surfing));

    _report(
      'beans=$_beans  swimming=${before.toStringAsFixed(3)}ms  '
      'surfing=${after.toStringAsFixed(3)}ms  '
      'delta=${(after - before).toStringAsFixed(3)}ms',
    );

    // Not a threshold on the absolute number, which is a property of the
    // machine. The claim is that the worst case stays a fraction of a 16ms
    // frame — five extra vector shapes per bean cannot be anything else.
    expect(after, lessThan(8));
  });

  test('a board costs nothing at all on dry land', () {
    const beach = BeachMap();
    final onSand = [
      for (var i = 0; i < _beans; i++)
        BeanComponent(
          position: Vector2(60 + (i % 10) * 110, 230 + (i ~/ 10) * 50),
          animation: BeanAnimation(maxSpeed: 140),
          map: beach,
        )..hasBoard = true,
    ];
    for (var i = 0; i < 60; i++) {
      for (final bean in onSand) {
        bean.update(1 / 60);
      }
    }

    final dry = _median(_frame(onSand));

    _report('beans=$_beans  dry with boards=${dry.toStringAsFixed(3)}ms');

    // Nothing is drawn: `isSurfing` is false out of the water, so the whole
    // feature is one bool read per bean per frame here.
    expect(onSand.every((bean) => !bean.swim.isSurfing), isTrue);
    expect(dry, lessThan(8));
  });
}
