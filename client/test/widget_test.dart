import 'package:client/app/app.dart';
import 'package:client/core/credits.dart';
import 'package:client/core/player_identity.dart';
import 'package:client/core/share_link.dart';
import 'package:client/core/sponsor.dart';
import 'package:client/features/setup/view/setup_screen.dart';
import 'package:client/features/welcome/view/welcome_screen.dart';
import 'package:client/features/world/view/world_screen.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/services/server_status_service.dart';
import 'package:client/services/sponsor_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import 'support/fake_identity_store.dart';
import 'support/fake_socket.dart';

/// A status service that answers whatever the test tells it to.
class _FakeStatusService implements ServerStatusService {
  _FakeStatusService([this.answer = const ServerOnline(7)]);

  ServerStatus answer;
  int calls = 0;

  @override
  Future<ServerStatus> fetch() async {
    calls++;
    return answer;
  }
}

void main() {
  const testSponsors = [
    Sponsor(
      id: 'test-booth',
      name: 'Test Booth',
      blurb: 'A booth for a test to walk up to.',
      x: 1130,
      y: 478,
      color: Color(0xFF54C5F8),
    ),
  ];

  const returning = PlayerIdentity(
    sessionId: FakeIdentityStore.testSessionId,
    name: 'Ada',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
  );

  // The game runs a ticker, so `pumpAndSettle` would never settle: pump a
  // couple of frames by hand instead.
  Future<({FakeSocket socket, FakeIdentityStore store})> pumpApp(
    WidgetTester tester, {
    PlayerIdentity? identity,
    ServerStatus status = const ServerOnline(7),
  }) async {
    // The app is given a fake socket and a fake store: a widget test must
    // never open a real socket or touch a platform channel.
    final (:client, :socket) = fakeNetwork();
    addTearDown(client.dispose);
    final store = FakeIdentityStore(identity: identity);

    await tester.pumpWidget(
      VirtualConferenceApp(
        store: store,
        statusService: _FakeStatusService(status),
        network: client,
        // A widget test must not read the asset bundle any more than it may
        // open a socket: the booth list is injected, like everything else.
        sponsors: const StaticSponsorRepository(testSponsors),
      ),
    );
    // One for the bootstrap read, one for the status fetch.
    await tester.pump();
    await tester.pump();
    return (socket: socket, store: store);
  }

  group('the front door', () {
    testWidgets('a new device lands on the welcome screen', (tester) async {
      await pumpApp(tester);

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
    });

    testWidgets('shows the live online count', (tester) async {
      await pumpApp(tester);

      expect(find.text('7 people walking around'), findsOneWidget);
    });

    testWidgets('an unreachable server does not block the door', (
      tester,
    ) async {
      await pumpApp(tester, status: const ServerUnreachable());

      expect(find.textContaining('Explore!!!'), findsOneWidget);
      // The Join button is still there. The count decorates the door, it
      // does not gate it.
      expect(find.text('Join'), findsOneWidget);
    });

    testWidgets('offers the link before anybody has walked in', (tester) async {
      // The front door is where sharing happens: people pass this on while
      // they are still deciding who else should be here.
      final realSheet = shareSheet;
      addTearDown(() => shareSheet = realSheet);
      final shared = <String>[];
      shareSheet = (text) async => shared.add(text);

      await pumpApp(tester);

      expect(find.text('Share this world'), findsOneWidget);

      await tester.tap(find.text('Share this world'));
      await tester.pump();

      expect(shared, hasLength(1));
      expect(shared.single, contains(AppConfig.defaultWorldName));
    });

    testWidgets('Join sends a new player to setup', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Join'));
      await tester.pump();

      expect(find.byType(SetupScreen), findsOneWidget);
    });

    testWidgets('a returning player skips setup entirely', (tester) async {
      await pumpApp(tester, identity: returning);

      expect(find.text('Continue as Ada'), findsOneWidget);

      await tester.tap(find.text('Continue as Ada'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(WorldScreen), findsOneWidget);
      expect(find.byType(SetupScreen), findsNothing);
    });

    testWidgets('a returning player can still change their bean', (
      tester,
    ) async {
      await pumpApp(tester, identity: returning);

      await tester.tap(find.text('Change name or bean'));
      await tester.pump();

      expect(find.byType(SetupScreen), findsOneWidget);
      // Seeded with what they already had, so fixing a typo is an edit.
      expect(find.text('Ada'), findsOneWidget);
    });
  });

  group('setup', () {
    Future<void> openSetup(WidgetTester tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Join'));
      await tester.pump();
    }

    testWidgets('the enter button is inert until the name is valid', (
      tester,
    ) async {
      await openSetup(tester);

      FilledButton enterButton() =>
          tester.widget<FilledButton>(find.byType(FilledButton));

      expect(enterButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'A');
      await tester.pump();
      expect(enterButton().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Ada');
      await tester.pump();
      expect(enterButton().onPressed, isNotNull);
    });

    testWidgets('a blocked name is refused inline, politely', (tester) async {
      await openSetup(tester);

      await tester.enterText(find.byType(TextField), 'f.u.c.k');
      await tester.pump();

      expect(find.text(NameValidation.blocked.message), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('says nothing at all about an empty field', (tester) async {
      await openSetup(tester);

      expect(find.text(NameValidation.tooShort.message), findsNothing);
    });

    testWidgets('entering saves the identity and opens the world', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('Join'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Ada Lovelace');
      await tester.pump();
      // The screen scrolls; in an 800x600 test viewport the button sits
      // below the fold.
      await tester.ensureVisible(find.text('Enter the world'));
      await tester.pump();
      await tester.tap(find.text('Enter the world'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(WorldScreen), findsOneWidget);
    });
  });

  group('the world', () {
    Future<FakeSocket> enterWorld(WidgetTester tester) async {
      final (:socket, :store) = await pumpApp(tester, identity: returning);
      await tester.tap(find.text('Continue as Ada'));
      await tester.pump();
      // The world reads its booth config before it builds the game, so it
      // takes one more turn of the loop to appear than it used to.
      await tester.pump();
      await tester.pump();
      return socket;
    }

    testWidgets('hosts the game', (tester) async {
      await enterWorld(tester);

      expect(find.byType(GameWidget<ConferenceGame>), findsOneWidget);
    });

    testWidgets('joins exactly once, carrying the session id', (tester) async {
      final socket = await enterWorld(tester);
      await tester.pump();

      final joins = socket.sentMessages.whereType<JoinMessage>();
      expect(joins, hasLength(1));
      expect(joins.single.sessionId, equals(returning.sessionId));
      expect(joins.single.name, equals('Ada'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('toggles which side the joystick sits on', (tester) async {
      await enterWorld(tester);

      expect(find.text('Joystick: Right'), findsOneWidget);

      await tester.tap(find.text('Joystick: Right'));
      await tester.pump();

      expect(find.text('Joystick: Left'), findsOneWidget);
    });

    testWidgets('a dropped socket shows reconnecting, not an error', (
      tester,
    ) async {
      final socket = await enterWorld(tester);
      await tester.pump();
      expect(find.text('Connected'), findsOneWidget);

      socket.dropFromServer();
      await tester.pump();
      await tester.pump();

      // The whole point of the phase: still in the world, no modal, no
      // bounce to the lobby, just a calm word in the corner.
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.byType(WorldScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(GameWidget<ConferenceGame>), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rejected join sends the player back to setup', (
      tester,
    ) async {
      final socket = await enterWorld(tester);
      await tester.pump();

      socket.emit(
        const JoinRejectedMessage(
          reason: JoinRejection.invalidName,
          detail: 'Please pick a different name.',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(SetupScreen), findsOneWidget);
      // The server's own words, shown rather than swallowed.
      expect(find.text('Please pick a different name.'), findsOneWidget);
    });

    testWidgets('a banned join is not the setup form', (tester) async {
      // A form somebody can retype forever, that refuses every attempt, is
      // the cruellest version of this screen. There is nothing to fix — but
      // there is somebody to write to, and a door that can be knocked on.
      final socket = await enterWorld(tester);
      await tester.pump();

      socket.emit(
        const JoinRejectedMessage(
          reason: JoinRejection.banned,
          detail: 'A moderator has removed you from this event.',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(SetupScreen), findsNothing);
      expect(
        find.text('A moderator has removed you from this event.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      // The address to appeal to, and the explanation of what the button
      // does — because what it does is ask the server, not let itself in.
      expect(find.text(Credits.supportEmail), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('once the ban is lifted'), findsOneWidget);
      // Nothing has been asked yet, so there is nothing to report.
      expect(find.textContaining('Last checked at'), findsNothing);
    });

    testWidgets('a lifted ban lets them back in without a reload', (
      tester,
    ) async {
      // The whole point. The socket that would have carried the good news
      // was refused at the door, so before this button an unbanned person
      // sat on a dead screen until they thought to reload the tab.
      final socket = await enterWorld(tester);
      await tester.pump();

      socket.emit(
        const JoinRejectedMessage(
          reason: JoinRejection.banned,
          detail: 'A moderator has removed you from this event.',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(WorldScreen), findsNothing);

      // The moderator lifts it, so this join is simply not refused.
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byType(WorldScreen), findsOneWidget);
      expect(
        find.text('A moderator has removed you from this event.'),
        findsNothing,
      );
    });

    testWidgets('a kicked player sets up again from scratch', (tester) async {
      // The name is what a kick is almost always about, so coming back has to
      // go through the screen where the name is chosen — with nothing
      // pre-filled, because the server will refuse the old one anyway.
      final (:socket, :store) = await pumpApp(tester, identity: returning);
      await tester.tap(find.text('Continue as Ada'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      socket.emit(
        const JoinRejectedMessage(
          reason: JoinRejection.kicked,
          detail:
              'A moderator removed you from this event. '
              'You can rejoin in 30s, under a different name.',
        ),
      );
      await tester.pump();
      await tester.pump();

      // Wiped, but not the session id: the cooldown, the name block and any
      // ban are all keyed on it.
      expect(store.clearIdentityCount, equals(1));
      expect(await store.readIdentity(), isNull);
      expect(await store.sessionId(), equals(returning.sessionId));

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SetupScreen), findsOneWidget);
      // Not 'Continue as Ada', and not a form holding the kicked name.
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('Ada'), findsNothing);
    });

    testWidgets('a mis-tapped log out changes nothing', (tester) async {
      final (:socket, :store) = await pumpApp(tester, identity: returning);
      await tester.tap(find.text('Continue as Ada'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Stay'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Still in the world, still Ada, nothing thrown away.
      expect(find.byType(WorldScreen), findsOneWidget);
      expect(store.clearCount, isZero);
      expect(await store.readIdentity(), equals(returning));
    });

    testWidgets('logging out forgets the device and reopens onboarding', (
      tester,
    ) async {
      final (:socket, :store) = await pumpApp(tester, identity: returning);
      await tester.tap(find.text('Continue as Ada'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The whole point: the device no longer knows anybody, session id
      // included, so the next person is a new person to the server.
      expect(store.clearCount, equals(1));
      expect(await store.readIdentity(), isNull);
      expect(await store.sessionId(), isNot(equals(returning.sessionId)));

      // Back at the front door as a first-timer, not a returning player.
      expect(find.byType(WorldScreen), findsNothing);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
      expect(find.text('Continue as Ada'), findsNothing);

      // And Join now goes through setup again, as it does on a fresh phone.
      await tester.tap(find.text('Join'));
      await tester.pump();
      expect(find.byType(SetupScreen), findsOneWidget);
      expect(find.text('Ada'), findsNothing);
    });

    testWidgets('a kicked join stops the client from walking back in', (
      tester,
    ) async {
      // Without this the supervisor treats the moderator's closed socket as
      // a blip and rejoins within half a second, which is the kick undoing
      // itself. Coming back has to be the person's decision.
      final socket = await enterWorld(tester);
      await tester.pump();

      socket.emit(
        const JoinRejectedMessage(
          reason: JoinRejection.kicked,
          detail:
              'A moderator removed you from this event. '
              'You can rejoin in 30s.',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(WorldScreen), findsNothing);
      expect(find.byType(SetupScreen), findsNothing);
      expect(
        find.text(
          'A moderator removed you from this event. You can rejoin in 30s.',
        ),
        findsOneWidget,
      );
      // Unlike a ban, this one is a wait — so there is a way back.
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
