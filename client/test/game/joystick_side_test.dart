import 'package:client/game/joystick_side.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JoystickSide', () {
    test('toggles between the two sides', () {
      expect(JoystickSide.right.opposite, JoystickSide.left);
      expect(JoystickSide.left.opposite, JoystickSide.right);
    });

    test('labels itself for the settings toggle', () {
      expect(JoystickSide.right.label, 'Right');
      expect(JoystickSide.left.label, 'Left');
    });

    test('pins to exactly one horizontal edge', () {
      final right = JoystickSide.right.margin(inset: 32, bottomInset: 44);
      expect(right.right, 32);
      expect(right.left, 0);
      expect(right.bottom, 44);
      expect(right.top, 0);

      final left = JoystickSide.left.margin(inset: 32, bottomInset: 44);
      expect(left.left, 32);
      expect(left.right, 0);
      expect(left.bottom, 44);
      expect(left.top, 0);
    });
  });
}
