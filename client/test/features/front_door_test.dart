import 'package:client/app/app.dart';
import 'package:client/core/player_identity.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/full/view/full_screen.dart';
import 'package:client/features/welcome/view/welcome_screen.dart';
import 'package:client/services/server_status_service.dart';
import 'package:client/services/sponsor_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_identity_store.dart';
import '../support/fake_socket.dart';
import '../support/front_door.dart';

class _Online implements ServerStatusService {
  @override
  Future<ServerStatus> fetch() async => const ServerOnline(7);
}

void main() {
  const ada = PlayerIdentity(
    sessionId: FakeIdentityStore.testSessionId,
    name: 'Ada',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
  );

  Future<FakeSocket> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (:client, :socket) = fakeNetwork();
    addTearDown(client.dispose);

    await tester.pumpWidget(
      VirtualConferenceApp(
        store: FakeIdentityStore(identity: ada),
        statusService: _Online(),
        network: client,
        sponsors: const StaticSponsorRepository([]),
      ),
    );
    await tester.pump();
    await tester.pump();
    return socket;
  }

  // The phones the door is laid out for: a common Android, an iPhone, and
  // the short end of what is still in people's pockets.
  for (final size in const [Size(390, 844), Size(360, 780), Size(375, 667)]) {
    testWidgets('the way in is on screen without scrolling at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await pumpAt(tester, size);

      final button = tester.getRect(find.text(WelcomeScreen.enterLabel));
      expect(button.bottom, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the door itself is on paper', (tester) async {
    await pumpAt(tester, const Size(390, 844));

    // Below the screen's own Theme, which is where its widgets read from.
    final theme = Theme.of(
      tester.element(find.text(WelcomeScreen.enterLabel)),
    );
    expect(theme.brightness, equals(Brightness.light));
  });

  testWidgets('being turned away is on the same paper as the door', (
    tester,
  ) async {
    final socket = await pumpAt(tester, const Size(390, 844));
    await tapEnter(tester);
    await tester.pump();

    socket.emit(
      const JoinRejectedMessage(
        reason: JoinRejection.worldFull,
        detail: 'The event is full right now.',
      ),
    );
    await tester.pump();
    await tester.pump();

    final theme = Theme.of(tester.element(find.byType(FullScreen)));
    expect(theme.scaffoldBackgroundColor, equals(LanyardColors.paper));
  });
}
