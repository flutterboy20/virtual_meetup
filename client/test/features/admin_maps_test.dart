import 'package:client/features/admin/view/admin_screen.dart';
import 'package:client/features/admin/view_model/admin_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';
import 'package:provider/provider.dart';

import '../support/fake_socket.dart';

/// A roster row, with sensible defaults for everything a test is not about.
AdminPlayerSummary row(
  String id,
  String name, {
  MapId map = MapId.conference,
  bool muted = false,
}) => AdminPlayerSummary(
  id: id,
  name: name,
  isNameMuted: muted,
  x: 800,
  y: 600,
  map: map,
);

void main() {
  group('AdminPlayerSummary', () {
    test('round-trips its map', () {
      for (final map in MapId.values) {
        final summary = row('p1', 'Ada', map: map);
        expect(
          AdminPlayerSummary.fromJson(summary.toJson()),
          equals(summary),
        );
      }
    });

    test('a summary with no map reads as the conference', () {
      // Every roster row written before Phase 10 meant the conference, and a
      // moderation screen is the last place to start refusing rows over a
      // missing field.
      final json = row('p1', 'Ada').toJson()..remove('map');

      expect(AdminPlayerSummary.fromJson(json).map, equals(MapId.conference));
    });

    test('two players on different maps are not the same player', () {
      expect(
        row('p1', 'Ada'),
        isNot(equals(row('p1', 'Ada', map: MapId.beach))),
      );
    });
  });

  group('AdminPlayerListMessage', () {
    test('round-trips onlineByMap', () {
      const message = AdminPlayerListMessage(
        players: [],
        online: 12,
        onlineByMap: {MapId.conference: 9, MapId.beach: 3},
      );

      final decoded = decodeMessage(encodeMessage(message));

      expect(decoded, equals(message));
      expect(
        (decoded as AdminPlayerListMessage).onlineByMap[MapId.beach],
        equals(3),
      );
    });

    test('online stays the grand total', () {
      const message = AdminPlayerListMessage(
        players: [],
        online: 12,
        onlineByMap: {MapId.conference: 9, MapId.beach: 3},
      );

      expect(
        message.onlineByMap.values.fold(0, (a, b) => a + b),
        equals(message.online),
      );
    });

    test('a message with no onlineByMap still decodes', () {
      final json = const AdminPlayerListMessage(
        players: [],
        online: 4,
      ).toJson()..remove('onlineByMap');

      final decoded = AdminPlayerListMessage.fromJson(json);

      expect(decoded.online, equals(4));
      expect(decoded.onlineByMap, isEmpty);
    });

    test('an unreadable onlineByMap costs the counts and nothing else', () {
      final json = const AdminPlayerListMessage(
        players: [],
        online: 4,
      ).toJson();
      json['onlineByMap'] = {'lagoon': 3, 'beach': 'lots'};

      final decoded = AdminPlayerListMessage.fromJson(json);

      expect(decoded.online, equals(4));
      expect(decoded.onlineByMap, isEmpty);
    });
  });

  group('AdminViewModel', () {
    /// An unlocked view model holding [players].
    ({AdminViewModel model, FakeSocket socket}) unlocked(
      List<AdminPlayerSummary> players, {
      Map<MapId, int> byMap = const {},
    }) {
      final (:client, :socket) = fakeNetwork();
      final model = AdminViewModel(network: client);
      unawaitedSubmit(model, 'a-long-enough-test-token');
      return (model: model, socket: socket);
    }

    Future<AdminViewModel> withRoster(
      List<AdminPlayerSummary> players, {
      Map<MapId, int> byMap = const {},
    }) async {
      final (:model, :socket) = unlocked(players);
      await Future<void>.delayed(Duration.zero);
      socket
        ..emit(const AdminAuthResultMessage(authorized: true, detail: 'ok'))
        ..emit(
          AdminPlayerListMessage(
            players: players,
            online: players.length,
            onlineByMap: byMap,
          ),
        );
      await Future<void>.delayed(Duration.zero);
      return model;
    }

    test('the roster is the union, grouped by map', () async {
      final model = await withRoster([
        row('bp1', 'Zoe', map: MapId.beach),
        row('p1', 'Ada'),
        row('p2', 'Brij'),
      ]);

      expect(
        model.visiblePlayers.map((player) => player.name),
        equals(['Ada', 'Brij', 'Zoe']),
      );
      expect(model.isGroupedByMap, isTrue);

      model.dispose();
    });

    test('a filter narrows the list to one map', () async {
      final model = await withRoster([
        row('p1', 'Ada'),
        row('bp1', 'Zoe', map: MapId.beach),
      ]);

      model.setMapFilter(MapId.beach);

      expect(
        model.visiblePlayers.map((player) => player.name),
        equals(['Zoe']),
      );
      expect(model.isGroupedByMap, isFalse);

      model.setMapFilter(null);
      expect(model.visiblePlayers, hasLength(2));

      model.dispose();
    });

    test('filter and search compose', () async {
      // They answer different questions — where, and who — and a report
      // usually arrives with both halves of the answer in it.
      final model = await withRoster([
        row('p1', 'Ada'),
        row('p2', 'Adam'),
        row('bp1', 'Ada', map: MapId.beach),
        row('bp2', 'Zoe', map: MapId.beach),
      ]);

      model.setSearch('ada');
      expect(model.visiblePlayers, hasLength(3));

      model.setMapFilter(MapId.beach);
      expect(model.visiblePlayers.single.id, equals('bp1'));

      // Changing the filter deliberately does not wipe the search.
      expect(model.search, equals('ada'));

      model.dispose();
    });

    test('chip counts come from the server, not from the rows', () async {
      // The roster is capped by nothing, but it can be a tick stale. A chip
      // that disagreed with the number beside it would be worse than none.
      final model = await withRoster(
        [row('p1', 'Ada')],
        byMap: const {MapId.conference: 30, MapId.beach: 12},
      );

      expect(model.countFor(MapId.conference), equals(30));
      expect(model.countFor(MapId.beach), equals(12));
      expect(model.countFor(null), equals(model.online));

      model.dispose();
    });

    test('an older server without byMap falls back to counting rows', () async {
      final model = await withRoster([
        row('p1', 'Ada'),
        row('p2', 'Brij'),
        row('bp1', 'Zoe', map: MapId.beach),
      ]);

      expect(model.countFor(MapId.conference), equals(2));
      expect(model.countFor(MapId.beach), equals(1));

      model.dispose();
    });

    test('locking forgets the filter along with everything else', () async {
      final model = await withRoster([row('bp1', 'Zoe', map: MapId.beach)])
        ..setMapFilter(MapId.beach)
        ..lock();

      expect(model.mapFilter, isNull);
      expect(model.onlineByMap, isEmpty);
      expect(model.players, isEmpty);

      model.dispose();
    });

    test('a kick names the player, wherever they are standing', () async {
      final (:client, :socket) = fakeNetwork();
      final model = AdminViewModel(network: client);
      unawaitedSubmit(model, 'a-long-enough-test-token');
      await Future<void>.delayed(Duration.zero);
      socket
        ..emit(const AdminAuthResultMessage(authorized: true, detail: 'ok'))
        ..sent.clear();
      await Future<void>.delayed(Duration.zero);

      model.kick('bp1');

      // The screen sends a player id and nothing about a map: the server
      // finds them on whichever relay they are on, which is safe because a
      // session is seated in exactly one registry at a time.
      final sent = decodeMessage(socket.sent.single);
      expect(sent, isA<AdminKickMessage>());
      expect((sent as AdminKickMessage).playerId, equals('bp1'));

      model.dispose();
    });
  });

  group('the moderation screen', () {
    Future<AdminViewModel> pumpUnlocked(
      WidgetTester tester,
      List<AdminPlayerSummary> players, {
      Map<MapId, int> byMap = const {},
    }) async {
      final (:client, :socket) = fakeNetwork();
      final model = AdminViewModel(network: client);
      addTearDown(model.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AdminViewModel>.value(
            value: model,
            child: const AdminScreen(),
          ),
        ),
      );
      unawaitedSubmit(model, 'a-long-enough-test-token');
      await tester.pump();
      socket
        ..emit(const AdminAuthResultMessage(authorized: true, detail: 'ok'))
        ..emit(
          AdminPlayerListMessage(
            players: players,
            online: players.length,
            onlineByMap: byMap,
          ),
        );
      await tester.pumpAndSettle();
      return model;
    }

    testWidgets('shows a chip per map, with counts', (tester) async {
      await pumpUnlocked(
        tester,
        [row('p1', 'Ada'), row('bp1', 'Zoe', map: MapId.beach)],
        byMap: const {MapId.conference: 30, MapId.beach: 12},
      );

      expect(find.text('All 2'), findsOneWidget);
      expect(find.text('Conference 30'), findsOneWidget);
      expect(find.text('Beach 12'), findsOneWidget);
    });

    testWidgets('groups by map with All selected', (tester) async {
      await pumpUnlocked(tester, [
        row('p1', 'Ada'),
        row('bp1', 'Zoe', map: MapId.beach),
      ]);

      expect(find.text('CONFERENCE'), findsOneWidget);
      expect(find.text('BEACH'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Zoe'), findsOneWidget);
    });

    testWidgets('tapping a chip filters, and drops the headings', (
      tester,
    ) async {
      await pumpUnlocked(tester, [
        row('p1', 'Ada'),
        row('bp1', 'Zoe', map: MapId.beach),
      ]);

      await tester.tap(find.text('Beach 1'));
      await tester.pumpAndSettle();

      expect(find.text('Zoe'), findsOneWidget);
      expect(find.text('Ada'), findsNothing);
      // A heading over a list that is already one map says what the chip
      // above it just said.
      expect(find.text('BEACH'), findsNothing);
    });

    testWidgets('every row names its map beside the coordinates', (
      tester,
    ) async {
      // The two maps are separate coordinate spaces, so a position without a
      // map is not an answer to "where are they".
      await pumpUnlocked(tester, [row('bp1', 'Zoe', map: MapId.beach)]);

      expect(
        find.text('Beach  ·  bp1  ·  800, 600'),
        findsOneWidget,
      );
    });
  });
}
