import 'dart:math';

/// What kind of crowd a load run simulates.
///
/// The scenario is the single most important knob on this tool, because the
/// three shapes below produce wildly different server load from the *same*
/// number of bots. A run that only ever tests [spread] is a run that will
/// report a comfortable ceiling and then fall over at 09:30 on the day.
enum LoadScenario {
  /// Bots wander the whole map.
  ///
  /// The flattering case. Every interest cell holds a handful of people, the
  /// culling looks free, and the snapshot size barely moves as the swarm
  /// grows. Useful as a control, misleading on its own.
  spread,

  /// Most bots crowd near the atrium spawn point.
  ///
  /// The realistic worst case, and the one the interest grid is worst at: one
  /// hot cell with everybody in it, so every player is inside every other
  /// player's interest block and the grid buys nothing. What saves it is the
  /// neighbour cap, and this is the scenario that proves the cap is doing the
  /// saving.
  cluster,

  /// Bots join and leave continuously while the rest walk around.
  ///
  /// Nothing about a steady swarm exercises the join and leave paths, which
  /// is exactly where a long event leaks: an orphaned grid entry, a session
  /// that keeps its seat forever, a socket that is never really closed. A
  /// flat player count with a rising memory line is the signature, and only
  /// churn produces it.
  churn;

  /// Parses a `--scenario` value, or returns `null` if it names none of them.
  static LoadScenario? parse(String raw) {
    final name = raw.trim().toLowerCase();
    for (final scenario in values) {
      if (scenario.name == name) return scenario;
    }
    return null;
  }

  /// Every scenario name, for a usage message.
  static String get names => values.map((s) => s.name).join(', ');

  /// How tightly this scenario packs bots around spawn, in world units.
  ///
  /// `null` means "anywhere on the floor". The clustered value is deliberately
  /// smaller than the atrium itself: a crowd does not distribute itself
  /// evenly over a room, it bunches at the door and around whoever is talking.
  double? get clusterRadius => switch (this) {
    LoadScenario.spread => null,
    LoadScenario.cluster => 200,
    LoadScenario.churn => null,
  };

  /// What fraction of the swarm is recycled every minute.
  ///
  /// Zero for the steady scenarios. A fifth of the room per minute is a hard
  /// but not absurd figure for a conference — it is roughly what a session
  /// changeover looks like, compressed.
  double get churnFraction => switch (this) {
    LoadScenario.spread => 0,
    LoadScenario.cluster => 0,
    LoadScenario.churn => 0.2,
  };

  /// A phrase for the console, so a log line says what was actually run.
  String get description => switch (this) {
    LoadScenario.spread => 'wandering the whole map',
    LoadScenario.cluster => 'crowded at the atrium spawn',
    LoadScenario.churn => 'wandering, with continuous join/leave',
  };
}

/// Spreads [count] connections over [over], as a gap between each one.
///
/// Connecting 200 sockets in the same millisecond measures the accept queue,
/// not the running server, and it produces a spike in every graph that then
/// has to be explained away. A conference fills up over minutes.
///
/// Returns [Duration.zero] when there is nothing to spread — one bot, or no
/// ramp asked for — so the caller never has to special-case it.
Duration rampGap({required int count, required Duration over}) {
  if (count <= 1 || over <= Duration.zero) return Duration.zero;
  return Duration(microseconds: over.inMicroseconds ~/ (count - 1));
}

/// Decides how many bots leave and rejoin on each churn step.
///
/// Pure accumulator maths, kept out of the timer so it can be tested without
/// waiting a real minute. The fractional remainder is carried rather than
/// dropped: at 50 bots and 20%/min a step of one second is due 0.167 of a
/// bot, and rounding that to zero every time would mean no churn at all.
class ChurnPlan {
  /// Creates a plan that recycles [fractionPerMinute] of [count] each minute.
  ChurnPlan({required this.count, required this.fractionPerMinute});

  /// How many bots are in the swarm.
  final int count;

  /// The share of the swarm replaced every minute, as a fraction of one.
  final double fractionPerMinute;

  double _elapsed = 0;
  int _issued = 0;

  /// How many bots this plan still owes, below the next whole one.
  double get owed => perSecond * _elapsed - _issued;

  /// Bots recycled per second at this rate.
  double get perSecond => count * fractionPerMinute / 60;

  /// Advances by [dt] seconds and returns how many bots to recycle now.
  ///
  /// Measured against total elapsed time rather than by adding up per-step
  /// remainders, so a long run cannot drift away from the rate that was
  /// asked for. The epsilon is not superstition: 200 bots at a fifth per
  /// minute is 0.666… a second, and sixty of those sums to 39.999999, which
  /// would quietly turn "40 a minute" into 39 forever.
  int take(double dt) {
    if (dt <= 0 || fractionPerMinute <= 0 || count <= 0) return 0;
    _elapsed += dt;
    final due = (perSecond * _elapsed + 1e-6).floor() - _issued;
    if (due <= 0) return 0;
    // A churn step that tried to recycle the entire swarm at once would be a
    // disconnect storm, which is a different test with a different name.
    final capped = min(due, count);
    _issued += capped;
    return capped;
  }
}
