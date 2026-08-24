// Pure timing maths for smoothing a remote player's motion. No components,
// no sockets, no Flame — so it can be tested by hand-cranking a clock.

/// How far behind the newest data a remote bean is drawn, in seconds.
///
/// The server ticks at ~15Hz, so positions arrive every ~66ms. Drawing the
/// newest one immediately would mean 15 jumps a second — steppy. Instead the
/// client renders the world as it was 100ms ago, which puts the render head
/// *between* two samples it already has, and moves it smoothly from one to
/// the other at 60fps.
///
/// The cost is 100ms of extra apparent lag on other people's beans, which
/// nobody notices in a social space, and which is why your own bean is never
/// interpolated: your input has to feel instant.
///
/// A little over one tick interval on purpose. Exactly one tick would leave
/// no slack, and a single snapshot arriving late — a wifi hiccup, a stalled
/// tab — would strand the render head past the newest sample and stutter.
const double interpolationDelay = 0.1;

/// One position, at one moment.
typedef PositionSample = ({double time, double x, double y});

/// A short history of where one remote player has been.
///
/// Holds the last handful of reported positions and answers "where should
/// this bean be drawn at time t", interpolating between the two samples that
/// bracket t.
///
/// It never extrapolates. Guessing where somebody is going and being wrong
/// makes a bean visibly snap backwards when the truth arrives; holding still
/// for one late snapshot is the quieter failure, and this is a social space,
/// not a shooter where the guess would be worth it.
class InterpolationBuffer {
  /// Creates an empty buffer.
  InterpolationBuffer({this.capacity = defaultCapacity});

  /// How many samples are kept at most.
  ///
  /// Interpolation only ever needs the two around the render head; the rest
  /// is slack for out-of-order or bunched arrivals. Beyond that it is memory
  /// per remote player per tick, and there can be a few hundred of those.
  static const int defaultCapacity = 8;

  /// The most samples this buffer will hold.
  final int capacity;

  final List<PositionSample> _samples = [];

  /// Whether nothing has been reported yet.
  bool get isEmpty => _samples.isEmpty;

  /// How many samples are currently held.
  int get length => _samples.length;

  /// The newest sample, or `null` when nothing has arrived.
  PositionSample? get newest => _samples.isEmpty ? null : _samples.last;

  /// Records that the player was at ([x], [y]) at [time].
  ///
  /// A sample at or before the newest one is dropped rather than inserted:
  /// snapshots arrive in order on a WebSocket, so an out-of-order one means
  /// something is wrong upstream, and rewriting history would jerk the bean.
  /// A sample at exactly the newest time replaces it — that is a second
  /// snapshot inside one frame, and only the later position matters.
  void add(double time, double x, double y) {
    if (_samples.isNotEmpty) {
      final last = _samples.last;
      if (time < last.time) return;
      if (time == last.time) {
        _samples[_samples.length - 1] = (time: time, x: x, y: y);
        return;
      }
    }
    _samples.add((time: time, x: x, y: y));
    if (_samples.length > capacity) _samples.removeAt(0);
  }

  /// Where the bean should be drawn at [renderTime].
  ///
  /// Clamps at both ends rather than extrapolating:
  ///
  /// - Before the first sample (the moment a player appears) it holds at the
  ///   first known position, so a new bean does not slide in from nowhere.
  /// - After the last sample (a late or missing snapshot) it holds at the
  ///   last known position. The bean stands still for a moment and then
  ///   carries on — no rubber-banding, no snapping backwards.
  ///
  /// Throws a [StateError] if nothing has been reported; a buffer is always
  /// seeded with the position a player appeared at.
  ({double x, double y}) positionAt(double renderTime) {
    if (_samples.isEmpty) {
      throw StateError('positionAt on a buffer with no samples');
    }

    final first = _samples.first;
    if (renderTime <= first.time) return (x: first.x, y: first.y);

    final last = _samples.last;
    if (renderTime >= last.time) return (x: last.x, y: last.y);

    for (var i = _samples.length - 2; i >= 0; i--) {
      final from = _samples[i];
      if (from.time > renderTime) continue;
      final to = _samples[i + 1];
      final span = to.time - from.time;
      final t = span <= 0 ? 1.0 : (renderTime - from.time) / span;
      // Everything older than `from` can never be needed again: the render
      // head only moves forwards.
      _samples.removeRange(0, i);
      return (x: _lerp(from.x, to.x, t), y: _lerp(from.y, to.y, t));
    }

    return (x: first.x, y: first.y);
  }

  /// Whether the render head has run past the newest sample.
  ///
  /// True means the bean is being held still because the next snapshot has
  /// not arrived — worth surfacing in a debug overlay, and the signal a
  /// future reconnect flow would watch.
  bool isStarvedAt(double renderTime) =>
      _samples.isNotEmpty && renderTime > _samples.last.time;

  static double _lerp(double from, double to, double t) =>
      from + (to - from) * t;
}
