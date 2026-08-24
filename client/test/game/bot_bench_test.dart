@Tags(['bench'])
library;

import 'dart:ui';

import 'package:client/game/beach_map.dart';
import 'package:client/game/bot_component.dart';
import 'package:client/game/world_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// Task 12.5's bench, in the shape 10.4 set and 11.8 reused: 300 frames,
// median rather than mean, one `PictureRecorder` per frame so the recording
// cost is measured the way the engine pays it.
//
// The number this is priced against is Phase 11's: **40 beans at 0.144 ms**,
// or ~0.0036 ms per bean. Twenty-one bots plus their brains and their
// collision should land around 0.10 ms, and the phase's gate is 0.3 ms — over
// that, the roster gets cut and the measured number goes in the task note.
//
// It **records** a display list rather than rasterising one, for the same
// reason the water and board benches do: what this phase added is our own
// per-frame work, and rasterising would drown that in Skia's cost and in
// whatever GPU the host happens to have.
//
// Tagged `bench` so a normal `flutter test` run skips it. Run it with:
//
//   fvm flutter test --tags bench test/game/bot_bench_test.dart

/// How many frames each measurement runs for.
const int _frames = 300;

/// How many frames are thrown away first.
const int _warmup = 30;

/// The phase's gate, in milliseconds.
const double _gate = 0.3;

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

/// One map's whole roster, every bot on camera.
List<BotComponent> _roster(GameMap map, {required bool visible}) => buildBots(
  specs: map.bots,
  map: map,
  isVisible: (_, _) => visible,
);

/// One frame of a roster: advance every bot, then record them all.
void Function() _frame(List<BotComponent> bots) => () {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  for (final bot in bots) {
    bot
      ..update(1 / 60)
      ..render(canvas);
  }
  recorder.endRecording().dispose();
};

/// Prints a bench line. Printing *is* the output of a bench.
// ignore: avoid_print
void _report(String line) => print(line);

void main() {
  test('the conference roster, brains and collision included', () {
    final bots = _roster(ConferenceMap.empty, visible: true);
    // Settled first, so the measurement is of bots walking rather than of
    // bots all standing still on their opening dwell.
    for (var i = 0; i < 600; i++) {
      for (final bot in bots) {
        bot.update(1 / 60);
      }
    }

    final onScreen = _median(_frame(bots));
    final offScreen = _median(
      _frame(_roster(ConferenceMap.empty, visible: false)),
    );

    _report(
      'bots=${bots.length}  on-camera=${onScreen.toStringAsFixed(3)}ms  '
      'culled=${offScreen.toStringAsFixed(3)}ms  '
      'gate=${_gate.toStringAsFixed(3)}ms',
    );

    // The gate the phase wrote down. Over it, the roster gets cut and the
    // measured number goes into the task note — a performance claim with no
    // measurement behind it is the one thing this phase can get wrong quietly.
    expect(onScreen, lessThan(_gate));
    // And culling really does cost nothing: a bot off camera is one
    // rectangle test and no brain, no collision, no animation, no draw.
    expect(offScreen, lessThan(onScreen));
  });

  test('the beach roster', () {
    const beach = BeachMap();
    final bots = _roster(beach, visible: true);
    for (var i = 0; i < 600; i++) {
      for (final bot in bots) {
        bot.update(1 / 60);
      }
    }

    final onScreen = _median(_frame(bots));

    _report(
      'bots=${bots.length}  on-camera=${onScreen.toStringAsFixed(3)}ms  '
      'gate=${_gate.toStringAsFixed(3)}ms',
    );

    expect(onScreen, lessThan(_gate));
  });
}
