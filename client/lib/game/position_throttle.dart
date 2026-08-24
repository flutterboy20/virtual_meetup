import 'package:flame/components.dart';

// Pure send-rate maths for the local bean's position. Kept free of sockets
// and components so it can be unit-tested without a game loop or a server.

/// Decides how often the local bean's position goes on the wire.
///
/// Two rules, and both matter at conference scale:
///
/// - **Never per frame.** 60Hz × 300 attendees is 18,000 messages a second
///   for the server to fan out. Ten times a second is plenty for something a
///   human reads as smooth movement, and the client interpolates the gaps
///   from Phase 3.
/// - **Never while standing still.** Somebody parked at a booth for ten
///   minutes should cost nothing at all.
class PositionThrottle {
  /// Creates a throttle.
  PositionThrottle({
    this.interval = defaultInterval,
    this.minDistance = defaultMinDistance,
  });

  /// The default gap between sends, in seconds — ten times a second.
  static const double defaultInterval = 0.1;

  /// The default movement needed before a send, in world units.
  ///
  /// Small enough to be invisible (a bean is 26 units wide) and large enough
  /// to swallow the floating-point drift of a bean easing to a halt.
  static const double defaultMinDistance = 0.5;

  /// Seconds between sends.
  final double interval;

  /// How far the bean must have moved since the last send for another one.
  final double minDistance;

  double _elapsed = 0;
  Vector2? _lastSent;

  /// The last position that was actually sent, if any.
  Vector2? get lastSent => _lastSent?.clone();

  /// Advances the clock by [dt] and returns the position to send, or `null`.
  ///
  /// Call this every frame with the bean's current position; send whatever it
  /// hands back.
  Vector2? sample(double dt, Vector2 position) {
    _elapsed += dt;
    if (_elapsed < interval) return null;
    // Subtracting rather than zeroing keeps the average rate honest when
    // frames run long; the modulo stops a stalled tab from firing a burst of
    // catch-up sends when it wakes.
    _elapsed %= interval;

    final last = _lastSent;
    if (last != null && last.distanceTo(position) < minDistance) return null;

    _lastSent = position.clone();
    return position.clone();
  }

  /// Forgets what was last sent, so the next sample always sends.
  ///
  /// Used after a (re)connect: the new server knows nothing about us.
  void reset() {
    _elapsed = 0;
    _lastSent = null;
  }
}
