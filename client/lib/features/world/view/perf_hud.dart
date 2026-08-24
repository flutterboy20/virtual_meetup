import 'dart:async';

import 'package:client/features/world/view/hud_chip.dart';
import 'package:client/game/frame_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Whether the on-screen frame readout is compiled in.
///
/// Supplied as `--dart-define=PERF_HUD=true`. A build flag rather than a
/// setting inside the app, for two reasons: nobody at the conference should
/// be able to turn a debug readout on over somebody's shoulder, and a
/// constant false lets the tree-shaker remove the whole thing from the bundle
/// that actually ships — which matters, because cold-load weight is one of
/// the things this readout exists to measure.
const bool perfHudEnabled = bool.fromEnvironment('PERF_HUD');

/// A small readout of what the frame rate is really doing, for profiling on a
/// real device.
///
/// This exists because the target is a mid-range Android phone on cellular,
/// and there is no DevTools on the end of that. You cannot attach a profiler
/// to a phone somebody is holding in a hall, but you can read four numbers
/// off the screen while you walk into a crowd — which is the measurement
/// Phase 7 actually needs.
///
/// Renders nothing at all unless [perfHudEnabled].
class PerfHud extends StatefulWidget {
  /// Creates the readout.
  const PerfHud({super.key});

  /// How often the readout repaints.
  ///
  /// Three times a second: fast enough to react as you walk into the crowd,
  /// slow enough that the readout is not itself a source of jank. It is
  /// deliberately decoupled from the frame callback — rebuilding a widget on
  /// every frame timing would mean the profiler caused the frames it reports.
  static const Duration refreshInterval = Duration(milliseconds: 333);

  @override
  State<PerfHud> createState() => _PerfHudState();
}

class _PerfHudState extends State<PerfHud> {
  final FrameProfile _profile = FrameProfile();
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    if (!perfHudEnabled) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _refresh = Timer.periodic(
      PerfHud.refreshInterval,
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _refresh?.cancel();
    if (perfHudEnabled) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    }
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _profile.record(
        buildMicros: timing.buildDuration.inMicroseconds,
        rasterMicros: timing.rasterDuration.inMicroseconds,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!perfHudEnabled) return const SizedBox.shrink();
    return HudChip(
      // Tapping restarts the measurement: the numbers from the empty lobby
      // you walked out of say nothing about the crowd you are standing in.
      onTap: () => setState(_profile.reset),
      child: Text(
        _profile.summary,
        style: const TextStyle(
          fontFeatures: [FontFeature.tabularFigures()],
          fontSize: 11,
        ),
      ),
    );
  }
}
