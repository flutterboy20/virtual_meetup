import 'package:client/features/welcome/view/badge_card.dart';
import 'package:client/features/welcome/view/bean_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

Widget _host(
  Widget child, {
  bool disableAnimations = false,
  double width = 390,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 844),
        disableAnimations: disableAnimations,
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(width: width - 40, child: child),
        ),
      ),
    ),
  );
}

BadgeCard _badge({
  String name = 'Ruhaan',
  Animation<double>? swing,
}) => BadgeCard(
  eyebrow: 'FlutterCon India 2026',
  worldName: 'Virtual Meetup',
  name: name,
  color: 0xFF54C5F8,
  cosmetic: PlayerCosmetic.headphones,
  swing: swing,
);

double _angleOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(find.byKey(BadgeCard.swingKey));
  // A z-rotation by θ puts sin θ in row 1, column 0 of the matrix.
  return transform.transform.entry(1, 0);
}

void main() {
  group('what the badge says', () {
    testWidgets('prints the config header, the eyebrow in capitals', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_badge()));

      expect(find.text('FLUTTERCON INDIA 2026'), findsOneWidget);
      expect(find.text('Virtual Meetup'), findsOneWidget);
    });

    testWidgets('prints the name, with no role stripe under it', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_badge()));

      expect(find.text('HELLO, MY NAME IS'), findsOneWidget);
      expect(find.text('Ruhaan'), findsOneWidget);
      // Removed to give the hats room: every badge said the same word.
      expect(find.text('ATTENDEE'), findsNothing);
    });

    testWidgets('says so when there is no name yet', (tester) async {
      // Whitespace counts as no name: a badge reading "   " is a blank badge.
      await tester.pumpWidget(_host(_badge(name: '   ')));

      expect(find.text(BadgeCard.namePlaceholder), findsOneWidget);
    });

    testWidgets('draws the bean the world will draw', (tester) async {
      await tester.pumpWidget(_host(_badge()));

      final preview = tester.widget<BeanPreview>(find.byType(BeanPreview));
      expect(preview.color, equals(0xFF54C5F8));
      expect(preview.cosmetic, equals(PlayerCosmetic.headphones));
    });

    testWidgets('a long name on a narrow phone truncates, not overflows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_badge(name: 'Bartholomew Featherstonehaugh'), width: 320),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Bartholomew Featherstonehaugh'), findsOneWidget);
    });
  });

  group('the swing', () {
    test('starts upright', () {
      expect(badgeSwingAngle(0), equals(0));
    });

    test('never leans past its limit', () {
      for (var i = 0; i <= 100; i++) {
        expect(
          badgeSwingAngle(i / 100).abs(),
          lessThanOrEqualTo(badgeSwingMax + 1e-12),
        );
      }
    });

    test('ends the loop where it began, so the repeat has no jump', () {
      expect(badgeSwingAngle(1), closeTo(badgeSwingAngle(0), 1e-12));
    });

    testWidgets('leans with the loop it is handed', (tester) async {
      // A quarter of the way into the first swing: the furthest lean.
      await tester.pumpWidget(
        _host(_badge(swing: const AlwaysStoppedAnimation(0.125))),
      );

      expect(_angleOf(tester), closeTo(badgeSwingMax, 1e-3));
    });

    testWidgets('holds still under reduce motion, whatever it is handed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _badge(swing: const AlwaysStoppedAnimation(0.125)),
          disableAnimations: true,
        ),
      );

      expect(_angleOf(tester), equals(0));
    });

    testWidgets('holds still with no loop at all', (tester) async {
      await tester.pumpWidget(_host(_badge()));

      expect(_angleOf(tester), equals(0));
    });
  });
}
