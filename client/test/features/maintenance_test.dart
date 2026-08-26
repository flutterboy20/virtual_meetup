import 'dart:async';

import 'package:client/app/app.dart';
import 'package:client/core/player_identity.dart';
import 'package:client/features/maintenance/view/maintenance_screen.dart';
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

/// A config source the test hands answers to, one reload at a time.
class _FakeConfig implements AppConfigRepository {
  _FakeConfig(this.answer);

  AppConfig answer;
  int loads = 0;

  @override
  Future<AppConfig> load() async {
    loads++;
    return answer;
  }
}

class _FakeStatus implements ServerStatusService {
  @override
  Future<ServerStatus> fetch() async => const ServerOnline(7);
}

void main() {
  const returning = PlayerIdentity(
    sessionId: 'aaaa1111bbbb2222cccc3333dddd4444',
    name: 'Ada',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.none,
  );

  /// The app, over a fake socket, a fake store and [config].
  Future<({FakeSocket socket, _FakeConfig config})> pumpApp(
    WidgetTester tester, {
    required AppConfig config,
    PlayerIdentity? identity,
  }) async {
    final (:client, :socket) = fakeNetwork();
    addTearDown(client.dispose);
    final repository = _FakeConfig(config);

    await tester.pumpWidget(
      VirtualConferenceApp(
        store: FakeIdentityStore(identity: identity),
        statusService: _FakeStatus(),
        network: client,
        sponsors: const StaticSponsorRepository([]),
        appConfig: repository,
      ),
    );
    await tester.pump();
    await tester.pump();
    return (socket: socket, config: repository);
  }

  AppConfig closedFor(Duration left) =>
      AppConfig(maintenanceUntil: DateTime.now().toUtc().add(left));

  group('the maintenance screen', () {
    testWidgets('a closed event replaces the front door', (tester) async {
      // Nobody has done anything and nobody has tried to join. The config
      // alone is enough, which is what puts *everybody* here at once.
      await pumpApp(tester, config: closedFor(const Duration(hours: 2)));

      expect(find.byType(MaintenanceScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.text('The event is paused'), findsOneWidget);
    });

    testWidgets('names the moment the doors reopen', (tester) async {
      final until = DateTime.now().add(const Duration(days: 1));
      await pumpApp(
        tester,
        config: AppConfig(maintenanceUntil: until.toUtc()),
      );

      expect(find.textContaining('The doors open again at'), findsOneWidget);
      expect(find.textContaining('to go'), findsOneWidget);
    });

    testWidgets('the way back in is shut while the window is open', (
      tester,
    ) async {
      // The client never decides that maintenance is over.
      await pumpApp(tester, config: closedFor(const Duration(hours: 2)));

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Try again'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a window that has passed offers the way back', (tester) async {
      await pumpApp(
        tester,
        config: AppConfig(
          maintenanceUntil: DateTime.now().toUtc().subtract(
            const Duration(minutes: 1),
          ),
        ),
      );

      // A window in the past is not maintenance at all, so the app never
      // stops at this screen for it.
      expect(find.byType(MaintenanceScreen), findsNothing);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });

  group('the moderator notice', () {
    testWidgets('replaces the built-in sentence rather than joining it', (
      tester,
    ) async {
      final until = DateTime.now().add(const Duration(hours: 2));
      await pumpApp(
        tester,
        config: AppConfig(
          maintenanceUntil: until.toUtc(),
          maintenanceMessage: 'The keynote overran.',
        ),
      );

      expect(find.textContaining('The keynote overran.'), findsOneWidget);
      expect(find.textContaining('Somebody is working on it'), findsNothing);
      // The reopening time is still appended: it is a fact the screen knows
      // and the moderator should not have to retype it.
      expect(find.textContaining('The doors open again at'), findsOneWidget);
    });

    testWidgets('hides the clock and the time when it is told to', (
      tester,
    ) async {
      await pumpApp(
        tester,
        config: AppConfig(
          maintenanceUntil: DateTime.now()
              .add(const Duration(hours: 2))
              .toUtc(),
          maintenanceMessage: 'Back as soon as we can.',
          maintenanceShowTimer: false,
        ),
      );

      expect(find.textContaining('to go'), findsNothing);
      expect(find.textContaining('The doors open again at'), findsNothing);
      expect(find.text('Back as soon as we can.'), findsOneWidget);
    });

    testWidgets('keeps the door shut even with the clock hidden', (
      tester,
    ) async {
      // The gate is the server's. Hiding the countdown hides the promise,
      // not the lock — a button that let somebody knock every second would
      // be a worse countdown, not none.
      await pumpApp(
        tester,
        config: AppConfig(
          maintenanceUntil: DateTime.now()
              .add(const Duration(hours: 2))
              .toUtc(),
          maintenanceShowTimer: false,
        ),
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Try again'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('the countdown', () {
    /// The screen on its own, over a clock the test moves by hand.
    ///
    /// `tester.pump` advances Flutter's clock, which fires the timer, but it
    /// does not move `DateTime.now` — so a countdown driven by the real clock
    /// could only ever be asserted to render.
    Future<void> pumpCountdown(
      WidgetTester tester, {
      required DateTime until,
      required DateTime Function() now,
      Future<void> Function()? onRetry,
      Duration recheckEvery = Duration.zero,
    }) => tester.pumpWidget(
      MaterialApp(
        home: MaintenanceScreen(
          until: until,
          now: now,
          recheckEvery: recheckEvery,
          onRetry: onRetry ?? () async {},
        ),
      ),
    );

    testWidgets('counts down as time passes', (tester) async {
      var now = DateTime(2026, 8, 22, 18);
      await pumpCountdown(
        tester,
        until: DateTime(2026, 8, 22, 18, 1, 30),
        now: () => now,
      );

      expect(find.text('about 1m 30s to go'), findsOneWidget);

      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('about 59s to go'), findsOneWidget);
    });

    testWidgets('unlocks the way back when the window runs out', (
      tester,
    ) async {
      var now = DateTime(2026, 8, 22, 18);
      final until = DateTime(2026, 8, 22, 18, 0, 2);
      await pumpCountdown(tester, until: until, now: () => now);

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Try again'),
            )
            .onPressed,
        isNull,
      );

      now = until.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Try again'),
            )
            .onPressed,
        isNotNull,
      );
      // Reaching zero enables a button. It does not walk anybody back in.
      expect(find.byType(MaintenanceScreen), findsOneWidget);
      expect(find.textContaining('to go'), findsNothing);
    });

    testWidgets('stops ticking once there is nothing to count', (tester) async {
      // A timer left running rebuilds a fixed sentence forever, on a phone
      // somebody has left this tab open on.
      var now = DateTime(2026, 8, 22, 18);
      await pumpCountdown(
        tester,
        until: DateTime(2026, 8, 22, 18, 0, 2),
        now: () => now,
      );

      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));

      // No pending timers is the assertion: the test would fail on teardown
      // if one were still alive.
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('asks the server once, however hard the button is tapped', (
      tester,
    ) async {
      var calls = 0;
      final answer = Completer<void>();
      await pumpCountdown(
        tester,
        until: DateTime(2026, 8, 22, 18),
        now: () => DateTime(2026, 8, 22, 19),
        onRetry: () {
          calls++;
          return answer.future;
        },
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();
      expect(find.text('Checking…'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Checking…'));
      await tester.pump();

      expect(calls, equals(1));
      answer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('asks the server on its own while the window is open', (
      tester,
    ) async {
      // A moderator who reopens early cannot push that to a client the
      // closure already disconnected, so the screen asks rather than sitting
      // out a window that has stopped existing.
      var calls = 0;
      final now = DateTime(2026, 8, 22, 18);
      await pumpCountdown(
        tester,
        until: DateTime(2026, 8, 22, 20),
        now: () => now,
        recheckEvery: const Duration(seconds: 15),
        onRetry: () async {
          calls++;
        },
      );

      expect(calls, isZero);
      await tester.pump(const Duration(seconds: 15));
      expect(calls, equals(1));
      await tester.pump(const Duration(seconds: 15));
      expect(calls, equals(2));
    });

    testWidgets('stops asking once there is nothing left to wait for', (
      tester,
    ) async {
      // The ask rides the countdown's timer, so it dies with it: a screen
      // whose window has run out is a screen with a button on it, not a
      // client polling an open event forever.
      var calls = 0;
      var now = DateTime(2026, 8, 22, 18);
      await pumpCountdown(
        tester,
        until: DateTime(2026, 8, 22, 18, 0, 2),
        now: () => now,
        recheckEvery: const Duration(seconds: 15),
        onRetry: () async {
          calls++;
        },
      );

      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 30));

      expect(calls, isZero);
    });
  });

  group('being closed out mid-event', () {
    testWidgets('a config pushed down the socket empties the world', (
      tester,
    ) async {
      // The moderator's side of the same moment: everybody who was already
      // inside has to leave, not just the people who try to join next.
      final it = await pumpApp(
        tester,
        config: AppConfig.defaults,
        identity: returning,
      );
      await tester.tap(find.text('Continue as Ada'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byType(WorldScreen), findsOneWidget);

      it.socket.emit(
        ConfigMessage(config: closedFor(const Duration(hours: 1))),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(WorldScreen), findsNothing);
      expect(find.byType(MaintenanceScreen), findsOneWidget);
    });

    testWidgets('a refused join lands here rather than on a dead end', (
      tester,
    ) async {
      // The client may be holding a config from before the closure, so the
      // refusal is what tells it — and the reload is what lets it say when.
      final it = await pumpApp(
        tester,
        config: AppConfig.defaults,
        identity: returning,
      );
      await tester.tap(find.text('Continue as Ada'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      it.config.answer = closedFor(const Duration(hours: 3));
      it.socket.emit(
        const JoinRejectedMessage(
          reason: JoinRejection.maintenance,
          detail: 'The event is paused for maintenance.',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MaintenanceScreen), findsOneWidget);
      // Re-read over HTTP, which is how the screen learns the moment the
      // closed socket never got to tell it.
      expect(find.textContaining('The doors open again at'), findsOneWidget);
    });

    testWidgets('a reopen before the window ends takes the screen down', (
      tester,
    ) async {
      // The bug this exists for: the doors were opened early, and the client
      // holding the old timestamp went on counting down to a moment that had
      // stopped meaning anything.
      final it = await pumpApp(
        tester,
        config: closedFor(const Duration(hours: 2)),
      );
      expect(find.byType(MaintenanceScreen), findsOneWidget);

      it.config.answer = AppConfig.defaults;
      // The recheck interval, without anybody tapping anything.
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      await tester.pump();

      expect(find.byType(MaintenanceScreen), findsNothing);
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('trying again asks the server and leaves when it is open', (
      tester,
    ) async {
      // Refused at the door by a window that had already ended by the time
      // the config was re-read: the stage is what is holding them here, and
      // the retry is the only thing that clears it.
      final it = await pumpApp(
        tester,
        config: AppConfig.defaults,
        identity: returning,
      );
      await tester.tap(find.text('Continue as Ada'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      it.socket.emit(
        const JoinRejectedMessage(
          reason: JoinRejection.maintenance,
          detail: 'The event is paused for maintenance.',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MaintenanceScreen), findsOneWidget);

      final before = it.config.loads;
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      // Pumped rather than settled: the front door this lands on runs a
      // parade of beans that never stops, so `pumpAndSettle` never would
      // either.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(it.config.loads, greaterThan(before));
      // The front door, not straight back into the world: a room full of
      // clients all reconnecting at once is the herd the window avoided.
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });
  });
}
