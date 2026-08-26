import 'package:client/core/share_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shareLinkFor', () {
    test('keeps the front door and drops what the tab happened to be on', () {
      expect(
        shareLinkFor(Uri.parse('https://world.example/?map=beach')),
        equals('https://world.example/'),
      );
      expect(
        shareLinkFor(Uri.parse('https://world.example/#og-route')),
        equals('https://world.example/'),
      );
    });

    test('keeps a path, because the app may not be at the root', () {
      expect(
        shareLinkFor(Uri.parse('https://acme.example/world/?map=beach')),
        equals('https://acme.example/world/'),
      );
    });

    test('keeps an explicit port and adds no implicit one', () {
      expect(
        shareLinkFor(Uri.parse('http://localhost:8080/?map=beach')),
        equals('http://localhost:8080/'),
      );
      expect(
        shareLinkFor(Uri.parse('https://world.example')),
        equals('https://world.example/'),
      );
    });
  });

  group('shareApp', () {
    late List<String> shared;
    late Future<void> Function(String text) realSheet;

    setUpAll(() => realSheet = shareSheet);

    setUp(() {
      shared = [];
      shareSheet = (text) async => shared.add(text);
    });

    tearDown(() => shareSheet = realSheet);

    /// A screen with a messenger over it, which is what the fallback needs.
    Future<BuildContext> pumpHost(WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      return captured;
    }

    testWidgets('offers the world by name, with the stripped link', (
      tester,
    ) async {
      final context = await pumpHost(tester);

      await shareApp(
        context,
        worldName: 'FlutterCon India',
        base: Uri.parse('https://world.example/?map=beach'),
      );

      expect(shared, hasLength(1));
      expect(shared.single, contains('FlutterCon India'));
      expect(shared.single, contains('https://world.example/'));
      expect(shared.single, isNot(contains('map=beach')));
    });

    testWidgets('falls back to the clipboard when there is no sheet', (
      tester,
    ) async {
      // A desktop browser with no Web Share API. The link still has to get to
      // the player somehow, and a mail client is not that somehow.
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      shareSheet = (text) async => throw Exception('no share sheet here');

      final context = await pumpHost(tester);
      await shareApp(
        context,
        worldName: 'FlutterCon India',
        base: Uri.parse('https://world.example/'),
      );
      await tester.pump();

      expect(copied, equals(['https://world.example/']));
      expect(find.textContaining('Link copied'), findsOneWidget);
    });
  });
}
