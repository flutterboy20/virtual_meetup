import 'package:client/app/app.dart';
import 'package:client/core/credits.dart';
import 'package:client/core/player_identity.dart';
import 'package:client/features/world/view/credit_badge.dart';
import 'package:client/features/world/view/emote_bar.dart';
import 'package:client/features/world/view/minimap.dart';
import 'package:client/game/world_hud.dart';
import 'package:client/services/app_config_repository.dart';
import 'package:client/services/server_status_service.dart';
import 'package:client/services/sponsor_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_identity_store.dart';
import '../support/fake_socket.dart';

class _FakeConfig implements AppConfigRepository {
  const _FakeConfig([this.config = AppConfig.defaults]);

  final AppConfig config;

  @override
  Future<AppConfig> load() async => config;
}

class _FakeStatus implements ServerStatusService {
  @override
  Future<ServerStatus> fetch() async => const ServerOnline(7);
}

void main() {
  const returning = PlayerIdentity(
    sessionId: FakeIdentityStore.testSessionId,
    name: 'Ada',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
  );

  /// A phone in portrait, which is the screen the HUD has to survive.
  const phone = Size(360, 740);

  /// A laptop, where there was never a problem to solve.
  const desk = Size(1280, 800);

  /// The app, in the world, on a screen of [size].
  Future<void> enterWorld(
    WidgetTester tester,
    Size size, {
    AppConfig config = AppConfig.defaults,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final (:client, :socket) = fakeNetwork();
    addTearDown(client.dispose);

    await tester.pumpWidget(
      VirtualConferenceApp(
        store: FakeIdentityStore(identity: returning),
        statusService: _FakeStatus(),
        network: client,
        sponsors: const StaticSponsorRepository([]),
        appConfig: _FakeConfig(config),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Continue as Ada'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  /// Opens the phone's HUD menu and lets the drawer finish sliding in.
  ///
  /// `pumpAndSettle` is not an option anywhere near this screen: the game
  /// runs a ticker, so nothing ever settles. The drawer's slide is 246ms.
  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('the HUD on a phone', () {
    testWidgets('keeps only the controls a thumb uses while walking', (
      tester,
    ) async {
      // The rule this file exists to hold, restated for the drawer: what is
      // on screen is what you reach for mid-step — the minimap, the emotes,
      // the joystick and the door to the other world. Everything else is one
      // tap away, and the tap is always visible.
      await enterWorld(tester, phone);

      expect(find.byType(Minimap), findsOneWidget);
      expect(find.byType(EmoteBar), findsOneWidget);
      expect(find.text('Go to Beach'), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
      // Share is the other deliberate duplicate: the moment somebody passes
      // this on is mid-walk, when the room they are in is worth showing.
      expect(find.text('Share'), findsOneWidget);

      // ...and the standing HUD is not carrying the rest of it.
      expect(find.textContaining('Joystick:'), findsNothing);
      expect(find.text('Ada'), findsNothing);
      expect(find.text('Log out'), findsNothing);
      expect(find.byType(CreditBadge), findsNothing);
    });

    testWidgets('hides nothing: the drawer holds all of it', (tester) async {
      // The other half of the same rule. Moving a control into a drawer is
      // allowed; losing the way out of the screen is not.
      await enterWorld(tester, phone);
      await openMenu(tester);

      expect(find.textContaining('Joystick:'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.byType(CreditBadge), findsOneWidget);
      expect(find.text(Credits.builtBy), findsOneWidget);
      // The controls that are deliberately in both places.
      expect(find.text('Go to Beach'), findsNWidgets(2));
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Share this world'), findsOneWidget);
    });

    testWidgets('a drawer control closes the drawer and acts', (tester) async {
      await enterWorld(tester, phone);
      await openMenu(tester);

      await tester.tap(find.textContaining('Joystick:'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Joystick:'), findsNothing);
      await openMenu(tester);
      expect(find.text('Joystick: Left'), findsOneWidget);
    });

    testWidgets('draws a narrower minimap', (tester) async {
      await enterWorld(tester, phone);

      final minimap = tester.widget<Minimap>(find.byType(Minimap));
      expect(minimap.width, equals(Minimap.phoneWidth));
    });

    testWidgets('says nothing while the socket is healthy', (tester) async {
      // The menu button carries the socket, because the chip that used to is
      // now behind it — but only once there is something to say.
      await enterWorld(tester, phone);

      expect(find.text('Connected'), findsNothing);
      expect(find.byIcon(Icons.cloud_done), findsNothing);
      expect(find.byIcon(Icons.menu), findsOneWidget);
    });
  });

  group('the HUD on a desk', () {
    testWidgets('shows every chip', (tester) async {
      await enterWorld(tester, desk);

      expect(find.textContaining('Joystick:'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('draws the full-size minimap and the whole credit', (
      tester,
    ) async {
      await enterWorld(tester, desk);

      expect(
        tester.widget<Minimap>(find.byType(Minimap)).width,
        equals(Minimap.deskWidth),
      );
      expect(
        tester.widget<CreditBadge>(find.byType(CreditBadge)).compact,
        isFalse,
      );
    });

    testWidgets('hands the badge the repository link from the config', (
      tester,
    ) async {
      // The QR is a poster, and the config is where whoever runs the event
      // changes what it points at — without a rebuild.
      await enterWorld(
        tester,
        desk,
        config: const AppConfig(githubLink: 'https://example.dev/their-repo'),
      );

      expect(
        tester.widget<CreditBadge>(find.byType(CreditBadge)).githubLink,
        equals('https://example.dev/their-repo'),
      );
    });
  });

  group('the minimap in the hall', () {
    /// The chip on its own, driven by a frame this test owns.
    ///
    /// Tested here rather than through the whole app because the thing under
    /// test is "which room is the dot in", and walking a real bean into the
    /// auditorium through a `GameWidget` would test the joystick.
    Future<void> pumpAt(WidgetTester tester, Offset you, MapId map) async {
      final frames = ValueNotifier(
        MinimapFrame(you: you, others: const []),
      );
      addTearDown(frames.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: HallAwareMinimap(
            frames: frames,
            spec: MapSpec.of(map),
            width: Minimap.deskWidth,
          ),
        ),
      );
    }

    testWidgets('is drawn everywhere else in the conference', (tester) async {
      // The atrium, where everybody spawns.
      await pumpAt(tester, const Offset(800, 600), MapId.conference);

      expect(find.byType(Minimap), findsOneWidget);
    });

    testWidgets('steps aside inside the hall', (tester) async {
      // In the seats, under the screen people are there to read.
      await pumpAt(tester, const Offset(800, 250), MapId.conference);

      expect(find.byType(Minimap), findsNothing);
    });

    testWidgets('gives the corner back on the way out', (tester) async {
      await pumpAt(tester, const Offset(800, 250), MapId.conference);
      expect(find.byType(Minimap), findsNothing);

      await pumpAt(tester, const Offset(800, 600), MapId.conference);
      expect(find.byType(Minimap), findsOneWidget);
    });

    testWidgets('never hides on a map with no hall', (tester) async {
      // The beach has no such zone, so the same coordinates are just sand.
      await pumpAt(tester, const Offset(800, 250), MapId.beach);

      expect(find.byType(Minimap), findsOneWidget);
    });
  });
}
