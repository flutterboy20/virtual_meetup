import 'package:client/game/position_throttle.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const frame = 1 / 60;

  /// Runs [frames] frames, moving [step] world units each one, and returns
  /// every position the throttle asked to send.
  List<Vector2> run(
    PositionThrottle throttle, {
    required int frames,
    Vector2? step,
    Vector2? start,
  }) {
    final position = start?.clone() ?? Vector2.zero();
    final sent = <Vector2>[];
    for (var i = 0; i < frames; i++) {
      if (step != null) position.add(step);
      final toSend = throttle.sample(frame, position);
      if (toSend != null) sent.add(toSend);
    }
    return sent;
  }

  group('rate', () {
    test('sends nothing before the first interval is up', () {
      final throttle = PositionThrottle();

      expect(run(throttle, frames: 5, step: Vector2(5, 0)), isEmpty);
    });

    test('sends about ten times a second, not sixty', () {
      final throttle = PositionThrottle();

      // One second of walking at 60fps. Nine or ten, not sixty: a frame is
      // not an exact fraction of the interval, so the count lands either
      // side of ten depending on rounding.
      final sent = run(throttle, frames: 60, step: Vector2(2, 0));

      expect(sent.length, inInclusiveRange(9, 11));
    });

    test('honours a custom interval', () {
      final throttle = PositionThrottle(interval: 0.5);

      final sent = run(throttle, frames: 120, step: Vector2(5, 0));

      expect(sent.length, inInclusiveRange(3, 4));
    });

    test('does not fire a burst of catch-up sends after a long frame', () {
      // A backgrounded tab hands back one enormous dt. Sending once is right;
      // sending fifty stale positions is not.
      final throttle = PositionThrottle();

      final sent = <Vector2>[];
      final first = throttle.sample(5, Vector2(10, 10));
      if (first != null) sent.add(first);
      final second = throttle.sample(frame, Vector2(20, 20));
      if (second != null) sent.add(second);

      // Two at most — a naive "catch up" loop would have sent fifty.
      expect(sent.length, lessThan(3));
      expect(sent.first, Vector2(10, 10));
    });
  });

  group('movement threshold', () {
    test('says nothing while the bean stands still', () {
      final throttle = PositionThrottle();
      run(throttle, frames: 12, step: Vector2(5, 0));

      // Two more seconds of not moving.
      expect(run(throttle, frames: 120, start: throttle.lastSent), isEmpty);
    });

    test('sends again as soon as the bean really moves', () {
      final throttle = PositionThrottle();
      run(throttle, frames: 12, step: Vector2(5, 0));

      final sent = run(throttle, frames: 12, step: Vector2(5, 0));

      expect(sent, isNotEmpty);
    });

    test('ignores drift below the threshold', () {
      final throttle = PositionThrottle();
      run(throttle, frames: 12, step: Vector2(5, 0));

      // 0.01 units a frame is a bean easing to a halt, not a bean walking.
      final sent = run(
        throttle,
        frames: 12,
        start: throttle.lastSent,
        step: Vector2(0.01, 0),
      );

      expect(sent, isEmpty);
    });

    test('sends the first position it is given', () {
      final throttle = PositionThrottle();

      final sent = run(throttle, frames: 12, start: Vector2(100, 200));

      expect(sent.first, Vector2(100, 200));
    });
  });

  group('bookkeeping', () {
    test('reports what it last sent', () {
      final throttle = PositionThrottle();

      run(throttle, frames: 12, start: Vector2(7, 8));

      expect(throttle.lastSent, Vector2(7, 8));
    });

    test('hands back a copy, not the live position', () {
      final throttle = PositionThrottle();
      final position = Vector2(1, 2);

      final sent = run(throttle, frames: 12, start: position);
      position.setValues(999, 999);

      expect(sent.first, Vector2(1, 2));
      expect(throttle.lastSent, Vector2(1, 2));
    });

    test('reset makes the next sample send again', () {
      final throttle = PositionThrottle();
      run(throttle, frames: 12, start: Vector2(1, 2));

      throttle.reset();
      final sent = run(throttle, frames: 12, start: Vector2(1, 2));

      expect(sent.first, Vector2(1, 2));
      expect(throttle.lastSent, Vector2(1, 2));
    });
  });
}
