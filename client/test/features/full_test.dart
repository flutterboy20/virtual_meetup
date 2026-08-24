import 'package:client/app/app.dart';
import 'package:client/core/player_identity.dart';
import 'package:client/features/full/view/full_screen.dart';
import 'package:client/features/setup/view/setup_screen.dart';
import 'package:client/features/welcome/view/welcome_screen.dart';
import 'package:client/features/world/view/world_screen.dart';
import 'package:client/services/app_config_repository.dart';
import 'package:client/services/server_status_service.dart';
import 'package:client/services/sponsor_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_identity_store.dart';
import '../support/fake_socket.dart';

class _FakeConfig implements AppConfigRepository {
  @override
  Future<AppConfig> load() async => AppConfig.defaults;
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

  const refusal = JoinRejectedMessage(
    reason: JoinRejection.worldFull,
    detail: 'The event is full right now. Please try again in a moment.',
  );

  /// The app, in the world, over a fake socket.
  Future<FakeSocket> enterWorld(WidgetTester tester) async {
    final (:client, :socket) = fakeNetwork();
    addTearDown(client.dispose);

    await tester.pumpWidget(
      VirtualConferenceApp(
        store: FakeIdentityStore(identity: returning),
        statusService: _FakeStatus(),
        network: client,
        sponsors: const StaticSponsorRepository([]),
        appConfig: _FakeConfig(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Continue as Ada'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return socket;
  }

  group('a worldFull rejection', () {
    testWidgets('lands on the full screen, not on setup', (tester) async {
      // The distinction the whole client half of this phase is about: there
      // is nothing to retype, so a form that refuses every attempt would be
      // the wrong answer.
      final socket = await enterWorld(tester);
      await tester.pump();

      socket.emit(refusal);
      await tester.pump();
      await tester.pump();

      expect(find.byType(FullScreen), findsOneWidget);
      expect(find.byType(SetupScreen), findsNothing);
      expect(find.byType(WorldScreen), findsNothing);
      expect(find.text('The event is full'), findsOneWidget);
    });

    testWidgets("shows the server's own words", (tester) async {
      final socket = await enterWorld(tester);
      await tester.pump();

      socket.emit(refusal);
      await tester.pump();
      await tester.pump();

      expect(find.text(refusal.detail), findsOneWidget);
    });

    testWidgets('offers no countdown — the server never sent a time', (
      tester,
    ) async {
      final socket = await enterWorld(tester);
      await tester.pump();

      socket.emit(refusal);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('to go'), findsNothing);
      expect(find.textContaining('open again at'), findsNothing);
    });

    testWidgets('offers a way back, unlike a ban', (tester) async {
      final socket = await enterWorld(tester);
      await tester.pump();

      socket.emit(refusal);
      await tester.pump();
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Try again'),
      );
      // Enabled immediately: nobody knows when a seat frees, so refusing to
      // let somebody ask would be the lie.
      expect(button.onPressed, isNotNull);
    });

    testWidgets('keeps the identity — there is nothing to change', (
      tester,
    ) async {
      final (:client, :socket) = fakeNetwork();
      addTearDown(client.dispose);
      final store = FakeIdentityStore(identity: returning);

      await tester.pumpWidget(
        VirtualConferenceApp(
          store: store,
          statusService: _FakeStatus(),
          network: client,
          sponsors: const StaticSponsorRepository([]),
          appConfig: _FakeConfig(),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Continue as Ada'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      socket.emit(refusal);
      await tester.pump();
      await tester.pump();

      // Unlike a kick, which wipes the identity because a kick is about the
      // name. Being refused for space is about nobody.
      expect(store.clearIdentityCount, equals(0));
      expect(await store.readIdentity(), isNotNull);
    });
  });

  group('the manual retry', () {
    /// The app in the world, over a client that gets a *fresh* socket per
    /// connection.
    ///
    /// A retry is a second connection, and a single fake socket is one-shot:
    /// its stream is closed when the first world screen is disposed, so a
    /// reconnect would have nothing to attach to and the retry would look
    /// broken when it is not.
    Future<List<FakeSocket>> enterWorldReconnecting(WidgetTester tester) async {
      final (:client, :sockets) = reconnectingNetwork();
      addTearDown(client.dispose);

      await tester.pumpWidget(
        VirtualConferenceApp(
          store: FakeIdentityStore(identity: returning),
          statusService: _FakeStatus(),
          network: client,
          sponsors: const StaticSponsorRepository([]),
          appConfig: _FakeConfig(),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Continue as Ada'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return sockets;
    }

    Future<void> refuse(WidgetTester tester, List<FakeSocket> sockets) async {
      sockets.last.emit(refusal);
      await tester.pump();
      await tester.pump();
    }

    Future<void> tapRetry(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      // The world screen reads its booths and its board flag before it
      // connects, so coming back in takes several turns of the loop — the
      // same ones entering it the first time takes, plus the retry's own
      // await.
      // `runAsync` as well as `pump`: coming back in tears the old socket
      // down first, and a stream subscription's `cancel` completes on the
      // *real* event loop, which the test's fake clock does not advance.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    testWidgets('asks the server by trying the door again', (tester) async {
      final sockets = await enterWorldReconnecting(tester);
      await tester.pump();
      await refuse(tester, sockets);
      final socketsBefore = sockets.length;

      await tapRetry(tester);

      // Straight into the world, not back to the front door: there is one
      // seat and whoever asks first should get it.
      expect(find.byType(WorldScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      // A second connection, carrying a second join. The server is the only
      // thing that decides whether there is room.
      expect(sockets.length, greaterThan(socketsBefore));
      expect(
        sockets.last.sentMessages.whereType<JoinMessage>(),
        isNotEmpty,
      );
    });

    testWidgets('a still-full server puts the screen straight back', (
      tester,
    ) async {
      final sockets = await enterWorldReconnecting(tester);
      await tester.pump();
      await refuse(tester, sockets);

      await tapRetry(tester);
      await refuse(tester, sockets);

      expect(find.byType(FullScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a seat that freed lets the player in and stays in', (
      tester,
    ) async {
      final sockets = await enterWorldReconnecting(tester);
      await tester.pump();
      await refuse(tester, sockets);

      await tapRetry(tester);
      // The server welcomed them this time.
      sockets.last.emit(const WelcomeMessage(yourId: 'p1'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(WorldScreen), findsOneWidget);
      expect(find.byType(FullScreen), findsNothing);
    });
  });

  group('the quiet poll', () {
    /// The screen on its own, counting how often it asked.
    Future<int Function()> pumpScreen(
      WidgetTester tester, {
      Duration recheckEvery = const Duration(seconds: 10),
    }) async {
      var asks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreen(
            recheckEvery: recheckEvery,
            onRetry: () async => asks++,
          ),
        ),
      );
      return () => asks;
    }

    testWidgets('asks on its interval without anybody tapping', (tester) async {
      // A closed-out client has no socket, so the news that a seat freed
      // cannot be pushed to it. Asking on a timer is what closes that gap.
      final asks = await pumpScreen(tester);
      expect(asks(), equals(0));

      await tester.pump(const Duration(seconds: 10));
      expect(asks(), equals(1));

      await tester.pump(const Duration(seconds: 10));
      expect(asks(), equals(2));
    });

    testWidgets('does not ask before its interval is up', (tester) async {
      final asks = await pumpScreen(tester);

      await tester.pump(const Duration(seconds: 9));

      expect(asks(), equals(0));
    });

    testWidgets('a zero interval turns the poll off', (tester) async {
      final asks = await pumpScreen(tester, recheckEvery: Duration.zero);

      await tester.pump(const Duration(minutes: 5));

      expect(asks(), equals(0));
    });

    testWidgets('the manual button still works with the poll off', (
      tester,
    ) async {
      final asks = await pumpScreen(tester, recheckEvery: Duration.zero);

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();

      expect(asks(), equals(1));
    });

    testWidgets('the timer stops when the screen goes', (tester) async {
      // A timer left running on a tab somebody forgot about is expensive on a
      // phone and invisible in a test that does not look for it.
      final asks = await pumpScreen(tester);
      await tester.pump(const Duration(seconds: 10));
      expect(asks(), equals(1));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(minutes: 5));

      expect(asks(), equals(1));
    });
  });
}
