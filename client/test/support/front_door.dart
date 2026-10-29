import 'package:client/features/welcome/view/welcome_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Taps the front door's way in and lets the save and the stage change land.
///
/// Scrolls first: the badge, the hall signs and the button are a phone's
/// height, and the default 800x600 test window is shorter than that.
Future<void> tapEnter(WidgetTester tester) async {
  final button = find.text(WelcomeScreen.enterLabel);
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  // One for the identity being written, one for the stage it unlocks.
  await tester.pump();
  await tester.pump();
}
