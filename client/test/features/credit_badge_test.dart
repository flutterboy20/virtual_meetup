import 'package:client/core/credits.dart';
import 'package:client/features/world/view/credit_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  /// The badge on its own, on a screen with room for a sheet.
  Future<void> pump(WidgetTester tester, {String? link}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: link == null
                ? const CreditBadge()
                : CreditBadge(githubLink: link),
          ),
        ),
      ),
    );
  }

  group('the QR sheet', () {
    testWidgets('encodes the link it was given, not a baked-in one', (
      tester,
    ) async {
      // The whole point of the config key: somebody forks this world for
      // their own event, and the code in the corner has to lead to their
      // repo.
      await pump(tester, link: 'https://example.dev/their-repo');
      await tester.tap(find.byType(CreditBadge));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel,
        equals('QR code for example.dev/their-repo'),
      );
    });

    testWidgets('prints the same link under it, minus the scheme', (
      tester,
    ) async {
      await pump(tester, link: 'https://example.dev/their-repo');
      await tester.tap(find.byType(CreditBadge));
      await tester.pumpAndSettle();

      expect(find.text('example.dev/their-repo'), findsOneWidget);
    });

    testWidgets('makes that line tappable', (tester) async {
      // The person holding the phone showing this sheet cannot scan it with
      // the same phone. Tapping is the only way in for them.
      await pump(tester, link: 'https://example.dev/their-repo');
      await tester.tap(find.byType(CreditBadge));
      await tester.pumpAndSettle();

      final row = find.ancestor(
        of: find.text('example.dev/their-repo'),
        matching: find.byType(InkWell),
      );
      expect(row, findsWidgets);
      expect(tester.widget<InkWell>(row.first).onTap, isNotNull);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    });

    testWidgets('falls back to this project when nobody says otherwise', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byType(CreditBadge));
      await tester.pumpAndSettle();

      expect(
        tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel,
        equals('QR code for ${Credits.linkLabel(Credits.repositoryUrl)}'),
      );
      expect(
        find.text(Credits.linkLabel(Credits.repositoryUrl)),
        findsOneWidget,
      );
    });
  });
}
