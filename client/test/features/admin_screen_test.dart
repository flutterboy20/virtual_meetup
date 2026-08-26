import 'package:client/app/app.dart';
import 'package:client/core/app_route.dart';
import 'package:client/features/admin/view/admin_screen.dart';
import 'package:client/features/admin/view_model/admin_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';
import 'package:provider/provider.dart';

import '../support/fake_identity_store.dart';
import '../support/fake_socket.dart';

void main() {
  const token = 'a-long-enough-test-token';

  /// Pumps the admin screen over a fake socket, and hands back the socket.
  Future<FakeSocket> pumpAdmin(WidgetTester tester) async {
    final network = fakeNetwork();
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AdminViewModel>(
          create: (_) => AdminViewModel(network: network.client),
          child: const AdminScreen(),
        ),
      ),
    );
    return network.socket;
  }

  /// Types the token and lets the fake server say yes.
  Future<void> unlock(WidgetTester tester, FakeSocket socket) async {
    await tester.enterText(find.byType(TextField), token);
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    socket.emit(
      const AdminAuthResultMessage(authorized: true, detail: 'Authenticated.'),
    );
    await tester.pumpAndSettle();
  }

  group('the gate', () {
    testWidgets('asks for a token before anything else', (tester) async {
      await pumpAdmin(tester);

      expect(find.text('Moderation'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('the token field is obscured', (tester) async {
      // A moderator types this on a phone in a room full of people.
      await pumpAdmin(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('a wrong token keeps the gate shut', (tester) async {
      final socket = await pumpAdmin(tester);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Unlock'));
      await tester.pump();

      socket.emit(
        const AdminAuthResultMessage(
          authorized: false,
          detail: 'That token was not accepted.',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unlock'), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('a good token shows the list', (tester) async {
      final socket = await pumpAdmin(tester);

      await unlock(tester, socket);
      socket.emit(
        const AdminPlayerListMessage(
          players: [
            AdminPlayerSummary(
              id: 'p1',
              name: 'Ada',
              isNameMuted: false,
              x: 800,
              y: 600,
            ),
          ],
          online: 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ada'), findsOneWidget);
      // The head count moved onto the filter chips in Phase 10, where it is
      // now one number per map plus a total.
      expect(find.text('All 1'), findsOneWidget);
    });
  });

  group('actions', () {
    Future<FakeSocket> withOnePlayer(WidgetTester tester) async {
      final socket = await pumpAdmin(tester);
      await unlock(tester, socket);
      socket.emit(
        const AdminPlayerListMessage(
          players: [
            AdminPlayerSummary(
              id: 'p1',
              name: 'Ada',
              isNameMuted: false,
              x: 0,
              y: 0,
            ),
          ],
          online: 1,
        ),
      );
      await tester.pumpAndSettle();
      socket.sent.clear();
      return socket;
    }

    testWidgets('a kick asks first, and cancelling sends nothing', (
      tester,
    ) async {
      // The realistic mistake is the right button on the wrong row, so the
      // dialog names the person.
      final socket = await withOnePlayer(tester);

      await tester.tap(find.byTooltip('Kick'));
      await tester.pumpAndSettle();
      expect(find.text('Kick Ada?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(socket.sent, isEmpty);
    });

    testWidgets('confirming a kick sends one kick', (tester) async {
      final socket = await withOnePlayer(tester);

      await tester.tap(find.byTooltip('Kick'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Kick'));
      await tester.pumpAndSettle();

      expect(
        socket.sentMessages.single,
        equals(const AdminKickMessage(playerId: 'p1')),
      );
    });

    testWidgets('confirming a ban sends one ban', (tester) async {
      final socket = await withOnePlayer(tester);

      await tester.tap(find.byTooltip('Ban'));
      await tester.pumpAndSettle();
      expect(find.text('Ban Ada?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Ban'));
      await tester.pumpAndSettle();

      expect(
        socket.sentMessages.single,
        equals(const AdminBanMessage(playerId: 'p1')),
      );
    });

    testWidgets('confirming a mute sends one mute', (tester) async {
      final socket = await withOnePlayer(tester);

      await tester.tap(find.byTooltip('Mute name'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mute'));
      await tester.pumpAndSettle();

      expect(
        socket.sentMessages.single,
        equals(const AdminMuteNameMessage(playerId: 'p1', muted: true)),
      );
    });

    testWidgets('a muted row offers to restore instead', (tester) async {
      final socket = await pumpAdmin(tester);
      await unlock(tester, socket);
      socket.emit(
        const AdminPlayerListMessage(
          players: [
            AdminPlayerSummary(
              id: 'p1',
              name: 'Rude',
              isNameMuted: true,
              x: 0,
              y: 0,
            ),
          ],
          online: 1,
        ),
      );
      await tester.pumpAndSettle();
      socket.sent.clear();

      // The chosen name is still on screen — a list of identical Guests is
      // a list nobody can moderate.
      expect(find.text('Rude'), findsOneWidget);
      expect(find.text(mutedDisplayName), findsOneWidget);

      await tester.tap(find.byTooltip('Restore name'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();

      expect(
        socket.sentMessages.single,
        equals(const AdminMuteNameMessage(playerId: 'p1', muted: false)),
      );
    });

    testWidgets('a result is reported to the moderator', (tester) async {
      final socket = await withOnePlayer(tester);

      socket.emit(
        const AdminActionResultMessage(
          action: AdminAction.kick,
          targetId: 'p1',
          targetName: 'Ada',
        ),
      );
      // Three pumps, deliberately: one to deliver the message and notify,
      // one to run the post-frame callback that shows the bar, one to let it
      // animate in far enough to be found.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Kicked Ada'), findsOneWidget);
    });

    testWidgets('search narrows the list', (tester) async {
      final socket = await pumpAdmin(tester);
      await unlock(tester, socket);
      socket.emit(
        const AdminPlayerListMessage(
          players: [
            AdminPlayerSummary(
              id: 'p1',
              name: 'Ada',
              isNameMuted: false,
              x: 0,
              y: 0,
            ),
            AdminPlayerSummary(
              id: 'p2',
              name: 'Bob',
              isNameMuted: false,
              x: 0,
              y: 0,
            ),
          ],
          online: 2,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'bob');
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Ada'), findsNothing);
    });

    testWidgets('locking returns to the gate', (tester) async {
      final socket = await withOnePlayer(tester);

      await tester.tap(find.byTooltip('Lock'));
      await tester.pumpAndSettle();

      expect(find.text('Unlock'), findsOneWidget);
      expect(find.text('Ada'), findsNothing);
      expect(socket.sent, isEmpty);
    });
  });

  group('the admin screen is not reachable from the player app', () {
    testWidgets('the world route shows no way to get to it', (tester) async {
      // Hiding the UI is not security — the server is what refuses an
      // unauthenticated action. But an attendee who never finds the door
      // never rattles it either, so nothing player-facing may mention it.
      await tester.pumpWidget(
        VirtualConferenceApp(store: FakeIdentityStore()),
      );
      // The welcome screen animates forever (a drifting backdrop and a
      // parade of beans), so `pumpAndSettle` would never settle: pump the
      // bootstrap read and the status fetch by hand instead.
      await tester.pump();
      await tester.pump();

      expect(find.byType(AdminScreen), findsNothing);
      expect(find.textContaining('admin', findRichText: true), findsNothing);
      expect(find.textContaining('Admin', findRichText: true), findsNothing);
      expect(
        find.textContaining('Moderation', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('the admin route shows only the gate', (tester) async {
      final network = fakeNetwork();
      await tester.pumpWidget(
        VirtualConferenceApp(
          store: FakeIdentityStore(),
          route: AppRoute.admin,
          adminNetwork: network.client,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminScreen), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
    });
  });

  group('the event tab', () {
    testWidgets('is behind the token, like everything else', (tester) async {
      await pumpAdmin(tester);

      expect(find.text('EVENT'), findsNothing);
    });

    testWidgets('shows a dial per map and the document itself', (
      tester,
    ) async {
      final socket = await pumpAdmin(tester);
      await unlock(tester, socket);

      await tester.tap(find.text('EVENT'));
      await tester.pumpAndSettle();

      for (final map in MapId.values) {
        expect(find.text(map.label), findsOneWidget);
      }
      // The editor opens on what is live, not on an empty box somebody could
      // reasonably mistake for an empty config.
      expect(find.textContaining('worldName'), findsOneWidget);
    });

    testWidgets('the dial pushes a whole document', (tester) async {
      final socket = await pumpAdmin(tester);
      await unlock(tester, socket);
      await tester.tap(find.text('EVENT'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Fewer').first);
      await tester.pumpAndSettle();

      final sent = socket.sentMessages
          .whereType<AdminSetConfigMessage>()
          .single;
      expect(
        parseAppConfig(sent.document).botCountFor(MapId.conference),
        isNotNull,
      );
    });

    testWidgets('will not push until something has been edited', (
      tester,
    ) async {
      final socket = await pumpAdmin(tester);
      await unlock(tester, socket);
      await tester.tap(find.text('EVENT'));
      await tester.pumpAndSettle();

      // The panel scrolls, and the buttons live under a sixteen-line editor.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      final push = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Push to everybody'),
      );

      expect(push.onPressed, isNull);
      expect(find.text('This is what the server is serving.'), findsOneWidget);
    });

    /// The document editor, told apart from the People tab's search box by
    /// the only thing that is structurally different about it.
    final editor = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.maxLines == 16,
    );

    TextEditingController controllerOf(WidgetTester tester) =>
        tester.widget<TextField>(editor).controller!;

    /// Opens the event tab on an unlocked screen.
    Future<FakeSocket> openEventTab(WidgetTester tester) async {
      final socket = await pumpAdmin(tester);
      await unlock(tester, socket);
      await tester.tap(find.text('EVENT'));
      await tester.pumpAndSettle();
      return socket;
    }

    testWidgets('the player list does not move the caret', (tester) async {
      // The regression this whole panel was rewritten for: the list arrives
      // once a second, and the editor used to be re-filled from the model on
      // every rebuild — which collapsed the selection and dropped the caret
      // to the end while somebody was typing in the middle of a line.
      final socket = await openEventTab(tester);
      final controller = controllerOf(tester)
        ..selection = const TextSelection(baseOffset: 4, extentOffset: 9);

      socket.emit(const AdminPlayerListMessage(players: [], online: 0));
      await tester.pump();

      expect(controller.selection.baseOffset, 4);
      expect(controller.selection.extentOffset, 9);
    });

    testWidgets('a push the server normalises stops reading as unpushed', (
      tester,
    ) async {
      // The other half of the same bug: the banner compared the raw text
      // against the server's pretty-printed copy, so any document that came
      // back re-indented — which is all of them — read as never pushed.
      final socket = await openEventTab(tester);
      await tester.enterText(editor, '{"worldName":"Compacted"}');
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Push to everybody'));
      await tester.pump();

      expect(
        socket.sentMessages.whereType<AdminSetConfigMessage>().single.document,
        '{"worldName":"Compacted"}',
      );

      socket.emit(
        const ConfigMessage(config: AppConfig(worldName: 'Compacted')),
      );
      await tester.pumpAndSettle();

      // The adopted document is ten pretty-printed lines where a compact one
      // was, so the editor grows and pushes the banner off the viewport.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('This is what the server is serving.'), findsOneWidget);
      expect(controllerOf(tester).text, contains('"worldName": "Compacted"'));
    });

    testWidgets('a push of the same document still clears the warning', (
      tester,
    ) async {
      // A moderator who only reorders keys or fixes the indentation pushes a
      // document that parses to exactly what the server already had, so the
      // config that comes back is byte-identical to the one before it. The
      // editor has to notice the *answer*, not a change in the text.
      final socket = await openEventTab(tester);
      final document = controllerOf(tester).text;
      await tester.enterText(editor, '$document ');
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Push to everybody'));
      await tester.pump();
      socket.emit(const ConfigMessage(config: AppConfig.defaults));
      await tester.pumpAndSettle();

      expect(find.text('This is what the server is serving.'), findsOneWidget);
      expect(controllerOf(tester).text, document);
    });

    testWidgets('a refused push keeps what was typed', (tester) async {
      final socket = await openEventTab(tester);
      await tester.enterText(editor, 'not json');
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Push to everybody'));
      await tester.pump();

      socket.emit(
        const AdminErrorMessage(
          reason: AdminError.badRequest,
          detail: 'That document is not JSON.',
        ),
      );
      await tester.pumpAndSettle();

      expect(controllerOf(tester).text, 'not json');
      expect(
        find.text('Not pushed yet. The world is still showing the old copy.'),
        findsOneWidget,
      );
    });

    testWidgets('an edit somebody else pushed is not thrown away', (
      tester,
    ) async {
      final socket = await openEventTab(tester);
      await tester.enterText(editor, '{"worldName":"Mine"}');
      await tester.pump();

      socket.emit(const ConfigMessage(config: AppConfig(worldName: 'Theirs')));
      await tester.pumpAndSettle();

      expect(controllerOf(tester).text, '{"worldName":"Mine"}');
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('somebody else changed the document'),
        findsOneWidget,
      );
    });

    testWidgets('copies the document to the clipboard', (tester) async {
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

      await openEventTab(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Copy'));
      await tester.pumpAndSettle();

      expect(copied.single, contains('"worldName"'));
    });

    testWidgets('tidy re-indents without dropping unknown keys', (
      tester,
    ) async {
      await openEventTab(tester);
      await tester.enterText(editor, '{"worldName":"Held","somethingNew":1}');
      await tester.pump();

      // Scrolled to first: the panel grew a booth editor above the document,
      // so the button is off the bottom of a phone-sized screen.
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Tidy'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Tidy'));
      await tester.pumpAndSettle();

      expect(controllerOf(tester).text, contains('"worldName": "Held"'));
      expect(controllerOf(tester).text, contains('"somethingNew": 1'));
    });
  });

  group('the banned tab', () {
    /// Unlocks the screen, opens the Banned tab and pushes [bans] into it.
    Future<FakeSocket> openBanTab(
      WidgetTester tester,
      List<BannedSession> bans,
    ) async {
      final socket = await pumpAdmin(tester);
      await unlock(tester, socket);
      await tester.tap(find.text('BANNED'));
      await tester.pumpAndSettle();
      socket.emit(AdminBanListMessage(bans: bans));
      await tester.pumpAndSettle();
      return socket;
    }

    testWidgets('says so plainly when nobody is banned', (tester) async {
      await openBanTab(tester, const []);

      expect(find.text('Nobody is banned.'), findsOneWidget);
    });

    testWidgets('names a ban this run still remembers', (tester) async {
      await openBanTab(tester, [
        BannedSession(
          id: '0123456789abcdef',
          name: 'Rude',
          bannedAt: DateTime.utc(2026, 8, 22, 18, 30),
        ),
      ]);

      expect(find.text('Rude'), findsOneWidget);
      expect(find.textContaining('0123456789abcdef'), findsOneWidget);
    });

    testWidgets('is honest about one it has forgotten', (tester) async {
      // A ban read off disk after a restart. Saying nothing would be worse
      // than saying "I do not know who this was" — the row is still real and
      // still has to be liftable.
      await openBanTab(tester, const [
        BannedSession(id: 'fedcba9876543210'),
      ]);

      expect(find.text('Banned before the last restart'), findsOneWidget);
      expect(find.byTooltip('Lift the ban'), findsOneWidget);
    });

    testWidgets('lifting one asks first, then sends the handle', (
      tester,
    ) async {
      final socket = await openBanTab(tester, [
        BannedSession(
          id: '0123456789abcdef',
          name: 'Rude',
          bannedAt: DateTime.utc(2026, 8, 22, 18, 30),
        ),
      ]);

      await tester.tap(find.byTooltip('Lift the ban'));
      await tester.pumpAndSettle();
      // Nothing may go up until the question has been answered.
      expect(socket.sentMessages.whereType<AdminUnbanMessage>(), isEmpty);
      expect(find.text('Lift this ban?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Lift'));
      await tester.pumpAndSettle();

      expect(
        socket.sentMessages.whereType<AdminUnbanMessage>().single.banId,
        equals('0123456789abcdef'),
      );
    });

    testWidgets('cancelling the question sends nothing', (tester) async {
      final socket = await openBanTab(tester, [
        BannedSession(
          id: '0123456789abcdef',
          name: 'Rude',
          bannedAt: DateTime.utc(2026, 8, 22, 18, 30),
        ),
      ]);

      await tester.tap(find.byTooltip('Lift the ban'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(socket.sentMessages.whereType<AdminUnbanMessage>(), isEmpty);
    });

    testWidgets('says out loud that a ban is not a lock', (tester) async {
      // A moderator who believes a ban is permanent will not escalate a
      // problem that has walked back in under a new name.
      await openBanTab(tester, const [
        BannedSession(id: 'fedcba9876543210'),
      ]);

      expect(
        find.textContaining('Clearing site data'),
        findsOneWidget,
      );
    });
  });

  group('the booth editor', () {
    /// Opens the event tab on an unlocked screen holding [booths].
    Future<FakeSocket> openWithBooths(
      WidgetTester tester,
      List<Map<String, Object?>> booths,
    ) async {
      final socket = await pumpAdmin(tester);
      await unlock(tester, socket);
      await tester.tap(find.text('EVENT'));
      await tester.pumpAndSettle();
      socket.emit(ConfigMessage(config: AppConfig(sponsors: booths)));
      await tester.pumpAndSettle();
      return socket;
    }

    const acme = {
      'id': 'acme',
      'name': 'Acme',
      'x': 1130.0,
      'y': 478.0,
      'color': '#54C5F8',
    };

    testWidgets('offers the bundled list when the config names none', (
      tester,
    ) async {
      await openWithBooths(tester, const []);

      expect(find.text('Start from the bundled list'), findsOneWidget);
      expect(find.text('Add a booth'), findsOneWidget);
    });

    testWidgets('shows a row per booth, with where it stands', (tester) async {
      await openWithBooths(tester, const [acme]);

      expect(find.text('Acme'), findsOneWidget);
      expect(find.textContaining('1130, 478'), findsOneWidget);
    });

    testWidgets('says a booth cannot be read rather than hiding it', (
      tester,
    ) async {
      // The one person who can fix a broken entry is looking at this screen.
      await openWithBooths(tester, const [
        {'id': 'broken'},
      ]);

      expect(find.textContaining('cannot be read'), findsOneWidget);
    });

    testWidgets('removing one pushes a document without it', (tester) async {
      final socket = await openWithBooths(tester, const [acme]);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      final sent = socket.sentMessages
          .whereType<AdminSetConfigMessage>()
          .single;
      expect(parseAppConfig(sent.document).sponsors, isEmpty);
    });

    testWidgets('a booth typed into the dialog lands in the document', (
      tester,
    ) async {
      final socket = await openWithBooths(tester, const []);

      await tester.tap(find.text('Add a booth'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Beta Corp',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Id'), 'beta');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final sent = socket.sentMessages
          .whereType<AdminSetConfigMessage>()
          .single;
      final booth = parseAppConfig(sent.document).sponsors.single;
      expect(booth['name'], equals('Beta Corp'));
      expect(booth['id'], equals('beta'));
      // The defaults put it in the sponsor row rather than at the origin.
      expect(booth['x'], equals(1130.0));
    });

    testWidgets('a booth the world would refuse never leaves the dialog', (
      tester,
    ) async {
      final socket = await openWithBooths(tester, const []);

      await tester.tap(find.text('Add a booth'));
      await tester.pumpAndSettle();
      // No id, which is the one thing every booth must have.
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Beta');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Add a booth'), findsWidgets);
      expect(
        socket.sentMessages.whereType<AdminSetConfigMessage>(),
        isEmpty,
      );
    });
  });

  group('the maintenance card', () {
    Future<FakeSocket> openEventTab(WidgetTester tester) async {
      final socket = await pumpAdmin(tester);
      await unlock(tester, socket);
      await tester.tap(find.text('EVENT'));
      await tester.pumpAndSettle();
      return socket;
    }

    /// Scrolls the panel to the bottom, where the card lives.
    ///
    /// One drag and one settle, deliberately. `ensureVisible` cannot be used
    /// here — the card is past the end of a lazy list, so it is not built
    /// until something scrolls to it — and every extra `pumpAndSettle`
    /// advances the *fake* clock, while the card below has a timer waiting
    /// on the end of a maintenance window. A scroll that pumped its way past
    /// that moment would fire the timer before the wall clock got there.
    Future<void> toCard(WidgetTester tester) async {
      // A config arriving raises a toast, and a toast sits across the bottom
      // of the screen — which is exactly where the card lands once the panel
      // is scrolled to its end. Cleared rather than waited out: waiting means
      // pumping four seconds of *fake* clock past a card that has a timer in
      // it.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pumpAndSettle();

      final list = tester.getRect(find.byType(ListView));
      await tester.dragFrom(
        // Six pixels in from the left edge. The list pads its children by
        // sixteen, so this strip is the scrollable itself and nothing else —
        // in particular it is not the document editor, which is a sixteen-
        // line scrollable of its own and swallows a drag started over it.
        Offset(list.left + 6, list.center.dy),
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers to close an open event', (tester) async {
      await openEventTab(tester);
      await toCard(tester);

      expect(find.text('Close the event for maintenance'), findsOneWidget);
      expect(find.text('Reopen the event now'), findsNothing);
    });

    testWidgets('shows the window and offers to reopen a closed one', (
      tester,
    ) async {
      final socket = await openEventTab(tester);
      socket.emit(
        ConfigMessage(
          config: AppConfig(
            maintenanceUntil: DateTime(2031, 8, 22, 18, 30).toUtc(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await toCard(tester);

      expect(find.text('Reopen the event now'), findsOneWidget);
      expect(find.text('Close the event for maintenance'), findsNothing);
      expect(
        find.textContaining('22 Aug 2031, 18:30'),
        findsOneWidget,
      );
    });

    testWidgets('opens itself again when the window runs out', (tester) async {
      // A window ends by the clock. The server just starts letting people in
      // — nothing is pushed down the socket — so without a timer this card
      // would keep offering to reopen a door that was already open.
      final socket = await openEventTab(tester);
      socket.emit(
        ConfigMessage(
          config: AppConfig(
            maintenanceUntil: DateTime.now().toUtc().add(
              const Duration(seconds: 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await toCard(tester);

      expect(find.text('Reopen the event now'), findsOneWidget);

      // A real second, then a pumped one. The window is judged against
      // `DateTime.now()`, which a widget test's fake clock does not move —
      // so the wait has to be real, and the pump is what lets the card's
      // timer fire against it.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1200)),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.text('Close the event for maintenance'), findsOneWidget);
      expect(find.text('Reopen the event now'), findsNothing);
      expect(find.textContaining('the event is open again'), findsOneWidget);
    });

    testWidgets('closing asks for the token before it sends anything', (
      tester,
    ) async {
      // The dialog is the point of the whole flow: nothing may go up the
      // socket until somebody has typed the token a second time.
      final socket = await openEventTab(tester);
      socket.emit(
        ConfigMessage(
          config: AppConfig(
            maintenanceUntil: DateTime(2031, 8, 22, 18, 30).toUtc(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await toCard(tester);

      await tester.tap(find.text('Reopen the event now'));
      await tester.pumpAndSettle();

      expect(find.text('Reopen the event'), findsOneWidget);
      expect(
        socket.sentMessages.whereType<AdminSetMaintenanceMessage>(),
        isEmpty,
      );
    });

    testWidgets('cancelling the token dialog sends nothing', (tester) async {
      final socket = await openEventTab(tester);
      socket.emit(
        ConfigMessage(
          config: AppConfig(
            maintenanceUntil: DateTime(2031, 8, 22, 18, 30).toUtc(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await toCard(tester);

      await tester.tap(find.text('Reopen the event now'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(
        socket.sentMessages.whereType<AdminSetMaintenanceMessage>(),
        isEmpty,
      );
    });

    testWidgets('the typed token is what goes up the socket', (tester) async {
      final socket = await openEventTab(tester);
      socket.emit(
        ConfigMessage(
          config: AppConfig(
            maintenanceUntil: DateTime(2031, 8, 22, 18, 30).toUtc(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await toCard(tester);

      await tester.tap(find.text('Reopen the event now'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Moderation token'),
        token,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      final sent = socket.sentMessages
          .whereType<AdminSetMaintenanceMessage>()
          .single;
      expect(sent.token, equals(token));
      expect(sent.until, isNull);
    });

    testWidgets('the token field is obscured, like the gate', (tester) async {
      final socket = await openEventTab(tester);
      socket.emit(
        ConfigMessage(
          config: AppConfig(
            maintenanceUntil: DateTime(2031, 8, 22, 18, 30).toUtc(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await toCard(tester);

      await tester.tap(find.text('Reopen the event now'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Moderation token'),
      );
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
    });
  });
}
