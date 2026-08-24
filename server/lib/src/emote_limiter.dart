import 'package:server/src/token_bucket.dart';

/// How many emotes one player may throw, and how fast.
///
/// A token bucket, one per player. Every player holds up to [burst] tokens
/// and gains one back every [refill]; sending costs one, and an empty bucket
/// means the emote is dropped.
///
/// The arithmetic itself lives in [TokenBucket] — this class is the *map*,
/// one bucket per player, plus the defaults tuned for applause. Phase 13
/// pulled the maths out because a socket that has never joined has no id to
/// key on, and a second copy of the rule is how the two stop agreeing.
///
/// A bucket rather than a flat "one every N milliseconds" cooldown because
/// the two behave differently in exactly the case that matters. A cooldown
/// punishes the person who claps three times when the speaker lands a joke —
/// which is the entire point of the feature. A bucket lets that through and
/// still cuts off the person holding the button down, because the burst is
/// spent and the refill is slow.
///
/// This lives on the **server**, not the client. The client has its own,
/// gentler throttle so the button feels honest, but that one is advice: it
/// is trivially removed by anybody who opens the console. This one is the
/// rule. Emotes are the only message a client can cause to fan out to every
/// one of its neighbours, so an unlimited one is a one-tap way to make the
/// atrium unreadable for everybody standing in it.
class EmoteLimiter {
  /// Creates a limiter.
  ///
  /// [now] is injectable so the rate limit can be unit-tested against a
  /// clock the test drives, instead of by sleeping.
  EmoteLimiter({
    this.burst = defaultBurst,
    this.refill = defaultRefill,
    DateTime Function() now = DateTime.now,
    // A named parameter cannot be private, so this cannot be an
    // initializing formal.
    // ignore: prefer_initializing_formals
  }) : _now = now {
    if (burst < 1) {
      throw ArgumentError.value(burst, 'burst', 'must be at least 1');
    }
    if (refill <= Duration.zero) {
      throw ArgumentError.value(refill, 'refill', 'must be positive');
    }
  }

  /// How many emotes a player may fire back to back.
  static const int defaultBurst = 3;

  /// How long one spent token takes to come back.
  ///
  /// Three in hand and one back every 800ms: a real burst of applause goes
  /// through untouched, a held-down button settles at just over one a second.
  static const Duration defaultRefill = Duration(milliseconds: 800);

  /// The most tokens a player can hold.
  final int burst;

  /// How long one token takes to refill.
  final Duration refill;

  final DateTime Function() _now;
  final Map<String, TokenBucket> _buckets = {};

  /// How many players currently have a bucket.
  int get trackedPlayers => _buckets.length;

  /// Whether [id] may emote right now, spending a token if so.
  ///
  /// Asking is spending: there is no separate `take`, because a caller that
  /// could check without consuming would eventually check twice and send
  /// twice.
  bool allow(String id) {
    // A newcomer starts full: `TokenBucket` does that, so their first emote
    // is free and instant, which is what makes the button feel connected to
    // the tap.
    final bucket = _buckets.putIfAbsent(
      id,
      () => TokenBucket(burst: burst, refill: refill, now: _now),
    );
    return bucket.allow();
  }

  /// Drops [id]'s bucket, e.g. when their socket closes.
  ///
  /// Without this the map would grow for the whole life of the process — one
  /// entry per person who ever attended, which is a slow leak rather than a
  /// fast one, and therefore the kind that survives a load test.
  void forget(String id) => _buckets.remove(id);

  /// Drops every bucket.
  void clear() => _buckets.clear();
}
