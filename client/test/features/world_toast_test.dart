import 'package:client/features/world/view/world_toast.dart';
import 'package:client/game/world_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Pumps the toast view over [hud], and hands back a pump helper.
  Future<void> pumpToast(WidgetTester tester, WorldHud hud) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(child: WorldToastView(toasts: hud.toast)),
          ),
        ),
      );

  /// The opacity the toast is currently drawn at.
  double opacityOf(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('says nothing until the world does', (tester) async {
    final hud = WorldHud();
    addTearDown(hud.dispose);

    await pumpToast(tester, hud);

    expect(opacityOf(tester), isZero);
  });

  testWidgets('fades a message in and holds it', (tester) async {
    final hud = WorldHud();
    addTearDown(hud.dispose);
    await pumpToast(tester, hud);

    hud.say('Board unlocked');
    await tester.pump();

    expect(find.text('Board unlocked'), findsOneWidget);
    expect(opacityOf(tester), equals(1));

    // Still up four seconds later.
    await tester.pump(const Duration(seconds: 4));
    expect(opacityOf(tester), equals(1));
  });

  testWidgets('fades out after five seconds', (tester) async {
    final hud = WorldHud();
    addTearDown(hud.dispose);
    await pumpToast(tester, hud);

    hud.say('Board stowed');
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    expect(opacityOf(tester), isZero);
    // Settle the fade so no timer is left running past the test.
    await tester.pumpAndSettle();
  });

  testWidgets('a second message replaces the first rather than queueing', (
    tester,
  ) async {
    final hud = WorldHud();
    addTearDown(hud.dispose);
    await pumpToast(tester, hud);

    hud.say('First');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    hud.say('Second');
    await tester.pump();

    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    // And the second gets its own full five seconds, not the two the first
    // had left — a replacement that inherited a stale timer would flash.
    await tester.pump(const Duration(seconds: 4));
    expect(opacityOf(tester), equals(1));
    await tester.pump(const Duration(seconds: 2));
    expect(opacityOf(tester), isZero);
    await tester.pumpAndSettle();
  });

  testWidgets('never eats a tap meant for the world under it', (tester) async {
    final hud = WorldHud();
    addTearDown(hud.dispose);
    await pumpToast(tester, hud);
    hud.say('Anything');
    await tester.pump();

    // The outermost one, which is the toast's own — the chip's Material adds
    // others further down the tree.
    expect(
      tester
          .widgetList<IgnorePointer>(
            find.descendant(
              of: find.byType(WorldToastView),
              matching: find.byType(IgnorePointer),
            ),
          )
          .first
          .ignoring,
      isTrue,
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('two identical messages are two toasts', (tester) async {
    final hud = WorldHud();
    addTearDown(hud.dispose);

    hud.say('Same');
    final first = hud.toast.value;
    hud.say('Same');

    // The id is what makes the notifier fire twice; without it the second
    // tap on the hint bean would look like it did nothing.
    expect(hud.toast.value, isNot(equals(first)));
  });
}
