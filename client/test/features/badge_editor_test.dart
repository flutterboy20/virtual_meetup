import 'package:client/core/player_identity.dart';
import 'package:client/features/setup/view_model/setup_view_model.dart';
import 'package:client/features/welcome/view/badge_editor.dart';
import 'package:client/features/welcome/view/bean_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_identity_store.dart';

void main() {
  const sessionId = FakeIdentityStore.testSessionId;

  SetupViewModel model({PlayerIdentity? identity}) {
    final model = SetupViewModel(
      store: FakeIdentityStore(sessionId: sessionId),
      sessionId: sessionId,
      identity: identity,
    );
    addTearDown(model.dispose);
    return model;
  }

  Future<void> pump(
    WidgetTester tester,
    SetupViewModel model, {
    VoidCallback? onSubmitted,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              child: BadgeEditor(
                model: model,
                eyebrow: 'FlutterCon India 2026',
                worldName: 'Virtual Meetup',
                onSubmitted: onSubmitted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('typing on the badge goes into the view model', (tester) async {
    final m = model();
    await pump(tester, m);

    await tester.enterText(find.byKey(BadgeEditor.nameFieldKey), 'Ada');

    expect(m.name.value, equals('Ada'));
  });

  testWidgets('a returning player finds their badge filled in', (
    tester,
  ) async {
    final m = model(
      identity: const PlayerIdentity(
        sessionId: sessionId,
        name: 'Ada',
        color: 0xFFF2B33D,
        cosmetic: PlayerCosmetic.cap,
      ),
    );
    await pump(tester, m);

    expect(find.text('Ada'), findsOneWidget);
    final preview = tester.widget<BeanPreview>(find.byType(BeanPreview));
    expect(preview.color, equals(0xFFF2B33D));
    expect(preview.cosmetic, equals(PlayerCosmetic.cap));
  });

  testWidgets('the validation message shows on the badge', (tester) async {
    final m = model();
    await pump(tester, m);

    await tester.enterText(find.byKey(BadgeEditor.nameFieldKey), 'A');
    await tester.pump();

    // The message is the view model's, word for word: the badge adds no rule.
    expect(m.hint.value, isNotEmpty);
    expect(find.text(m.hint.value), findsOneWidget);
  });

  testWidgets('an empty field nags nobody', (tester) async {
    final m = model();
    await pump(tester, m);

    expect(m.hint.value, isEmpty);
  });

  testWidgets('a swatch picks the colour and the bean follows', (
    tester,
  ) async {
    final m = model();
    await pump(tester, m);

    await tester.tap(find.bySemanticsLabel('Colour 3'));
    await tester.pump();

    expect(m.color.value, equals(beanColors[2]));
    final preview = tester.widget<BeanPreview>(find.byType(BeanPreview));
    expect(preview.color, equals(beanColors[2]));
  });

  testWidgets('every hat has a chip with a human label', (tester) async {
    final m = model();
    await pump(tester, m);

    expect(
      find.byType(ChoiceChip),
      findsNWidgets(PlayerCosmetic.values.length),
    );
    for (final cosmetic in PlayerCosmetic.values) {
      expect(cosmeticLabels[cosmetic], isNotNull, reason: cosmetic.name);
      expect(find.text(cosmetic.wireName), findsNothing);
    }
  });

  testWidgets('every hat is on the badge at once, in two rows', (
    tester,
  ) async {
    // No sideways scrolling: a hat you have to scroll to find is a hat
    // nobody picks.
    final m = model();
    await pump(tester, m);

    final badge = tester.getRect(find.byType(BadgeEditor));
    final chips = find.byType(ChoiceChip);
    final rows = <double>{};
    for (var i = 0; i < PlayerCosmetic.values.length; i++) {
      final chip = tester.getRect(chips.at(i));
      expect(badge.contains(chip.topLeft), isTrue);
      expect(badge.contains(chip.bottomRight - const Offset(1, 1)), isTrue);
      rows.add(chip.top);
    }
    expect(
      find.ancestor(of: chips.first, matching: find.byType(Scrollable)),
      findsNothing,
    );
    expect(rows, hasLength(2));
  });

  testWidgets('a hat chip picks the hat and the bean follows', (
    tester,
  ) async {
    final m = model();
    await pump(tester, m);

    await tester.ensureVisible(find.text('Laser Visor'));
    await tester.tap(find.text('Laser Visor'));
    await tester.pump();

    expect(m.cosmetic.value, equals(PlayerCosmetic.laserVisor));
    final preview = tester.widget<BeanPreview>(find.byType(BeanPreview));
    expect(preview.cosmetic, equals(PlayerCosmetic.laserVisor));
  });

  testWidgets('picking a colour keeps what was typed', (tester) async {
    final m = model();
    await pump(tester, m);

    await tester.enterText(find.byKey(BadgeEditor.nameFieldKey), 'Grace');
    await tester.tap(find.bySemanticsLabel('Colour 5'));
    await tester.pump();

    expect(find.text('Grace'), findsOneWidget);
    expect(m.name.value, equals('Grace'));
  });

  testWidgets('done on a valid name submits; on an invalid one it does not', (
    tester,
  ) async {
    final m = model();
    var submitted = 0;
    await pump(tester, m, onSubmitted: () => submitted++);

    await tester.enterText(find.byKey(BadgeEditor.nameFieldKey), 'A');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, equals(0));

    await tester.enterText(find.byKey(BadgeEditor.nameFieldKey), 'Ada');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submitted, equals(1));
  });

  testWidgets('fits a 320px phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final m = model();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: BadgeEditor(
              model: m,
              eyebrow: 'FlutterCon India 2026',
              worldName: 'Virtual Meetup',
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('stays short enough to leave room for the way in', (
    tester,
  ) async {
    // The badge shares an 844px phone with the hall signs and "Enter".
    // Past this height, the way in drops under the fold on a common phone.
    final m = model();
    await pump(tester, m);

    expect(
      tester.getSize(find.byType(BadgeEditor)).height,
      lessThanOrEqualTo(500),
    );
  });
}
