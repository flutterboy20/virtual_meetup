import 'dart:math' as math;

/// How much detail the water is currently drawing.
///
/// Three steps, not a continuous dial. A dial would mean the surface is
/// subtly different on every device and impossible to reason about; three
/// named states are three things you can look at and recognise.
enum WaterDetail {
  /// Everything: the full crest lattice, all the bands, wakes at full rate.
  full,

  /// Half the crests and slower wakes. The surface still moves.
  reduced,

  /// Static bands, no crests, no particles. Water that is still blue and
  /// still readable, and costs almost nothing.
  flat;

  /// The tier one step cheaper than this one.
  WaterDetail get next => switch (this) {
    WaterDetail.full => WaterDetail.reduced,
    WaterDetail.reduced => WaterDetail.flat,
    WaterDetail.flat => WaterDetail.flat,
  };

  /// The tier one step richer than this one.
  WaterDetail get previous => switch (this) {
    WaterDetail.full => WaterDetail.full,
    WaterDetail.reduced => WaterDetail.full,
    WaterDetail.flat => WaterDetail.reduced,
  };
}

/// Decides how much water detail this device can currently afford.
///
/// **Driven by measured frame time, not by swim state.** The expensive frame
/// is "thirty people swimming near me", and that costs the same whether the
/// local bean is wet or dry — a state trigger would miss it entirely. It
/// would also read as the water freezing the instant you stepped into it,
/// which is the exact moment the effect is meant to be enjoyed.
///
/// Pure arithmetic over a p95 in milliseconds: no `Canvas`, no `Component`,
/// no binding. Same shape as `BeanAnimation` and `SplashField`, and for the
/// same reason — a thing that can only be tuned by running the game and
/// staring at it does not get tuned.
///
/// **The hysteresis is the point of the class.** A bare threshold at the
/// budget would flip tiers on every frame that landed near it, and a surface
/// that changes detail twice a second is far more noticeable than one that is
/// simply cheap. So dropping needs [dropAfter] seconds continuously over
/// budget, and climbing back needs [riseAfter] seconds continuously *below*
/// [recoverFraction] of it — a longer wait, against a stricter bar, in the
/// direction that costs more.
class WaterLod {
  /// Creates a profile that starts at [WaterDetail.full].
  ///
  /// Optimistic on purpose: most devices can afford everything, and starting
  /// low would mean every session opens on flat water and climbs out of it
  /// three seconds later, in full view.
  WaterLod({
    this.budgetMillis = defaultBudgetMillis,
    this.dropAfter = 1,
    this.riseAfter = 3,
    this.recoverFraction = 0.75,
  });

  /// The per-frame budget at 60fps, in milliseconds.
  ///
  /// The same 16667µs `FrameProfile` judges a janked frame against, in the
  /// units this class is fed in.
  static const double defaultBudgetMillis = 16.667;

  /// How many crests the full tier scatters over the visible water.
  static const int fullCrests = 40;

  /// How many crests the reduced tier scatters.
  ///
  /// Half, and it is *every other lattice cell* rather than a tighter
  /// lattice — see `WaterComponent`. Re-spacing the lattice would make every
  /// remaining crest jump sideways at the moment the tier changed, which is
  /// the one thing a quality drop must not do.
  static const int reducedCrests = 20;

  /// The frame budget a p95 is judged against, in milliseconds.
  final double budgetMillis;

  /// How long p95 must stay over budget before a tier is dropped, in seconds.
  final double dropAfter;

  /// How long p95 must stay comfortably under before a tier is regained.
  final double riseAfter;

  /// How far under budget counts as "comfortable", as a fraction.
  ///
  /// Not 1.0. Recovering at the same threshold that triggered the drop is how
  /// a controller oscillates: the tier that made the frame cheap enough is
  /// immediately undone by the frame being cheap enough.
  final double recoverFraction;

  WaterDetail _detail = WaterDetail.full;
  double _over = 0;
  double _under = 0;

