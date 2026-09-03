import 'package:client/app/app.dart';
import 'package:client/core/player_identity.dart';
import 'package:client/features/setup/view/setup_screen.dart';
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
    reason: JoinRejection.displaced,
    detail:
        'This event is now open in another tab or window on this device. '
        'Only one can be connected at a time.',
  );

  /// The app in the world, over a client that gets a fresh socket per
  /// connection — a rejoin is a second connection, and one fake socket is
  /// one-shot.
  Future<List<FakeSocket>> enterWorld(
    WidgetTester tester, {
    FakeIdentityStore? store,
  }) async {
    final (:client, :sockets) = reconnectingNetwork();
    addTearDown(client.dispose);

    await tester.pumpWidget(
      VirtualConferenceApp(
        store: store ?? FakeIdentityStore(identity: returning),
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

  Future<void> displace(WidgetTester tester, List<FakeSocket> sockets) async {
    sockets.last.emit(refusal);
    await tester.pump();
    await tester.pump();
  }

  group('a displaced rejection', () {
    testWidgets('leaves the world and says who took the seat', (tester) async {
      final sockets = await enterWorld(tester);
      await tester.pump();

      await displace(tester, sockets);

      expect(find.byType(WorldScreen), findsNothing);
      // Not setup: there is nothing to retype, and the person is welcome.
      expect(find.byType(SetupScreen), findsNothing);
      expect(find.text(refusal.detail), findsOneWidget);
    });

    testWidgets('keeps the identity — this is not a sanction', (tester) async {
      final store = FakeIdentityStore(identity: returning);

      final sockets = await enterWorld(tester, store: store);
      await tester.pump();
      await displace(tester, sockets);

      expect(store.clearIdentityCount, equals(0));
      expect(await store.readIdentity(), isNotNull);
    });

    testWidgets('never reconnects on its own', (tester) async {
      // The whole point of the fix. Two tabs that both retried on a timer
      // would take turns evicting each other for as long as both stayed
      // open — which is the "Reconnecting… connected" flicker this reason
      // exists to end.
      final sockets = await enterWorld(tester);
      await tester.pump();
      await displace(tester, sockets);
      final socketsBefore = sockets.length;

      await tester.pump(const Duration(minutes: 5));

      expect(sockets.length, equals(socketsBefore));
    });

    testWidgets('takes the seat back when the person asks', (tester) async {
      final sockets = await enterWorld(tester);
      await tester.pump();
      await displace(tester, sockets);
      final socketsBefore = sockets.length;

      await tester.tap(find.widgetWithText(FilledButton, 'Continue here'));
      // Coming back in tears the old socket down first, and a subscription's
      // `cancel` completes on the real event loop rather than the fake clock.
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }

      expect(find.byType(WorldScreen), findsOneWidget);
      expect(sockets.length, greaterThan(socketsBefore));
      // Under the same session id, which is what displaces the other tab
      // rather than seating a stranger.
      final join = sockets.last.sentMessages.whereType<JoinMessage>().first;
      expect(join.sessionId, equals(FakeIdentityStore.testSessionId));
    });
  });
}
