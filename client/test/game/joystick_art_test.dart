import 'package:client/game/joystick_art.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [fade] for [seconds] at 60 Hz with the thumb on or off.
void _run(JoystickFade fade, double seconds, {required bool active}) {
  const step = 1 / 60;
  for (var t = 0.0; t < seconds; t += step) {
    fade.update(step, active: active);
  }
}

void main() {
  group('JoystickFade', () {
    test('starts fully visible', () {
      expect(JoystickFade().opacity, equals(1));
    });

    test('holds full opacity until the idle delay is up', () {
      final fade = JoystickFade();

      _run(fade, 1.9, active: false);

      expect(fade.opacity, equals(1));
      expect(fade.idleFor, greaterThan(1.5));
    });

    test('eases to its floor once the stick has been left alone', () {
      final fade = JoystickFade();

      _run(fade, 8, active: false);

      expect(fade.opacity, closeTo(fade.idleOpacity, 0.01));
    });

    test('never fades away entirely', () {
      // A pinned control that disappears is a control a first-time player
      // thinks the app has lost. Faint is the point; gone is a bug.
      final fade = JoystickFade();

      _run(fade, 60, active: false);

      expect(fade.opacity, greaterThanOrEqualTo(fade.idleOpacity));
      expect(fade.idleOpacity, greaterThan(0));
    });

    test('a thumb landing restores it instantly, not over a ramp', () {
      // The fade out is politeness; a fade *in* would be lag on an input.
      final fade = JoystickFade();
      _run(fade, 8, active: false);
      expect(fade.opacity, lessThan(0.5));

      fade.update(1 / 60, active: true);

      expect(fade.opacity, equals(1));
      expect(fade.idleFor, isZero);
    });

    test('the idle timer restarts from the last touch, not from zero', () {
      final fade = JoystickFade();

      _run(fade, 1.5, active: false);
      fade.update(1 / 60, active: true);
      _run(fade, 1.5, active: false);

      // 3 s of wall clock, but only 1.5 s since the thumb came off.
      expect(fade.opacity, equals(1));
    });
  });
}
