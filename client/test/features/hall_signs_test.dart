import 'package:client/core/theme.dart';
import 'package:client/features/welcome/view/map_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

void main() {
  Future<List<MapId>> pump(
    WidgetTester tester, {
    MapId selected = MapId.conference,
    int? Function(MapId)? countOf,
    double width = 350,
  }) async {
    final picked = <MapId>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: MapPicker(
                selected: selected,
                onSelected: picked.add,
                countOf: countOf ?? (map) => map == MapId.conference ? 18 : 0,
              ),
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  Color? fillOf(WidgetTester tester, String label) => tester
      .widget<Material>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Material))
            .first,
      )
      .color;

  testWidgets('one sign per place, each with its head-count', (tester) async {
    await pump(tester);

    expect(find.text('Conference'), findsOneWidget);
    expect(find.text('Beach'), findsOneWidget);
    expect(find.text('18 people here'), findsOneWidget);
    expect(find.text('Empty — be the first'), findsOneWidget);
  });

  testWidgets('the chosen sign is lit and the other is not', (tester) async {
    await pump(tester, selected: MapId.beach);

    expect(fillOf(tester, 'Beach'), equals(LanyardColors.ink));
    expect(fillOf(tester, 'Conference'), equals(Colors.transparent));
  });

  testWidgets('tapping a sign picks its place', (tester) async {
    final picked = await pump(tester);

    await tester.tap(find.text('Beach'));

    expect(picked, equals([MapId.beach]));
  });

  testWidgets('an unknown count is a dash, never a zero', (tester) async {
    await pump(tester, countOf: (_) => null);

    expect(find.text('—'), findsNWidgets(2));
    expect(find.textContaining('0'), findsNothing);
  });

  testWidgets('reads as one button per place to a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    expect(
      tester.getSemantics(find.text('Conference')),
      isSemantics(
        label: 'Conference, 18 here',
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('fits a 288px column without overflowing', (tester) async {
    await pump(tester, width: 288, countOf: (_) => 0);

    expect(tester.takeException(), isNull);
  });
}
