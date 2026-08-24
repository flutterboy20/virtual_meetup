import 'dart:math' as math;

/// What the client's frame rate has actually been doing.
///
/// Pure arithmetic over frame durations in microseconds — no bindings, no
/// widgets — so the thing that judges the frame rate can be tested without
/// running one.
///
/// The measurement that matters on a phone is **not** the average. An average
/// of 58fps describes both a perfectly smooth minute and a minute with two
/// half-second freezes in it, and only one of those is shippable. So this
/// keeps the average *and* the p95 *and* an explicit count of janked frames,
/// and the HUD shows all three.
///
/// "Total" here means build plus raster, which is the number a player feels.
/// Flutter runs those two phases on different threads and pipelines them, so
/// adding them slightly overstates wall-clock latency — deliberately, because
/// this is a budget check and the pessimistic reading is the safe one.
class FrameProfile {
  /// Creates an empty profile.
  FrameProfile({this.budget = defaultBudget, this.capacity = defaultCapacity});

  /// The per-frame budget at 60fps, in microseconds.
  ///
  /// A frame over this missed its slot: the previous image stayed on screen a
  /// beat longer than it should have, which reads as a stutter.
  static const int defaultBudget = 16667;

  /// How many recent frames are kept.
  ///
  /// About sixteen seconds at 60fps. Long enough that a busy scene shows its
  /// character, short enough that walking into a crowd changes the reading
  /// while you are standing in it — which is how you find the jank source.
  static const int defaultCapacity = 1000;

  /// The per-frame budget, in microseconds.
  final int budget;

  /// How many recent frames are retained.
  final int capacity;

  final List<int> _totals = [];

  int _frames = 0;
  int _janked = 0;
  int _worst = 0;

  /// Frames seen since the last [reset], including ones already evicted.
  int get frames => _frames;

  /// Frames that ran over [budget] since the last [reset].
  int get jankedFrames => _janked;

  /// The share of frames that missed their slot, from 0 to 1.
  double get jankRate => _frames == 0 ? 0 : _janked / _frames;

  /// The slowest frame since the last [reset], in milliseconds.
  double get worstMillis => _worst / 1000;

  /// The mean of the retained frames, in milliseconds.
  double get averageMillis {
    if (_totals.isEmpty) return 0;
    var sum = 0;
    for (final total in _totals) {
      sum += total;
    }
    return sum / _totals.length / 1000;
  }

  /// The 95th percentile of the retained frames, in milliseconds.
  ///
  /// The honest headline. Sorting a thousand ints on demand is fine because
  /// this is only ever read to paint one line of text a few times a second —
  /// a profiler that shows up in its own numbers is not a profiler.
  double get p95Millis {
    if (_totals.isEmpty) return 0;
    final sorted = List<int>.of(_totals)..sort();
    final index = math.min(
      sorted.length - 1,
      ((sorted.length - 1) * 0.95).round(),
    );
    return sorted[index] / 1000;
  }

  /// Frames per second implied by the mean retained frame.
  double get impliedFps {
    final average = averageMillis;
    return average <= 0 ? 0 : 1000 / average;
  }

  /// Records one frame that took [buildMicros] to build and
  /// [rasterMicros] to raster.
  void record({required int buildMicros, required int rasterMicros}) {
    final total = buildMicros + rasterMicros;
    _frames++;
    if (total > budget) _janked++;
    _worst = math.max(_worst, total);
    _totals.add(total);
    if (_totals.length > capacity) _totals.removeAt(0);
  }

  /// Forgets everything, so a fresh measurement can start.
  ///
  /// Used when walking into the crowd: the numbers from the empty lobby you
  /// walked out of are not evidence about the scene you are standing in.
  void reset() {
    _totals.clear();
    _frames = 0;
    _janked = 0;
    _worst = 0;
  }

  /// The one line the on-screen readout shows.
  String get summary =>
      '${impliedFps.toStringAsFixed(0)}fps  '
      'p95 ${p95Millis.toStringAsFixed(1)}ms  '
      'jank ${(jankRate * 100).toStringAsFixed(1)}%  '
      'worst ${worstMillis.toStringAsFixed(0)}ms';
}
