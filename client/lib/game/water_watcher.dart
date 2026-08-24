import 'package:client/game/world_layout.dart';
import 'package:protocol/protocol.dart';

/// One bean's position, as the watcher sees it.
typedef SwimSample = ({String id, double x, double y});

/// A point in the world, for a splash or a wake.
typedef SplashAt = ({double x, double y});

/// Who just went in, and who is still swimming.
///
/// Returned by [WaterWatcher.update]. The lists are the watcher's own and are
/// cleared on every call — read them before the next update, do not keep them.
/// A fresh pair of lists sixty times a second would be sixty allocations a
/// second to say "nobody did anything", which is the usual answer.
typedef WaterEvents = ({List<SplashAt> dives, List<SplashAt> wakes});

/// Watches beans crossing the water's edge, and says who just dived.
///
/// Pure bookkeeping over positions — no `Canvas`, no `Component`, no network.
/// It is fed the local bean and every remote bean in exactly the same way,
/// because as far as this is concerned they are the same thing: a position
/// this client already has. That is what makes the whole feature free on the
/// wire.
///
/// **The hysteresis is the point of the class.** A single boundary would let a
/// bean parked on the pool lip fire a splash on every frame its interpolated
/// position wobbled across the edge — the same failure the sponsor panel had
/// at its approach radius, and far more obnoxious, because it is 14 particles
/// a frame instead of a panel flickering. So going in is judged against the
/// pool shrunk by [margin] and coming out against the pool grown by it, and a
/// bean has to genuinely commit before either fires.
class WaterWatcher {
  /// Creates a watcher with nobody in the water.
  ///
  /// [regions] is every swimmable rectangle on the map — a list since Phase
  /// 10, because the conference has one pool and the beach has a sea. It
  /// defaults to the conference's pool so a test that only cares about
  /// hysteresis does not have to name a map.
  WaterWatcher({
    List<WorldRect>? regions,
    this.dryPlatforms = const [],
    this.margin = defaultMargin,
    this.wakeInterval = 0.35,
    this.remoteWakeInterval,
    this.localId,
  }) : regions = regions ?? const [WorldLayout.pool];

  /// Every swimmable rectangle on this map.
  final List<WorldRect> regions;

  /// The decks inside [regions] that a bean stands on — the beach's raft.
  ///
  /// Holes in the water as far as this class is concerned: climbing onto one
  /// counts as getting out, so the wakes stop and stepping off the far side
  /// splashes again. Same hysteresis as the shoreline, so a bean shuffling on
  /// the raft's edge does not strobe.
  final List<WorldRect> dryPlatforms;

  /// How far past the pool's edge a bean must go before it counts, in world
  /// units.
  static const double defaultMargin = 7;

  /// The dead band around the pool edge, in world units.
  final double margin;

  /// How often the **local** bean drops a wake ring, in seconds.
  ///
  /// Roughly three a second. Bounded without needing its own cap: only beans
  /// this client can *see* are ever passed in, and that is already capped by
  /// the server's interest culling.
  ///
  /// Mutable since Phase 10: the water's level-of-detail writes it every
  /// frame. A `final` here would mean rebuilding the watcher to change a
  /// rate, and rebuilding the watcher would forget who is in the water and
  /// splash all of them again.
  double wakeInterval;

  /// How often a **remote** bean drops one, or `null` for the same rate.
  ///
  /// Separate so the LOD can drop remote wakes a tier early while the local
  /// bean is submerged — see `WaterLod.remoteWakeInterval`. The local bean's
  /// own wake is never cheapened, because that one is the feedback for what
  /// the player is doing right now.
  double? remoteWakeInterval;

  /// Which sample is the local bean, if any.
  String? localId;

  final Map<String, _Swimmer> _swimmers = {};
  final List<SplashAt> _dives = [];
  final List<SplashAt> _wakes = [];

  /// How many of the beans last seen are currently in the water.
  int get swimmerCount {
    var count = 0;
    for (final swimmer in _swimmers.values) {
      if (swimmer.inWater) count++;
    }
    return count;
  }

  /// Whether [id] was in the water as of the last update.
  bool isSwimming(String id) => _swimmers[id]?.inWater ?? false;

  /// Advances by [dt] and reports what the beans in [samples] just did.
  WaterEvents update(double dt, Iterable<SwimSample> samples) {
    _dives.clear();
    _wakes.clear();

    final seen = <String>{};
    for (final sample in samples) {
      seen.add(sample.id);
      final swimmer = _swimmers.putIfAbsent(
        sample.id,
        // A bean that appears already standing in the water — a resumed
        // session, or somebody walking into interest range mid-swim — starts
        // swimming rather than diving. They did not just jump in, and a
        // splash for somebody who has been floating there for a minute is a
        // lie every other client can see through.
        () => _Swimmer(inWater: _isWater(sample.x, sample.y)),
      );

      final wasIn = swimmer.inWater;
      final nowIn = wasIn
          ? !_isOutside(sample.x, sample.y)
          : _isInside(sample.x, sample.y);

      if (nowIn && !wasIn) {
        _dives.add((x: sample.x, y: sample.y));
        swimmer.sinceWake = 0;
      }
      swimmer.inWater = nowIn;

      if (nowIn) {
        final interval = sample.id == localId
            ? wakeInterval
            : (remoteWakeInterval ?? wakeInterval);
        swimmer.sinceWake += dt;
        // An infinite interval is how the flat tier says "no wakes at all"
        // without a second flag that could disagree with this one.
        if (interval.isFinite && swimmer.sinceWake >= interval) {
          swimmer.sinceWake -= interval;
          _wakes.add((x: sample.x, y: sample.y));
        }
      }
    }

    // Anybody who stopped being visible stops being tracked, or the map grows
    // for the length of the event. Coming back into range is a fresh entry —
    // which is right: this client genuinely does not know what they did while
    // they were culled.
    if (_swimmers.length != seen.length) {
      _swimmers.removeWhere((id, _) => !seen.contains(id));
    }

    return (dives: _dives, wakes: _wakes);
  }

  /// Forgets everybody, e.g. when the connection drops.
  void clear() => _swimmers.clear();

  bool _isWater(double x, double y) {
    if (_onPlatform(x, y, 0)) return false;
    for (final region in regions) {
      if (region.contains(x, y)) return true;
    }
    return false;
  }

  bool _isInside(double x, double y) {
    // Getting in has to clear the raft by the same dead band it clears the
    // shore by, or wading off the deck fires a dive a frame early.
    if (_onPlatform(x, y, margin)) return false;
    for (final region in regions) {
      final inner = region.deflate(
        left: margin,
        top: margin,
        right: margin,
        bottom: margin,
      );
      if (inner.contains(x, y)) return true;
    }
    return false;
  }

  bool _isOutside(double x, double y) {
    if (_onPlatform(x, y, -margin)) return true;
    for (final region in regions) {
      if (region.inflate(margin).contains(x, y)) return false;
    }
    return true;
  }

  /// Whether ([x], [y]) is on a dry platform grown by [margin] units.
  ///
  /// A negative [margin] shrinks it, which is what "committed to the deck"
  /// means on the way out.
  bool _onPlatform(double x, double y, double margin) {
    for (final platform in dryPlatforms) {
      if (platform.inflate(margin).contains(x, y)) return true;
    }
    return false;
  }
}

class _Swimmer {
  _Swimmer({required this.inWater});

  bool inWater;
  double sinceWake = 0;
}