  /// The tier the water should draw at.
  WaterDetail get detail => _detail;

  /// How many crests to scatter over the visible water this frame.
  int get crestCount => switch (_detail) {
    WaterDetail.full => fullCrests,
    WaterDetail.reduced => reducedCrests,
    WaterDetail.flat => 0,
  };

  /// Whether the bands and the crests animate at all.
  bool get isAnimated => _detail != WaterDetail.flat;

  /// Whether splashes and wakes are emitted.
  bool get emitsParticles => _detail != WaterDetail.flat;

  /// How often a swimming bean drops a wake ring, in seconds.
  double get wakeInterval => wakeIntervalAt(_detail);

  /// How often a bean drops a wake ring at [detail], in seconds.
  ///
  /// [double.infinity] at [WaterDetail.flat], which the watcher reads as
  /// "never" without needing a second flag to mean the same thing.
  static double wakeIntervalAt(WaterDetail detail) => switch (detail) {
    WaterDetail.full => 0.35,
    WaterDetail.reduced => 0.6,
    WaterDetail.flat => double.infinity,
  };

  /// How often a **remote** bean drops a wake, given the local bean's state.
  ///
  /// One tier cheaper while the local bean is submerged. Surface detail is
  /// barely visible from inside the water — the camera is at the waterline
  /// and half the screen is the bean's own splash — so it is the cheapest
  /// thing in the scene to lose, and losing it shaves the worst frame in the
  /// game *before* the profile has noticed it is a bad one.
  ///
  /// Deliberately not applied to the local bean's own wake: that one is the
  /// feedback for what the player is doing right now.
  double remoteWakeInterval({required bool localIsSubmerged}) =>
      wakeIntervalAt(localIsSubmerged ? _detail.next : _detail);

  /// Advances by [dt] seconds against the frame profile's [p95Millis].
  ///
  /// A p95 of zero means nothing has been measured yet — a fresh profile, a
  /// test, a headless run — and is treated as "no evidence of trouble"
  /// rather than as a perfect frame, so it neither drops nor climbs.
  void update(double dt, {required double p95Millis}) {
    if (dt <= 0) return;
    if (p95Millis <= 0) return;

    if (p95Millis > budgetMillis) {
      _over += dt;
      _under = 0;
      if (_over >= dropAfter && _detail != WaterDetail.flat) {
        _detail = _detail.next;
        _over = 0;
      }
      return;
    }

    if (p95Millis <= budgetMillis * recoverFraction) {
      _under += dt;
      _over = 0;
      if (_under >= riseAfter && _detail != WaterDetail.full) {
        _detail = _detail.previous;
        _under = 0;
      }
      return;
    }

    // In the dead band between the two thresholds: under budget, but not
    // comfortably. Nothing changes, and neither timer runs — which is what
    // stops a frame time parked exactly on the boundary from slowly
    // accumulating its way into a tier change.
    _over = 0;
    _under = 0;
  }

  /// Forces a tier, for a benchmark or a test.
  ///
  /// Clears both timers with it, so the next [update] starts from a clean
  /// state rather than half way to a change it did not ask for.
  void force(WaterDetail detail) {
    _detail = detail;
    _over = 0;
    _under = 0;
  }

  /// The lattice spacing that scatters about [crests] points over [area].
  ///
  /// Clamped, because the two ends are both bad: too fine is the slideshow
  /// this whole task exists to avoid, and too coarse is one crest per screen,
  /// which reads as flat blue paint rather than as water.
  static double spacingFor(double area, int crests) {
    if (area <= 0 || crests <= 0) return maxSpacing;
    return math.sqrt(area / crests).clamp(minSpacing, maxSpacing);
  }

  /// The tightest the crest lattice is allowed to get, in world units.
  static const double minSpacing = 26;

  /// The loosest the crest lattice is allowed to get, in world units.
  static const double maxSpacing = 96;
}
