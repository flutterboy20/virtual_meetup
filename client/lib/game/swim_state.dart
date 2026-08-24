import 'dart:math' as math;

/// How submerged one bean is, and what it is doing about it.
///
/// Pure maths — no `Canvas`, no `Component` — for the same reason
/// `BeanAnimation` is: the dive is a *feel*, and a feel that can only be tuned
/// by running the game and staring at it does not get tuned.
///
/// Every value here is derived from one boolean per frame: is this bean's
/// position inside the water. That boolean is computed locally from
/// `WorldLayout.isWater`, on **every** client, for **every** bean — the local
/// one and every remote one alike. Nothing about swimming travels on the wire,
/// so a second device sees the same dive at the same moment for free.
class SwimState {
  /// Creates a dry bean.
  SwimState({
    this.submergeResponsiveness = 9,
    this.diveDuration = 0.42,
    this.diveHeight = 13,
    this.wobbleCyclesPerSecond = 1.15,
    this.wobbleWidth = 1.9,
  });

  /// How deep the body sinks at full submersion, as a fraction of its height.
  ///
  /// Just under half: the visor has to stay above the waterline or the bean
  /// stops having a face, and a face is the whole reason anybody cares which
  /// bean is theirs.
  static const double submergedFraction = 0.46;

  /// How fast submersion eases towards its target, per second.
  ///
  /// Eased rather than switched, because the boundary is a hard rectangle and
  /// a bean walking along the lip would otherwise pop between two poses.
  final double submergeResponsiveness;

  /// How long the entry arc lasts, in seconds.
  final double diveDuration;

  /// Peak height of the entry arc, in world units.
  final double diveHeight;

  /// Idle bobbing on the surface, in cycles per second.
  final double wobbleCyclesPerSecond;

  /// Peak sideways sway while swimming, in world units.
  final double wobbleWidth;

  /// Whether this bean is standing on a board rather than in the water.
  ///
  /// One settable bool, and everything it changes is in two getters below.
  /// It is set by the bean's owner from a *player* fact (`hasBoard`) and a
  /// *map* fact (does this map allow surfing) — never derived here, because
  /// this class knows nothing about either.
  bool onBoard = false;

  double _submersion = 0;
  double _diveElapsed = -1;
  double _phase = 0;
  bool _wasInWater = false;

  /// How submerged the bean is, from 0 (dry) to 1 (swimming).
  double get submersion => _submersion;

  /// Whether the bean is in the water at all right now.
  bool get isSwimming => _wasInWater;

  /// Whether the entry arc is still playing.
  bool get isDiving => _diveElapsed >= 0 && _diveElapsed < diveDuration;

  /// How far the body is lifted by the entry arc, in world units.
  ///
  /// A half-sine over [diveDuration]: up off the deck, over, and down into the
  /// water. There is deliberately **no jump button** anywhere in this project —
  /// a free-standing jump would need a new field on `PlayerPosition` and a
  /// protocol version bump to buy a hop. The dive gives the same visual payoff
  /// for nothing, because entering the water is already derivable from the
  /// position stream everybody already receives.
  double get diveLift {
    if (!isDiving) return 0;
    return diveHeight * math.sin(math.pi * (_diveElapsed / diveDuration));
  }

  /// Sideways sway of a floating body, in world units.
  ///
  /// Kept while [onBoard]. A board on water still rocks, and a bean standing
  /// dead still on the sea would read as standing on glass.
  double get wobble => wobbleWidth * _submersion * math.sin(_phase);

  /// How much of the body is hidden below the waterline, in body fractions.
  ///
  /// Zero on a board: the bean is on the sea, not in it, so the waterline
  /// clip in `BeanComponent` never engages and the whole body is drawn.
  ///
  /// The dive arc is deliberately **not** suppressed. Entering the water is
  /// the best-looking half-second on this map, and a surfer who splashes in
  /// and pops up standing reads far better than one who glides in upright.
  double get sinkFraction => onBoard ? 0 : submergedFraction * _submersion;

  /// Whether a board should be drawn under this bean right now.
  ///
  /// The surfing rule, in the one place that owns the pose: carrying a board
  /// is not surfing, being in the water on one is. The submersion term is
  /// what makes the board fade in and out with the shoreline instead of
  /// popping.
  bool get isSurfing => onBoard && _submersion > 0.01;

  /// Advances the state by [dt] seconds for a bean that is or is not
  /// [inWater].
  void update(double dt, {required bool inWater}) {
    if (dt <= 0) return;

    // The one edge that matters. Fired here as well as in `WaterWatcher`
    // because this is about how *this* bean is drawn, and that has to be true
    // even for a bean nobody is watching splash.
    if (inWater && !_wasInWater) _diveElapsed = 0;
    _wasInWater = inWater;

    if (_diveElapsed >= 0) {
      _diveElapsed += dt;
      if (_diveElapsed >= diveDuration) _diveElapsed = -1;
    }

    final target = inWater ? 1.0 : 0.0;
    _submersion +=
        (target - _submersion) * (1 - math.exp(-submergeResponsiveness * dt));
    _phase =
        (_phase + 2 * math.pi * wobbleCyclesPerSecond * dt) % (2 * math.pi);
  }
}
