import 'package:client/core/sponsor.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/world/view/emote_bar.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:client/features/world/view/sponsor_panel.dart';
import 'package:client/features/world/view/world_toast.dart';
import 'package:client/features/world/view/zone_card.dart';
import 'package:client/game/world_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

Offset _middleOf(WorldZone zone) => Offset(
  (zone.rect.left + zone.rect.right) / 2,
  (zone.rect.top + zone.rect.bottom) / 2,
);

MinimapFrame _at(WorldZone zone) =>
    MinimapFrame(you: _middleOf(zone), others: const []);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('the HUD card', () {
    testWidgets('is a toybox card: white, ink outline, hard shadow', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const HudChip(child: Text('Hi'))));

      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(of: find.text('Hi'), matching: find.byType(DecoratedBox))
            .last,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, equals(ToyboxColors.card));
      expect(decoration.boxShadow!.single.blurRadius, equals(0));
    });

    testWidgets('inks its text and icons for a white card', (tester) async {
      await tester.pumpWidget(
        _host(
          const HudChip(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Icons.share), Text('Share')],
            ),
          ),
        ),
      );

      final text = tester.widget<RichText>(
        find.descendant(
          of: find.text('Share'),
          matching: find.byType(RichText),
        ),
      );
      expect(text.text.style?.color, equals(ToyboxColors.ink));
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.share))).color,
        equals(ToyboxColors.ink),
      );
    });
  });

  group('the zone card', () {
    late ValueNotifier<MinimapFrame> frames;

    setUp(() => frames = ValueNotifier(_at(WorldZone.atrium)));
    tearDown(() => frames.dispose());

    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      _host(ZoneCard(frames: frames, spec: MapSpec.conference)),
    );

    testWidgets('names the room you are standing in', (tester) async {
      await pump(tester);

      expect(find.text(WorldZone.atrium.label), findsOneWidget);
    });

    testWidgets('changes when you walk into the next room', (tester) async {
      await pump(tester);

      frames.value = _at(WorldZone.foodCourt);
      await tester.pump();

      expect(find.text(WorldZone.foodCourt.label), findsOneWidget);
      expect(find.text(WorldZone.atrium.label), findsNothing);
    });

    testWidgets('rebuilds nothing while you walk across one room', (
      tester,
    ) async {
      await pump(tester);
      final before = tester.element(find.text(WorldZone.atrium.label));

      // A step inside the atrium: same room, so the same element, untouched.
      frames.value = MinimapFrame(
        you: _middleOf(WorldZone.atrium) + const Offset(12, 8),
        others: const [],
      );
      await tester.pump();

      expect(tester.element(find.text(WorldZone.atrium.label)), same(before));
    });

    testWidgets('steps aside in the hall, like the minimap', (tester) async {
      await pump(tester);

      frames.value = _at(WorldZone.hall);
      await tester.pump();

      expect(find.byType(HudChip), findsNothing);
    });

    testWidgets('names beach rooms on the beach', (tester) async {
      frames.value = _at(WorldZone.beachSand);
      await tester.pumpWidget(
        _host(ZoneCard(frames: frames, spec: MapSpec.beach)),
      );

      expect(find.text(WorldZone.beachSand.label), findsOneWidget);
    });

    testWidgets('a screen reader hears one sentence', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(
        find.bySemanticsLabel('You are in the ${WorldZone.atrium.label}'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('the dock', () {
    testWidgets('holds its buttons in one card', (tester) async {
      await tester.pumpWidget(
        _host(
          EmoteBar(
            onEmote: (_) {},
            leading: [
              DockButton(
                icon: Icons.menu,
                semanticLabel: 'Menu',
                onTap: () {},
              ),
            ],
            trailing: [
              DockButton(
                icon: Icons.ios_share,
                label: 'Share',
                semanticLabel: 'Share this world',
                onTap: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.byType(DockButton), findsNWidgets(3));
      final card = find.ancestor(
        of: find.byIcon(Icons.menu),
        matching: find.byType(DecoratedBox),
      );
      expect(
        find.descendant(of: card.last, matching: find.text('Share')),
        findsOneWidget,
      );
    });

    testWidgets('every reaction still sends, and the row folds away', (
      tester,
    ) async {
      final sent = <EmoteKind>[];
      await tester.pumpWidget(_host(EmoteBar(onEmote: sent.add)));

      for (final emote in EmoteKind.values) {
        await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text(emote.glyph));
        await tester.pumpAndSettle();

        expect(find.text(emote.glyph), findsNothing);
      }

      expect(sent, equals(EmoteKind.values));
    });

    testWidgets('every dock button is at least a thumb wide', (tester) async {
      await tester.pumpWidget(
        _host(
          DockButton(icon: Icons.menu, semanticLabel: 'Menu', onTap: () {}),
        ),
      );

      final size = tester.getSize(find.byType(DockButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('what the world says', () {
    testWidgets('a toast is an ink pill with cream text', (tester) async {
      final toasts = ValueNotifier<WorldToast?>(null);
      addTearDown(toasts.dispose);
      await tester.pumpWidget(_host(WorldToastView(toasts: toasts)));

      toasts.value = WorldToast('Ada waved');
      await tester.pump();

      final pill = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text('Ada waved'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((pill.decoration as BoxDecoration).color, ToyboxColors.ink);
      final text = tester.widget<Text>(find.text('Ada waved'));
      expect(text.style?.color, ToyboxColors.cream);
    });

    testWidgets('a booth is a toybox card, brand colour as a swatch only', (
      tester,
    ) async {
      const booth = Sponsor(
        id: 'b',
        name: 'Booth',
        blurb: 'A booth.',
        x: 0,
        y: 0,
        color: Color(0xFF13A57A),
      );
      await tester.pumpWidget(_host(const SponsorPanel(sponsor: booth)));
      await tester.pumpAndSettle();

      final card = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text('Booth'),
              matching: find.byType(DecoratedBox),
            )
            .last,
      );
      final decoration = card.decoration as BoxDecoration;
      expect(decoration.color, ToyboxColors.card);
      expect(decoration.boxShadow!.single.blurRadius, 0);
    });
  });
}
