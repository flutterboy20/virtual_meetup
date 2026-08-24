import 'dart:math' as math;

/// What a live splash particle is.
enum SplashKind {
  /// A thrown droplet from a dive.
  droplet,

  /// An expanding surface ring behind a swimming bean.
  wake,
}

/// One live particle. Mutable and reused — see [SplashField].
class SplashParticle {
  /// Creates a spent particle, ready to be claimed by a burst.
  SplashParticle();

  /// Centre x, in world units.
  double x = 0;

  /// Centre y, in world units.
  double y = 0;

  /// Velocity along x, in world units per second.
  double vx = 0;

  /// Velocity along y, in world units per second.
  double vy = 0;

  /// Seconds of life remaining.
  double life = 0;

  /// Seconds this particle was born with.
  double maxLife = 1;

  /// Radius at birth, in world units.
  double radius = 0;

  /// Which of the two things this is.
  SplashKind kind = SplashKind.droplet;

  /// Whether this particle is still being drawn.
  bool get isAlive => life > 0;

  /// How far through its life it is, from 0 at birth to 1 at death.
  double get age => maxLife <= 0 ? 1 : 1 - (life / maxLife).clamp(0, 1);
}

/// Every splash and wake in the world, in one bounded pool.
///
/// Pure maths: no `Canvas`, no `Component`. Same shape as `BeanAnimation`, and
/// for the same reason — the feel of a splash is worth tuning, and tuning it
/// through a game loop is guesswork.
///
/// **The cap is the whole design.** Twenty beans diving into the pool at once
/// is not a hypothetical, it is what a crowd at a conference does the moment
/// somebody discovers the pool is swimmable. An unbounded emitter turns that
/// into an outage on the phone of everybody standing nearby. So this is a ring
/// buffer of exactly [capacity] pre-allocated particles: a burst that would
/// overflow overwrites the **oldest** live particle instead of growing the
/// list. The worst case is a slightly shorter-lived splash, which nobody can
/// see, rather than a frame time that grows with the crowd, which everybody
/// can.
///
/// Nothing here allocates after construction, either. Sixty frames a second
/// of particle objects is a garbage collector pause in the middle of the one
/// moment the effect is meant to be enjoyed.
class SplashField {
  /// Creates an empty field.
  ///
  /// [seed] is fixed by default so a test gets the same burst every run; the
  /// game does not care what the seed is, only that droplets scatter.
  SplashField({this.capacity = defaultCapacity, int seed = 1337})
    : _random = math.Random(seed),
      _pool = List.generate(capacity, (_) => SplashParticle(), growable: false);

  /// The hard ceiling on live particles.
  ///
  /// 120 is roughly nine simultaneous dives' worth. Past that the extra
  /// droplets are invisible anyway — they land inside somebody else's splash.
  static const int defaultCapacity = 120;

  /// How many droplets one dive throws, at the low end.
  static const int minDroplets = 10;

  /// How many droplets one dive throws, at the high end.
  static const int maxDroplets = 14;

  /// How long a droplet lives, in seconds.
  static const double dropletLife = 0.5;

  /// How long a wake ring lives, in seconds.
  static const double wakeLife = 0.55;

  /// The most particles that can be alive at once.
  final int capacity;

  final List<SplashParticle> _pool;
  final math.Random _random;
  int _next = 0;

  /// Every particle currently being drawn.
  Iterable<SplashParticle> get live => _pool.where((p) => p.isAlive);

  /// How many particles are currently alive.
  int get liveCount {
    var count = 0;
    for (final particle in _pool) {
      if (particle.isAlive) count++;
    }
    return count;
  }

  /// Throws a burst of droplets from ([x], [y]).
  ///
  /// Called on the frame a bean crosses into the water, never per frame while
  /// it is in there — see `WaterWatcher`.
  void splash(double x, double y) {
    final count = minDroplets + _random.nextInt(maxDroplets - minDroplets + 1);
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = 42 + _random.nextDouble() * 74;
      _claim()
        ..x = x
        ..y = y
        ..vx = math.cos(angle) * speed
        // Flattened on y: a top-down splash reads as a ring spreading out
        // across the surface, not as a sphere of drops.
        ..vy = math.sin(angle) * speed * 0.55
        ..life = dropletLife
        ..maxLife = dropletLife
        ..radius = 2.4 + _random.nextDouble() * 2.6
        ..kind = SplashKind.droplet;
    }
  }

  /// Drops one expanding surface ring at ([x], [y]).
  void wake(double x, double y) {
    _claim()
      ..x = x
      ..y = y
      ..vx = 0
      ..vy = 0
      ..life = wakeLife
      ..maxLife = wakeLife
      ..radius = 7
      ..kind = SplashKind.wake;
  }

  /// Advances every live particle by [dt] seconds.
  void update(double dt) {
    if (dt <= 0) return;
    for (final particle in _pool) {
      if (!particle.isAlive) continue;
      particle.life -= dt;
      if (particle.kind == SplashKind.droplet) {
        particle
          ..x += particle.vx * dt
          ..y += particle.vy * dt
          // Drag, not gravity. There is no z axis in this world, so a droplet
          // does not fall — it slows down and sinks back into the surface.
          ..vx *= 1 - math.min(1, 4.2 * dt)
          ..vy *= 1 - math.min(1, 4.2 * dt);
      }
    }
  }

  /// Kills everything, e.g. when the connection drops.
  void clear() {
    for (final particle in _pool) {
      particle.life = 0;
    }
  }

  /// Returns the next slot, overwriting the oldest live particle if full.
  ///
  /// The ring index alone gives "oldest first" for free: slots are handed out
  /// in order, so the one about to be reused is always the one claimed
  /// longest ago.
  SplashParticle _claim() {
    final particle = _pool[_next];
    _next = (_next + 1) % capacity;
    return particle;
  }
}
