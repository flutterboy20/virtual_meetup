/// The three-tap ritual that arms the board, and the one tap that disarms it.
///
/// Pure state, no `Canvas` and no `Component`, for the same reason
/// `BeanAnimation` and `SwimState` are: this is a *feel*, and a feel that can
/// only be checked by walking a bean across a beach does not get checked.
///
/// **Three taps to arm, one to disarm.** Asymmetric on purpose: three taps is
/// the discovery ritual and has to feel deliberate, but somebody who wants
/// their board off is not in the mood to tap a prop three more times.
///
/// The [window] is the part that is easy to leave out and impossible to debug
/// afterwards. Without it, three accidental taps spread over an afternoon arm
/// the board and nobody has any idea why.
class TapUnlock {
  /// Creates an unlock that starts [armed] or not.
  TapUnlock({bool armed = false, this.tapsToArm = 3, this.window = 2.0}) {
    _armed = armed;
  }

  /// How many taps inside [window] it takes to arm.
  final int tapsToArm;

  /// How long a partial run of taps stays alive, in seconds.
  final double window;

  bool _armed = false;
  int _taps = 0;
  double _sinceLastTap = 0;

  /// Whether the board is currently in hand.
  bool get isArmed => _armed;

  /// How many taps of the current run have landed.
  ///
  /// Zero whenever the run has lapsed or the board is already armed. Exposed
  /// for the tests, which is the only honest way to check that the window
  /// resets rather than that it eventually stops working.
  int get taps => _taps;

  /// Advances the window by [dt] seconds.
  ///
  /// A partial run that goes quiet for longer than [window] is forgotten.
  /// Called from the game loop, and cheap enough to be: one add and one
  /// comparison, and only while a run is actually in progress.
  void update(double dt) {
    if (_taps == 0 || dt <= 0) return;
    _sinceLastTap += dt;
    if (_sinceLastTap > window) _taps = 0;
  }

  /// Registers one tap on the board, returning what it changed.
  ///
  /// Returns [TapUnlockResult.armed] or [TapUnlockResult.disarmed] on the tap
  /// that flipped it, and [TapUnlockResult.counting] on every other one — so
  /// the caller sends a message and raises a toast exactly once per change,
  /// rather than on every tap.
  TapUnlockResult tap() {
    if (_armed) {
      _armed = false;
      _taps = 0;
      _sinceLastTap = 0;
      return TapUnlockResult.disarmed;
    }

    // The lapse is checked here as well as in [update], so a tap that arrives
    // after a long gap starts a fresh run even if nothing ticked in between —
    // a backgrounded tab does not tick.
    if (_sinceLastTap > window) _taps = 0;
    _sinceLastTap = 0;
    _taps++;
    if (_taps < tapsToArm) return TapUnlockResult.counting;

    _taps = 0;
    _armed = true;
    return TapUnlockResult.armed;
  }

  /// Sets the armed state without any taps, e.g. from what was persisted.
  void restore({required bool armed}) {
    _armed = armed;
    _taps = 0;
    _sinceLastTap = 0;
  }
}

/// What one tap on the board did.
enum TapUnlockResult {
  /// It counted, and nothing has changed yet.
  counting,

  /// It was the last of the run: the board is in hand.
  armed,

  /// The board was in hand and has been put back.
  disarmed,
}
