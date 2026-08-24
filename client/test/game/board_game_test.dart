import 'dart:async';

import 'package:client/game/beach_layout.dart';
import 'package:client/game/beach_map.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/game/world_hud.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_socket.dart';

/// A point out in the open sea, well clear of the raft and the sandbar.
final Vector2 _sea = Vector2(300, 700);

/// A point on the sand, well clear of everything.
final Vector2 _sand = Vector2(600, 250);

/// The middle of the big board, in world units.
Vector2 get _atBoard => Vector2(
  (BeachLayout.bigBoard.left + BeachLayout.bigBoard.right) / 2,
  (BeachLayout.bigBoard.top + BeachLayout.bigBoard.bottom) / 2,
);

/// The middle of the hint bean, in world units.
Vector2 get _atHint =>
    Vector2(BeachLayout.hintBeanX, BeachLayout.hintBeanY - 20);

/// The player state a snapshot would carry for somebody standing at [at].
PlayerState _player(
  String id,
  Vector2 at, {
  bool hasBoard = false,
}) => PlayerState(
  id: id,
  name: 'Player $id',
  color: 0xFF54C5F8,
  cosmetic: PlayerCosmetic.none,
  x: at.x,
  y: at.y,
  hasBoard: hasBoard,
);

void main() {
  /// Pumps a game on [map] with a fake socket behind it.
  Future<({ConferenceGame game, FakeSocket socket, List<bool> persisted})>
  pumpGame(
    WidgetTester tester, {
    GameMap map = const BeachMap(),
    bool hasBoard = false,
  }) async {
    final (:client, :socket) = fakeNetwork();
    addTearDown(client.dispose);
    final persisted = <bool>[];
    final hud = WorldHud();
    addTearDown(hud.dispose);
    final game = ConferenceGame(
      network: client,
      map: map,
      hud: hud,
      hasBoard: hasBoard,
      onBoardChanged: ({required hasBoard}) => persisted.add(hasBoard),
    );
    unawaited(client.connect());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameWidget(game: game)),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return (game: game, socket: socket, persisted: persisted);
  }

  Future<void> tick(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Taps the world point [at], the way the engine would deliver it.
  ///
  /// Built through the camera rather than by guessing a screen pixel, so the
  /// test exercises the same conversion the real tap path uses and does not
  /// silently pass on a viewport size it happened to get.
  void tapWorld(ConferenceGame game, Vector2 at) {
    final canvasPoint = game.camera.localToGlobal(at);
    game.onTapDown(
      TapDownEvent(
        1,
        game,
        TapDownDetails(
          globalPosition: Offset(canvasPoint.x, canvasPoint.y),
          kind: PointerDeviceKind.touch,
        ),
      ),
    );
  }

  group('finding the board', () {
    testWidgets('three taps unlock it', (tester) async {
      final (:game, :socket, :persisted) = await pumpGame(tester);

      tapWorld(game, _atBoard);
      expect(game.hasBoard, isFalse);
      tapWorld(game, _atBoard);
      expect(game.hasBoard, isFalse);
      tapWorld(game, _atBoard);

      expect(game.hasBoard, isTrue);
      expect(
        game.hud.toast.value?.message,
        equals(ConferenceGame.unlockedText),
      );
      // Exactly one write, on the tap that flipped it — not one per tap.
      expect(persisted, equals([true]));
    });

    testWidgets('two taps and a pause do not', (tester) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);

      tapWorld(game, _atBoard);
      tapWorld(game, _atBoard);
      await tick(tester, frames: 180);
      tapWorld(game, _atBoard);

      expect(game.hasBoard, isFalse);
    });

    testWidgets('a fourth tap puts it back, and says so', (tester) async {
      final (:game, :socket, :persisted) = await pumpGame(tester);

      for (var i = 0; i < 4; i++) {
        tapWorld(game, _atBoard);
      }

      expect(game.hasBoard, isFalse);
      expect(game.hud.toast.value?.message, equals(ConferenceGame.stowedText));
      expect(persisted, equals([true, false]));
    });

    testWidgets('the hint bean says there is one, not where', (tester) async {
      final (:game, :socket, :persisted) = await pumpGame(tester);

      tapWorld(game, _atHint);

      final said = game.hud.toast.value!.message;
      expect(said, equals(ConferenceGame.hintText));
      expect(said.toLowerCase(), contains('board'));
      // A secret is worth passing on; an instruction is not.
      expect(said.toLowerCase(), isNot(contains('east')));
      expect(game.hasBoard, isFalse);
      expect(persisted, isEmpty);
    });

    testWidgets('tapping the hint bean three times never arms it', (
      tester,
    ) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);

      for (var i = 0; i < 3; i++) {
        tapWorld(game, _atHint);
      }

      expect(game.hasBoard, isFalse);
    });

    testWidgets('a tap that misses everything does nothing', (tester) async {
      final (:game, :socket, :persisted) = await pumpGame(tester);

      for (var i = 0; i < 3; i++) {
        tapWorld(game, _sea);
      }

      expect(game.hasBoard, isFalse);
      expect(game.hud.toast.value, isNull);
      expect(persisted, isEmpty);
    });

    testWidgets('the conference has nothing to tap', (tester) async {
      final (:game, :socket, :persisted) = await pumpGame(
        tester,
        map: ConferenceMap.empty,
      );

      for (var i = 0; i < 3; i++) {
        tapWorld(game, _atBoard);
      }

      expect(game.hasBoard, isFalse);
      expect(game.hud.toast.value, isNull);
    });

    testWidgets('a second toast replaces the first', (tester) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);

      tapWorld(game, _atHint);
      final first = game.hud.toast.value!;
      tapWorld(game, _atHint);

      expect(game.hud.toast.value, isNot(equals(first)));
      // Two identical messages are still two toasts, or the second tap looks
      // like it did nothing.
      expect(game.hud.toast.value!.message, equals(first.message));
    });
  });

  group('surfing', () {
    testWidgets('the sea is faster on a board than off one', (tester) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);
      game.bean.position.setFrom(_sea);
      await tick(tester, frames: 2);

      final swimming = game.layout.speedFactorAt(_sea.x, _sea.y);
      for (var i = 0; i < 3; i++) {
        tapWorld(game, _atBoard);
      }
      await tick(tester, frames: 40);

      expect(swimming, equals(0.55));
      expect(game.bean.swim.isSurfing, isTrue);
      expect(game.localSpeedFactor, equals(0.9));
    });

    testWidgets('the sea without a board is still 0.55', (tester) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);
      game.bean.position.setFrom(_sea);
      await tick(tester, frames: 4);

      expect(game.localSpeedFactor, equals(0.55));
    });

    testWidgets('land is full pace either way', (tester) async {
      final (:game, :socket, persisted: _) = await pumpGame(
        tester,
        hasBoard: true,
      );
      game.bean.position.setFrom(_sand);
      await tick(tester, frames: 30);

      expect(game.localSpeedFactor, equals(1));
      expect(game.bean.swim.isSurfing, isFalse);
    });

    testWidgets('a board carried into the pool is just a swim', (tester) async {
      final (:game, :socket, persisted: _) = await pumpGame(
        tester,
        map: ConferenceMap.empty,
        hasBoard: true,
      );
      game.bean.position.setValues(
        WorldLayout.pool.centerX,
        WorldLayout.pool.centerY,
      );
      await tick(tester, frames: 40);

      expect(game.bean.hasBoard, isTrue);
      expect(game.bean.swim.isSurfing, isFalse);
      expect(game.bean.swim.sinkFraction, greaterThan(0.3));
      // 0.55, not 0.9: the pool is for swimming.
      expect(game.localSpeedFactor, equals(WorldLayout.swimSpeedFactor));
    });
  });

  group('telling everybody', () {
    testWidgets('a toggle sends exactly one message', (tester) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);

      for (var i = 0; i < 3; i++) {
        tapWorld(game, _atBoard);
      }

      expect(
        socket.sentMessages.whereType<BoardMessage>().toList(),
        equals([const BoardMessage(hasBoard: true)]),
      );
    });

    testWidgets('a welcome re-announces an unlocked board', (tester) async {
      final (:game, :socket, persisted: _) = await pumpGame(
        tester,
        hasBoard: true,
      );

      socket.emit(const WelcomeMessage(yourId: 'p7'));
      await tick(tester, frames: 2);

      expect(
        socket.sentMessages.whereType<BoardMessage>().single.hasBoard,
        isTrue,
      );
    });

    testWidgets('a welcome says nothing when there is no board', (
      tester,
    ) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);

      socket.emit(const WelcomeMessage(yourId: 'p7'));
      await tick(tester, frames: 2);

      expect(socket.sentMessages.whereType<BoardMessage>(), isEmpty);
    });

    testWidgets('a reconnect re-announces it again', (tester) async {
      final (:game, :socket, persisted: _) = await pumpGame(
        tester,
        hasBoard: true,
      );

      socket
        ..emit(const WelcomeMessage(yourId: 'p7'))
        ..emit(const WelcomeMessage(yourId: 'p7'));
      await tick(tester, frames: 2);

      expect(socket.sentMessages.whereType<BoardMessage>(), hasLength(2));
    });
  });

  group("everybody else's board", () {
    testWidgets('appeared carries it, and the bean is drawn on one', (
      tester,
    ) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);

      socket
        ..emit(const WelcomeMessage(yourId: 'p7'))
        ..emit(
          SnapshotMessage(appeared: [_player('p1', _sea, hasBoard: true)]),
        );
      await tick(tester, frames: 40);

      final bean = game.remotePlayers.beanOf('p1')!;
      expect(bean.hasBoard, isTrue);
      expect(bean.swim.isSurfing, isTrue);
    });

    testWidgets('the same snapshot on the conference draws no board', (
      tester,
    ) async {
      final (:game, :socket, persisted: _) = await pumpGame(
        tester,
        map: ConferenceMap.empty,
      );
      final inPool = Vector2(
        WorldLayout.pool.centerX,
        WorldLayout.pool.centerY,
      );

      socket
        ..emit(const WelcomeMessage(yourId: 'p7'))
        ..emit(
          SnapshotMessage(appeared: [_player('p1', inPool, hasBoard: true)]),
        );
      await tick(tester, frames: 40);

      final bean = game.remotePlayers.beanOf('p1')!;
      expect(bean.hasBoard, isTrue);
      expect(bean.swim.isSurfing, isFalse);
    });

    testWidgets('a playerBoard applies to a bean already in view', (
      tester,
    ) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);

      socket
        ..emit(const WelcomeMessage(yourId: 'p7'))
        ..emit(SnapshotMessage(appeared: [_player('p1', _sea)]));
      await tick(tester, frames: 30);
      expect(game.remotePlayers.beanOf('p1')!.swim.isSurfing, isFalse);

      socket.emit(const PlayerBoardMessage(id: 'p1', hasBoard: true));
      await tick(tester, frames: 4);

      expect(game.remotePlayers.beanOf('p1')!.swim.isSurfing, isTrue);
    });

    testWidgets('a playerBoard for somebody out of view is dropped', (
      tester,
    ) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);

      socket
        ..emit(const WelcomeMessage(yourId: 'p7'))
        ..emit(const PlayerBoardMessage(id: 'ghost', hasBoard: true));
      await tick(tester, frames: 4);

      expect(game.remotePlayers.beanOf('ghost'), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('walking back into range keeps the board', (tester) async {
      final (:game, :socket, persisted: _) = await pumpGame(tester);

      socket
        ..emit(const WelcomeMessage(yourId: 'p7'))
        ..emit(SnapshotMessage(appeared: [_player('p1', _sea, hasBoard: true)]))
        ..emit(const SnapshotMessage(outOfRange: ['p1']))
        // The state travels in `appeared`, so nothing has to re-announce it.
        ..emit(
          SnapshotMessage(appeared: [_player('p1', _sea, hasBoard: true)]),
        );
      await tick(tester, frames: 40);

      expect(game.remotePlayers.beanOf('p1')!.hasBoard, isTrue);
    });
  });
}
