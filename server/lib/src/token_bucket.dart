import 'dart:math' as math;

/// How many of something may happen, and how fast.
///
/// The bucket arithmetic on its own, keyed by nothing. It holds up to [burst]
/// tokens and gains one back every [refill]; [allow] costs one, and an empty
/// bucket answers `false`.
///
/// A bucket rather than a flat "one every N milliseconds" cooldown because
/// the two behave differently in exactly the case that matters. A cooldown
/// punishes the person who claps three times when the speaker lands a joke —
/// which is the entire point of that feature. A bucket lets that through and
/// still cuts off the person holding the button down, because the burst is
/// spent and the refill is slow.
///
/// **Extracted rather than copied.** `EmoteLimiter` had this maths inside it,
/// keyed by player id and named for emotes. Phase 13 needed the same maths
/// keyed by nothing at all — a socket that has never joined has no id to key
/// on, and those are precisely the sockets a flood is made of. Two copies of
/// a rule is how they stop agreeing, which is the same reason `protocol/`
/// exists. `EmoteLimiter` keeps its map and its public shape and delegates
/// here.
class TokenBucket {
  /// Creates a full bucket.
  ///
  /// It starts full rather than empty: the first thing a newcomer does is
  /// free and instant, which is what makes a button feel connected to the
  /// tap. A bucket that filled up over time would throttle the one action
  /// nobody could have abused yet.
  ///
  /// [now] is injectable so a rate limit can be unit-tested against a clock
  /// the test drives, instead of by sleeping.
  TokenBucket({
    required this.burst,
    required this.refill,
    DateTime Function() now = DateTime.now,
    // A named parameter cannot be private, so this cannot be an initializing
    // formal.
    // ignore: prefer_initializing_formals
  }) : _now = now {
    if (burst < 1) {
      throw ArgumentError.value(burst, 'burst', 'must be at least 1');
    }
    if (refill <= Duration.zero) {
      throw ArgumentError.value(refill, 'refill', 'must be positive');
    }
    _tokens = burst.toDouble();
    _at = _now();
  }

  /// The most tokens this bucket can hold.
  final int burst;

  /// How long one spent token takes to come back.
  final Duration refill;

  final DateTime Function() _now;

  late double _tokens;
  late DateTime _at;

  /// How many whole tokens are in hand, as of the last time it was counted.
  ///
  /// Exposed for tests and for nothing else. It does **not** refill on read:
  /// a getter with a side effect on the clock would make two consecutive
  /// reads disagree for reasons nothing in the calling code can see.
  double get tokens => _tokens;

  /// Whether the next thing may happen, spending a token if so.
  ///
  /// Asking is spending: there is no separate `take`, because a caller that
  /// could check without consuming would eventually check twice and send
  /// twice.
  bool allow() {
    final at = _now();
    final elapsed = at.difference(_at).inMicroseconds;
    if (elapsed > 0) {
      _tokens = math.min(
        burst.toDouble(),
        _tokens + elapsed / refill.inMicroseconds,
      );
      _at = at;
    }

    if (_tokens < 1) return false;
    _tokens -= 1;
    return true;
  }
}
