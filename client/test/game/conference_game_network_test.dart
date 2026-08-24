import 'dart:async';

import 'package:client/game/conference_game.dart';
import 'package:client/services/network_client.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_socket.dart';

void main() {
  // These go through a real widget pump rather than `testWithGame`, because
  // connecting is asynchronous: the game has to keep ticking while the socket
  // opens, which is exactly what happens in the app.
  Future<({ConferenceGame game, FakeSocket socket})> pumpGame(
    WidgetTester tester,
  ) async {
    final (:client, :socket) = fakeNetwork();
    addTearDown(client.dispose);
    final game = ConferenceGame(network: client);
    // The game listens to a connection it does not own — in the app the
    // supervisor opens it, so here the test does.
    unawaited(client.connect());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameWidget(game: game)),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return (game: game, socket: socket);
  }

  /// Runs [frames] frames of the game loop.
  Future<void> tick(WidgetTester tester, {int frames = 12}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('leaves introducing itself to the supervisor', (tester) async {
    // Since Phase 4 the join carries a session id, which is identity, not
    // game state. The connection supervisor owns it — and it has to be the
    // *only* thing that sends one, or every reconnect would send two joins
    // on one socket and the server would drop the second as a duplicate.
    final (game: _, :socket) = await pumpGame(tester);

    expect(socket.sentMessages.whereType<JoinMessage>(), isEmpty);
  });

  testWidgets('remembers the id the server gave it', (tester) async {
    final (:game, :socket) = await pumpGame(tester);

    socket.emit(const WelcomeMessage(yourId: 'p7'));
    await tick(tester, frames: 2);

    expect(game.myId, 'p7');
  });

  testWidgets('shows the players the first snapshot named', (tester) async {
    final (:game, :socket) = await pumpGame(tester);

    socket
      ..emit(const WelcomeMessage(yourId: 'p7'))
      ..emit(
        const SnapshotMessage(
          appeared: [
            PlayerState(
              id: 'p1',
              name: 'Bob',
              color: 0xFF7ED9B6,
              cosmetic: PlayerCosmetic.cap,
              x: 100,
              y: 100,
            ),
          ],
          positions: [PlayerPosition(id: 'p1', x: 100, y: 100)],
        ),
      );
    await tick(tester, frames: 2);

    expect(game.remotePlayers.count, 1);
  });

  testWidgets('sends its position about ten times a second', (tester) async {
    final (:game, :socket) = await pumpGame(tester);
    socket.sent.clear();

    // Walk for a second: 60 frames of movement, ~10 messages.
    for (var i = 0; i < 60; i++) {
      game.bean.position.add(Vector2(2, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    final moves = socket.sentMessages.whereType<MoveMessage>();
    expect(moves.length, greaterThan(5));
    expect(moves.length, lessThan(20));
  });

  testWidgets('says nothing while the bean stands still', (tester) async {
    final (:game, :socket) = await pumpGame(tester);
    await tick(tester, frames: 20);
    socket.sent.clear();

    await tick(tester, frames: 120);

    expect(socket.sentMessages.whereType<MoveMessage>(), isEmpty);
  });

  testWidgets('clears the world when the server goes away', (tester) async {
    final (:game, :socket) = await pumpGame(tester);
    socket.emit(
      const SnapshotMessage(
        appeared: [
          PlayerState(
            id: 'p1',
            name: 'Bob',
            color: 0xFF7ED9B6,
            cosmetic: PlayerCosmetic.cap,
            x: 100,
            y: 100,
          ),
        ],
        positions: [PlayerPosition(id: 'p1', x: 100, y: 100)],
      ),
    );
    await tick(tester, frames: 2);
    expect(game.remotePlayers.count, 1);

    socket.dropFromServer();
    await tick(tester, frames: 4);

    // Leaving their beans standing there would be a lie — nobody is updating
    // them any more.
    expect(game.remotePlayers.count, isZero);
    expect(game.myId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the local bean moving with no server at all', (
    tester,
  ) async {
    // The core architecture decision, as a test: the local bean never waits
    // on the network, because the client owns its own position.
    final client = NetworkClient(
      url: Uri.parse('ws://test/ws'),
      openSocket: (_) => FakeSocket(openError: StateError('refused')),
    );
    addTearDown(client.dispose);
    final game = ConferenceGame(network: client);
    unawaited(client.connect());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameWidget(game: game)),
      ),
    );
    await tick(tester, frames: 4);
    final start = game.bean.position.clone();

    final knob = Offset(game.joystick.position.x, game.joystick.position.y);
    final gesture = await tester.startGesture(knob);
    await gesture.moveBy(const Offset(80, 0));
    await tick(tester, frames: 20);

    expect(game.bean.position.x, greaterThan(start.x));
    expect(client.status.value, ConnectionStatus.offline);
    expect(tester.takeException(), isNull);
    await gesture.up();
  });
}
