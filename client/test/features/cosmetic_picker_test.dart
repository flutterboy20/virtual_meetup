import 'package:client/features/setup/view/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_identity_store.dart';

void main() {
  testWidgets('the picker offers every cosmetic, with a real label', (
    tester,
  ) async {
    // The picker and the live preview both read `PlayerCosmetic.values`, so a
    // hat added to the protocol shows up here for free — which is exactly the
    // case that would ship a chip labelled `propellerBeanie` if the label map
    // were forgotten.
    await tester.pumpWidget(
      MaterialApp(
        home: SetupScreen(store: FakeIdentityStore(), sessionId: 's1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(ChoiceChip),
      findsNWidgets(PlayerCosmetic.values.length),
    );

    for (final cosmetic in PlayerCosmetic.values) {
      expect(
        find.text(cosmetic.wireName),
        findsNothing,
        reason:
            '${cosmetic.name} has no human label, so its chip fell back '
            'to its wire name',
      );
    }

    expect(find.text('Spiky Hair'), findsOneWidget);
    expect(find.text('Laser Visor'), findsOneWidget);
    expect(find.text('Propeller Beanie'), findsOneWidget);
  });
}
