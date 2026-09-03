import 'dart:math';

import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:server/src/emote_limiter.dart';
import 'package:test/test.dart';

/// A socket that records what the relay sent it.
///
/// The relay is written against [PlayerConnection], not `WebSocketChannel`,
/// which is what lets the whole join/tick/leave protocol be tested here with
/// no HTTP server, no ports and no waiting.
class FakeConnection implements PlayerConnection {
  final List<String> sent = [];
  bool closed = false;

  /// Set to throw on the next send, to stand in for a socket that died.
  bool failOnSend = false;

  /// Everything sent to this client, decoded.
  List<ProtocolMessage> get received =>
      sent.map(decodeMessage).toList(growable: false);

  /// The last message sent to this client.
  ProtocolMessage get last => received.last;

  /// The welcome this client was sent.
  ///
  /// Not `last`: a join is answered with a welcome *and* an opening world
  /// count, so "the last thing sent" is no longer the welcome.
  WelcomeMessage get welcome => received.whereType<WelcomeMessage>().single;

  /// The world-stats messages this client has been sent, in order.
  List<WorldStatsMessage> get stats =>
      received.whereType<WorldStatsMessage>().toList(growable: false);

  /// The emotes relayed to this client, in order.
  List<PlayerEmotedMessage> get emotes =>
      received.whereType<PlayerEmotedMessage>().toList(growable: false);

  /// The board changes relayed to this client, in order.
  List<PlayerBoardMessage> get boards =>
      received.whereType<PlayerBoardMessage>().toList(growable: false);

  /// The snapshots this client has been sent, in order.
  List<SnapshotMessage> get snapshots =>
      received.whereType<SnapshotMessage>().toList(growable: false);

  /// The most recent snapshot.
  SnapshotMessage get lastSnapshot => snapshots.last;

  @override
  void send(String data) {
    if (failOnSend) throw StateError('socket is dead');
    sent.add(data);
  }

  @override
  void close() => closed = true;
}

void main() {
  // The session id on these two is a placeholder: `connect` stamps a fresh
  // one on every socket, because a *repeated* session id is not a second
  // player — it is the same player coming back, which is its own group of
  // tests further down.
  const join = JoinMessage(
    sessionId: '',
    name: 'Alice',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
  );
  const bobJoin = JoinMessage(
    sessionId: '',
    name: 'Bob',
    color: 0xFF7ED9B6,
    cosmetic: PlayerCosmetic.headphones,
  );

  var sessionCounter = 0;
  String nextSessionId() =>
      (++sessionCounter).toRadixString(16).padLeft(sessionIdLength, '0');

  JoinMessage withSession(JoinMessage message, String sessionId) => JoinMessage(
    sessionId: sessionId,
    name: message.name,
    color: message.color,
    cosmetic: message.cosmetic,
  );

  // A 100-unit cell keeps the geography of these tests readable: anything
  // within one cell of you is visible, anything two cells away is not.
  const cellSize = 100.0;

  late List<String> logs;
  late Relay relay;

  setUp(() {
    logs = [];
    relay = Relay(
      registry: PlayerRegistry(random: Random(1), cellSize: cellSize),
      log: logs.add,
    );
  });

  /// Opens a socket and sends [message] on it, returning both halves.
  ///
  /// Each call gets its own session id unless [sessionId] names one, so the
  /// ordinary tests below describe distinct people rather than accidentally
  /// re-seating the same one.
  (FakeConnection, RelaySession) connect([
    JoinMessage? message,
    String? sessionId,
  ]) {
    final connection = FakeConnection();
    final session = relay.open(connection);
    if (message != null) {
      session.handleData(
        encodeMessage(withSession(message, sessionId ?? nextSessionId())),
      );
    }
    return (connection, session);
  }

  /// Walks [session] to ([x], [y]) the way a real client would.
  ///
  /// Spawn points are random, so every test that cares about who can see whom
  /// puts its players somewhere explicit first.
  void walk(RelaySession session, double x, double y) =>
      session.handleData(encodeMessage(MoveMessage(x: x, y: y)));

  group('the door', () {
    test('rejects a join with no session id and closes the socket', () {
      final connection = FakeConnection();
      final session = relay.open(connection)..handleData(encodeMessage(join));

      final rejection = connection.last as JoinRejectedMessage;
      expect(rejection.reason, equals(JoinRejection.invalidSession));
      expect(rejection.detail, isNotEmpty);
      expect(connection.closed, isTrue);
      expect(relay.playerCount, isZero);
      expect(session.playerId, isNull);
    });

    test('rejects a session id that is not shaped like one', () {
      final connection = FakeConnection();
      relay
          .open(connection)
          .handleData(encodeMessage(withSession(join, '../etc/passwd')));

      expect(
        (connection.last as JoinRejectedMessage).reason,
        equals(JoinRejection.invalidSession),
      );
    });

    test('re-validates the name the client already checked', () {
      // The client filter is UX. This one is the rule, and it has to hold
      // against a client that skipped it or was written by somebody else.
      final connection = FakeConnection();
      relay
          .open(connection)
          .handleData(
            encodeMessage(
              JoinMessage(
                sessionId: nextSessionId(),
                name: 'f.u.c.k',
                color: 1,
                cosmetic: PlayerCosmetic.none,
              ),
            ),
          );

      final rejection = connection.last as JoinRejectedMessage;
      expect(rejection.reason, equals(JoinRejection.invalidName));
      expect(rejection.detail, equals(NameValidation.blocked.message));
      expect(connection.closed, isTrue);
      expect(relay.playerCount, isZero);
    });

    test('rejects a name that is too short, with a reason to show', () {
      final connection = FakeConnection();
      relay
          .open(connection)
          .handleData(
            encodeMessage(
              JoinMessage(
                sessionId: nextSessionId(),
                name: 'x',
                color: 1,
                cosmetic: PlayerCosmetic.none,
              ),
            ),
          );

      expect(
        (connection.last as JoinRejectedMessage).detail,
        equals(NameValidation.tooShort.message),
      );
    });

    test('a rejected socket is not seated and sends nothing further', () {
      final connection = FakeConnection();
      final session = relay.open(connection)
        ..handleData(encodeMessage(join))
        ..handleData(encodeMessage(const MoveMessage(x: 10, y: 10)));

      expect(connection.received.whereType<WelcomeMessage>(), isEmpty);
      expect(session.sendSnapshot(), equals(-1));
    });
  });

  group('re-seating a returning session', () {
    test('a second socket on a live session keeps one player', () {
      // The re-seat race: the client is back before the server noticed the
      // first socket died. Two beans for one person is the bug.
      final session = nextSessionId();
      final (first, firstSession) = connect(join, session);
      final firstId = firstSession.playerId;

      final (second, secondSession) = connect(join, session);

      expect(relay.playerCount, equals(1));
      expect(secondSession.playerId, equals(firstId));
      expect(second.welcome.yourId, equals(firstId));
      expect(first.closed, isTrue, reason: 'the stale socket is hung up on');
      expect(firstSession.isDisplaced, isTrue);
    });

    test('the displaced socket is told why before it is closed', () {
      // Without this the close is indistinguishable from a dropped
      // connection, so the losing client backs off, reconnects under the same
      // session id and displaces the winner — which displaces it back. Two
      // browser tabs share their storage, so they share a session id, and the
      // pair of them trade the seat for as long as both stay open. One
      // sentence on the way out is what ends the loop.
      final session = nextSessionId();
      final (first, _) = connect(join, session);
      connect(join, session);

      final rejection = first.received.whereType<JoinRejectedMessage>().single;

      expect(rejection.reason, equals(JoinRejection.displaced));
      expect(rejection.detail, isNotEmpty);
      expect(first.closed, isTrue);
    });

    test('only the displaced socket hears about it', () {
      // The socket that took the seat did nothing wrong and must not be told
      // it lost one.
      final session = nextSessionId();
      connect(join, session);
      final (second, _) = connect(join, session);

      expect(second.received.whereType<JoinRejectedMessage>(), isEmpty);
    });

    test('a socket that dies for its own reasons is told nothing', () {
      // The rejection is a statement about *this* seat being taken by
      // somebody else. A tab closing has no such news to carry.
      final (connection, session) = connect(join, nextSessionId());

      session.close();

      expect(connection.received.whereType<JoinRejectedMessage>(), isEmpty);
    });

    test('the displaced socket closing does not evict the new one', () {
      // This is the whole point of the guard: the dying socket's `onDone`
      // arrives *after* the reconnect, and must not take the seat with it.
      final session = nextSessionId();
      final (_, firstSession) = connect(join, session);
      final (_, secondSession) = connect(join, session);

      firstSession.close();

      expect(relay.playerCount, equals(1));
      expect(relay.registry[secondSession.playerId!], isNotNull);
    });

    test('a re-seat keeps the bean where it was standing', () {
      final session = nextSessionId();
      final (_, firstSession) = connect(join, session);
      walk(firstSession, 300, 400);

      final (_, secondSession) = connect(join, session);
      final player = relay.registry[secondSession.playerId!]!;

      expect(player.x, equals(300));
      expect(player.y, equals(400));
    });

    test('a session that dropped cleanly resumes the same seat', () {
      final session = nextSessionId();
      final (_, firstSession) = connect(join, session);
      final firstId = firstSession.playerId;
      walk(firstSession, 300, 400);
      firstSession.close();

      expect(relay.playerCount, isZero);

      final (_, secondSession) = connect(join, session);

      expect(secondSession.playerId, equals(firstId));
      expect(relay.registry[firstId!]!.x, equals(300));
      expect(logs.last, contains('resumed'));
    });

    test('a returning client is told about its neighbours again', () {
      // The new socket knows nothing, so everything in range has to be
      // re-announced to it — not just the changes since it left.
      final session = nextSessionId();
      final (_, aliceSession) = connect(join, session);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 300, 300);
      walk(bobSession, 310, 300);
      relay.tick();

      final (alice, _) = connect(join, session);
      relay.tick();

      expect(alice.lastSnapshot.appeared.single.name, equals('Bob'));
    });

    test('a renamed player is re-announced to everybody who can see them', () {
      // Metadata travels once, on appearance. Somebody who reconnects under
      // a new name would otherwise keep the old one on every screen but
      // their own.
      final session = nextSessionId();
      final (_, aliceSession) = connect(join, session);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 300, 300);
      walk(bobSession, 310, 300);
      relay.tick();
      expect(bob.lastSnapshot.appeared.single.name, equals('Alice'));

      connect(join, session);
      relay.tick();

      expect(bob.lastSnapshot.appeared, isEmpty, reason: 'same name, no news');

      relay
          .open(FakeConnection())
          .handleData(
            encodeMessage(
              JoinMessage(
                sessionId: session,
                name: 'Ada',
                color: 0xFF54C5F8,
                cosmetic: PlayerCosmetic.cap,
              ),
            ),
          );
      relay.tick();

      expect(bob.lastSnapshot.appeared.single.name, equals('Ada'));
    });
  });

  group('join', () {
    test('welcomes the joiner with nothing but an id', () {
      final (alice, session) = connect(join);

      final welcome = alice.welcome;
      expect(welcome.yourId, equals(session.playerId));
      // Not "and here is everybody in the world": at 300 attendees that is
      // exactly the payload interest management exists to prevent.
      expect(welcome.toJson().keys, equals(['type', 'version', 'yourId']));
    });

    test('says nothing to anybody until the next tick', () {
      final (alice, _) = connect(join);
      final before = alice.sent.length;

      connect(bobJoin);

      expect(alice.sent, hasLength(before));
    });

    test('logs the arrival and the live player count', () {
      connect(join);

      expect(logs.last, contains('fresh'));
      expect(logs.last, contains('1 players'));
    });

    test('ignores a second join on the same socket', () {
      final (alice, session) = connect(join);
      final firstId = session.playerId;

      session.handleData(encodeMessage(bobJoin));

      expect(session.playerId, equals(firstId));
      expect(relay.playerCount, equals(1));
      expect(alice.received.whereType<WelcomeMessage>(), hasLength(1));
      expect(logs.last, contains('second join'));
    });
  });

  group('snapshots', () {
    test('a nearby player arrives with full metadata, once', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 160);

      relay.tick();

      final first = alice.lastSnapshot;
      expect(first.appeared.single.id, equals(bobSession.playerId));
      expect(first.appeared.single.name, equals('Bob'));
      expect(first.appeared.single.cosmetic, PlayerCosmetic.headphones);
      expect(first.positions.single.id, equals(bobSession.playerId));

      relay.tick();

      // Second tick: still there, but his name and colour are not re-sent.
      expect(alice.lastSnapshot.appeared, isEmpty);
      expect(alice.lastSnapshot.positions, hasLength(1));
    });

    test('a snapshot never contains the player it is sent to', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 160);

      relay.tick();

      expect(
        alice.lastSnapshot.positions.map((position) => position.id),
        isNot(contains(aliceSession.playerId)),
      );
    });

    test('a player alone in the world is sent nothing at all', () {
      final (alice, aliceSession) = connect(join);
      walk(aliceSession, 150, 150);
      final before = alice.sent.length;

      relay
        ..tick()
        ..tick();

      // Fifteen empty messages a second to somebody standing in a corner is
      // pure waste, and it would flatter the culling metric too.
      expect(alice.sent, hasLength(before));
    });

    test('a distant player is culled', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 1000, 1000);
      final before = alice.sent.length;

      relay.tick();

      expect(alice.sent, hasLength(before));
    });

    test('moves are coalesced: four inbound become one outbound', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 150, 150);
      relay.tick();
      final before = alice.sent.length;

      walk(bobSession, 151, 150);
      walk(bobSession, 152, 150);
      walk(bobSession, 153, 150);
      walk(bobSession, 154, 150);
      relay.tick();

      expect(alice.sent, hasLength(before + 1));
      expect(alice.lastSnapshot.positions.single.x, equals(154));
    });

    test('positions go on the wire as whole world units', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160.123456789, 170.987654321);

      relay.tick();

      // Sub-unit precision is invisible — a bean is 26 units wide and the
      // client interpolates anyway — and it was half the bandwidth bill.
      expect(alice.lastSnapshot.positions.single.x, equals(160));
      expect(alice.lastSnapshot.positions.single.y, equals(171));
      expect(alice.sent.last, contains('"x":160,"y":171'));
    });

    test('a position outside the world is clamped, not dropped', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, worldWidth, worldHeight);
      walk(bobSession, 9999, 9999);

      relay.tick();

      final position = alice.lastSnapshot.positions.single;
      expect(position.x, equals(clampWorldX(9999)));
      expect(position.y, equals(clampWorldY(9999)));
    });

    test('drops a move from a socket that never joined, and says nothing', () {
      final (_, stranger) = connect();

      walk(stranger, 1, 2);

      expect(relay.playerCount, isZero);
      // Silently. A well-formed move on an unseated socket can arrive as fast
      // as the inbound budget allows, and one log line each is a flood aimed
      // at the disk. The join deadline is what deals with these sockets.
      expect(logs, everyElement(isNot(contains('never joined'))));
    });
  });

  group('the boundary problem', () {
    test('two players either side of a cell edge see each other', () {
      final (alice, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      // Two units apart, but in different cells. A single-cell interest
      // query would make them invisible to one another.
      walk(aliceSession, 199, 150);
      walk(bobSession, 201, 150);

      relay.tick();

      expect(
        alice.lastSnapshot.positions.single.id,
        equals(bobSession.playerId),
      );
      expect(
        bob.lastSnapshot.positions.single.id,
        equals(aliceSession.playerId),
      );
    });

    test('interest is symmetric', () {
      final (alice, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 99, 99);
      walk(bobSession, 100, 100);

      relay.tick();

      expect(alice.snapshots, isNotEmpty);
      expect(bob.snapshots, isNotEmpty);
    });
  });

  group('walking out of range', () {
    test('a player who walks away is reported out of range, once', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 150, 150);
      relay.tick();

      walk(bobSession, 1000, 1000);
      relay.tick();

      expect(alice.lastSnapshot.outOfRange, equals([bobSession.playerId]));
      expect(alice.lastSnapshot.positions, isEmpty);

      final before = alice.sent.length;
      relay.tick();

      // He is gone; there is nothing left to say about him.
      expect(alice.sent, hasLength(before));
    });

    test('a player who walks back is re-announced with metadata', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 150, 150);
      relay.tick();
      walk(bobSession, 1000, 1000);
      relay.tick();

      walk(bobSession, 155, 155);
      relay.tick();

      expect(alice.lastSnapshot.appeared.single.name, equals('Bob'));
    });

    test('leaving range is not the same message as leaving the world', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 150, 150);
      relay.tick();

      walk(bobSession, 1000, 1000);
      relay.tick();

      expect(alice.received.whereType<PlayerLeftMessage>(), isEmpty);
      expect(alice.lastSnapshot.outOfRange, hasLength(1));
    });
  });

  group('leaving the world', () {
    test('everybody who can see them is told immediately', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 150, 150);
      relay.tick();

      bobSession.close();

      expect(relay.playerCount, equals(1));
      expect(
        (alice.last as PlayerLeftMessage).id,
        equals(bobSession.playerId),
      );
    });

    test('somebody far away is not told at all', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 1000, 1000);
      relay.tick();
      final before = alice.sent.length;

      bobSession.close();

      expect(alice.sent, hasLength(before));
    });

    test('a departure is not also reported as out of range', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 150, 150);
      relay.tick();
      bobSession.close();
      final before = alice.sent.length;

      relay.tick();

      // Saying it twice would be harmless on the client but means the server
      // is still carrying a player it has already forgotten.
      expect(alice.sent, hasLength(before));
      expect(aliceSession.known, isEmpty);
    });

    test('logs the departure and the live player count', () {
      final (_, aliceSession) = connect(join);

      aliceSession.close();

      expect(logs.last, contains('left'));
      expect(logs.last, contains('0 players'));
    });

    test('a socket that closes before joining leaves nothing behind', () {
      final (_, session) = connect();

      session.close();

      expect(relay.playerCount, isZero);
      expect(logs.last, contains('before joining'));
    });

    test('closing twice is harmless', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 150, 150);
      relay.tick();

      bobSession
        ..close()
        ..close();

      expect(alice.received.whereType<PlayerLeftMessage>(), hasLength(1));
      expect(relay.playerCount, equals(1));
    });

    test('a closed session is skipped by the tick', () {
      final (alice, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 150, 150);
      aliceSession.close();
      final before = alice.sent.length;

      relay.tick();

      expect(alice.sent, hasLength(before));
    });

    test('ignores data that arrives after the close', () {
      final (_, aliceSession) = connect(join);
      aliceSession.close();

      walk(aliceSession, 1, 2);

      expect(relay.playerCount, isZero);
    });
  });

  group('metrics', () {
    test('a tick records what it cost and what it sent', () {
      // Its own clock, because the rate metrics divide by elapsed wall time
      // and `DateTime.now()` on Windows can report a zero-length window for
      // a test this fast — which reads as "sent nothing" rather than
      // "measured nothing".
      var now = DateTime(2026);
      relay = Relay(
        registry: PlayerRegistry(random: Random(1), cellSize: cellSize),
        metrics: ServerMetrics(now: () => now),
        log: logs.add,
      );
      final (_, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 150, 150);

      relay.tick();
      now = now.add(const Duration(seconds: 1));

      expect(relay.metrics.players, equals(2));
      expect(relay.metrics.ticks, equals(1));
      expect(relay.metrics.averagePlayersPerSnapshot, equals(1));
      expect(relay.metrics.busiestCell, equals(2));
      expect(relay.metrics.outboundMessagesPerSecond, greaterThan(0));
    });

    test('culling shows up as players-per-snapshot far below players', () {
      // Nine players on a grid four cells apart, so nobody is anybody's
      // neighbour. Everyone online, nobody visible: the culling claim, made
      // as an assertion instead of a hope.
      for (var i = 0; i < 9; i++) {
        final (_, session) = connect(join);
        walk(
          session,
          200 + (i % 3) * 4 * cellSize,
          200 + (i ~/ 3) * 4 * cellSize,
        );
      }

      relay.tick();

      expect(relay.metrics.players, equals(9));
      expect(relay.metrics.averagePlayersPerSnapshot, isZero);
    });

    test('an empty tick still counts as a tick', () {
      relay.tick();

      expect(relay.metrics.ticks, equals(1));
      expect(relay.metrics.players, isZero);
    });
  });

  group('the tick loop', () {
    test('starts and stops', () {
      expect(relay.isRunning, isFalse);

      relay.start();
      expect(relay.isRunning, isTrue);

      relay.start();
      expect(relay.isRunning, isTrue);

      relay.stop();
      expect(relay.isRunning, isFalse);
    });

    test('really fires on its own', () async {
      final fast = Relay(
        registry: PlayerRegistry(random: Random(1), cellSize: cellSize),
        log: logs.add,
        tickInterval: const Duration(milliseconds: 5),
      )..start();
      addTearDown(fast.stop);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fast.metrics.ticks, greaterThan(3));
    });
  });

  group('hostile and buggy clients', () {
    test('malformed text is dropped, not fatal', () {
      final (alice, aliceSession) = connect(join);
      connect(bobJoin);

      for (final bad in ['', 'not json', '{"type":"move","x":"far"}', '[]']) {
        expect(() => aliceSession.handleData(bad), returnsNormally);
      }

      expect(alice.received.whereType<UnknownMessage>(), isEmpty);
      expect(relay.playerCount, equals(2));
    });

    test('an unknown message type is dropped', () {
      final (_, aliceSession) = connect(join);

      aliceSession.handleData('{"type":"emote","version":2,"emoji":"wave"}');

      expect(logs.last, contains('unreadable'));
      expect(relay.playerCount, equals(1));
    });

    test('a binary frame is dropped', () {
      final (_, aliceSession) = connect(join);

      expect(() => aliceSession.handleData([1, 2, 3]), returnsNormally);
      expect(logs.last, contains('non-text frame'));
    });

    test('a server-to-client message from a client is dropped', () {
      final (_, aliceSession) = connect(join);

      aliceSession.handleData(
        encodeMessage(const SnapshotMessage(outOfRange: ['p2'])),
      );

      expect(relay.playerCount, equals(1));
      expect(logs.last, contains('server-only'));
    });

    test('a client cannot move somebody else', () {
      final (_, aliceSession) = connect(join);
      final (_, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 800, 800);

      // Alice sends a move naming Bob; the relay ignores the id on the wire
      // and uses the one it assigned to her socket.
      aliceSession.handleData(
        '{"type":"move","version":2,"x":500,"y":600,'
        '"id":"${bobSession.playerId}"}',
      );

      expect(relay.registry[aliceSession.playerId!]!.x, equals(500));
      expect(relay.registry[bobSession.playerId!]!.x, equals(800));
    });

    test('one dead socket does not stop the tick for the others', () {
      final (alice, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      final (carol, carolSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 150, 150);
      walk(carolSession, 150, 150);
      bob.failOnSend = true;
      final aliceBefore = alice.sent.length;
      final carolBefore = carol.sent.length;

      relay.tick();

      expect(alice.sent.length, greaterThan(aliceBefore));
      expect(carol.sent.length, greaterThan(carolBefore));
      expect(logs.last, contains('failed'));
    });
  });

  group('emotes', () {
    test('reach a neighbour but never the sender', () {
      final (alice, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);

      aliceSession.handleData(
        encodeMessage(const EmoteMessage(emote: EmoteKind.clap)),
      );

      expect(bob.emotes.single.emote, equals(EmoteKind.clap));
      // The sender's own client drew it the instant they tapped; echoing it
      // back would put a round trip between a tap and a reaction.
      expect(alice.emotes, isEmpty);
    });

    test('carry the id the server assigned, not one the client chose', () {
      final (_, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);

      aliceSession.handleData(
        encodeMessage(const EmoteMessage(emote: EmoteKind.wave)),
      );

      expect(bob.emotes.single.id, equals(aliceSession.playerId));
    });

    test('are culled exactly like everything else', () {
      final (_, aliceSession) = connect(join);
      final (far, farSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      // Two cells away: outside the 3x3 interest block.
      walk(farSession, 550, 550);

      aliceSession.handleData(
        encodeMessage(const EmoteMessage(emote: EmoteKind.fire)),
      );

      expect(far.emotes, isEmpty);
    });

    test('are rate-limited per player, server-side', () {
      final (_, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);

      for (var i = 0; i < 30; i++) {
        aliceSession.handleData(
          encodeMessage(const EmoteMessage(emote: EmoteKind.party)),
        );
      }

      // The client throttles itself too, but that throttle is advice. This
      // one is the rule, and it is what stops one tap-happy person making
      // the atrium unreadable for everybody in it.
      expect(bob.emotes, hasLength(EmoteLimiter.defaultBurst));
    });

    test("a spammer does not use up anybody else's allowance", () {
      final (_, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      final (carol, carolSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);
      walk(carolSession, 170, 150);

      for (var i = 0; i < 30; i++) {
        aliceSession.handleData(
          encodeMessage(const EmoteMessage(emote: EmoteKind.party)),
        );
      }
      bobSession.handleData(
        encodeMessage(const EmoteMessage(emote: EmoteKind.heart)),
      );

      expect(carol.emotes.last.emote, equals(EmoteKind.heart));
      expect(bob.emotes, hasLength(EmoteLimiter.defaultBurst));
    });

    test('are dropped from a socket that never joined, and say nothing', () {
      final connection = FakeConnection();
      relay
          .open(connection)
          .handleData(
            encodeMessage(const EmoteMessage(emote: EmoteKind.wave)),
          );

      expect(connection.emotes, isEmpty);
      expect(relay.playerCount, isZero);
      // Silently, for the same reason as the pre-join move.
      expect(logs, everyElement(isNot(contains('never joined'))));
    });

    test('are never replayed to somebody who arrives afterwards', () {
      final (_, aliceSession) = connect(join);
      walk(aliceSession, 150, 150);
      aliceSession.handleData(
        encodeMessage(const EmoteMessage(emote: EmoteKind.laugh)),
      );

      final (late_, lateSession) = connect(bobJoin);
      walk(lateSession, 160, 150);
      relay.tick();

      // Ephemeral means ephemeral: a reaction is a moment, not state.
      expect(late_.emotes, isEmpty);
    });

    test('an unreadable reaction is dropped, not guessed at', () {
      final (_, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);

      aliceSession.handleData('{"type":"emote","version":1,"emote":"shrug"}');

      expect(bob.emotes, isEmpty);
      expect(logs.last, contains('unreadable'));
    });
  });

  group('boards', () {
    /// The board announcement a real client sends.
    String board({required bool hasBoard}) =>
        encodeMessage(BoardMessage(hasBoard: hasBoard));

    test('reach a neighbour but never the sender', () {
      final (alice, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);

      aliceSession.handleData(board(hasBoard: true));

      expect(bob.boards.single.hasBoard, isTrue);
      expect(alice.boards, isEmpty);
    });

    test('carry the id the server assigned, not one the client chose', () {
      final (_, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);

      // The inbound message has no id field at all, so there is nothing to
      // spoof — this test is here to keep it that way.
      aliceSession.handleData(
        '{"type":"board","version":4,"hasBoard":true,"id":"p999"}',
      );

      expect(bob.boards.single.id, equals(aliceSession.playerId));
    });

    test('are culled exactly like everything else', () {
      final (_, aliceSession) = connect(join);
      final (far, farSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(farSession, 550, 550);

      aliceSession.handleData(board(hasBoard: true));

      expect(far.boards, isEmpty);
    });

    test('are dropped from a socket that never joined, and say nothing', () {
      final connection = FakeConnection();
      relay.open(connection).handleData(board(hasBoard: true));

      expect(connection.boards, isEmpty);
      // Silently, for the same reason as the pre-join move.
      expect(logs, everyElement(isNot(contains('never joined'))));
    });

    test('a flood is cut off by its own, tighter limiter', () {
      final (_, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);

      for (var i = 0; i < 30; i++) {
        aliceSession.handleData(board(hasBoard: i.isEven));
      }

      expect(bob.boards, hasLength(Relay.defaultBoardBurst));
      // Stricter than emotes on purpose: applause is a burst, a board is not.
      expect(
        Relay.defaultBoardBurst,
        lessThan(EmoteLimiter.defaultBurst),
      );
    });

    test('spending the board bucket leaves the emote bucket alone', () {
      final (_, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);

      for (var i = 0; i < 30; i++) {
        aliceSession.handleData(board(hasBoard: i.isEven));
      }
      aliceSession.handleData(
        encodeMessage(const EmoteMessage(emote: EmoteKind.wave)),
      );

      expect(bob.emotes.single.emote, equals(EmoteKind.wave));
    });

    test('the state rides in a later appearance, not in a replay', () {
      final (_, aliceSession) = connect(join);
      walk(aliceSession, 150, 150);
      aliceSession.handleData(board(hasBoard: true));

      // Bob was nowhere near when it happened, and walks into range now.
      final (bob, bobSession) = connect(bobJoin);
      walk(bobSession, 160, 150);
      relay.tick();

      // No `playerBoard` — the flag came with the metadata instead, which is
      // the whole reason it is a field on `PlayerState` and not an event.
      expect(bob.boards, isEmpty);
      expect(bob.lastSnapshot.appeared.single.hasBoard, isTrue);
    });

    test('putting the board down travels the same way', () {
      final (_, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);

      aliceSession
        ..handleData(board(hasBoard: true))
        ..handleData(board(hasBoard: false));

      expect(
        bob.boards.map((message) => message.hasBoard),
        equals([true, false]),
      );
    });

    test('a v3 client on this server simply never has a board', () {
      final (_, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 150, 150);
      walk(bobSession, 160, 150);
      relay.tick();

      // Nobody sent a board, so nobody has one and nothing extra was sent.
      expect(bob.lastSnapshot.appeared.single.hasBoard, isFalse);
      expect(bob.boards, isEmpty);
    });
  });

  group('world stats', () {
    test('the joiner is told the head count immediately', () {
      final (alice, _) = connect(join);

      // Not at the next stats tick: a counter reading zero for the first
      // second of a session says the event is empty.
      expect(alice.stats.single.online, equals(1));
    });

    test('a broadcast tells everybody the same total', () {
      final (alice, _) = connect(join);
      final (bob, _) = connect(bobJoin);

      relay.broadcastStats();

      expect(alice.stats.last.online, equals(2));
      expect(bob.stats.last.online, equals(2));
    });

    test('is the one thing that is not culled', () {
      final (alice, aliceSession) = connect(join);
      final (bob, bobSession) = connect(bobJoin);
      walk(aliceSession, 100, 100);
      // Far enough apart that neither shows up in the other's snapshot.
      walk(bobSession, 900, 900);
      relay
        ..tick()
        ..broadcastStats();

      expect(alice.snapshots, isEmpty);
      expect(alice.stats.last.online, equals(2));
      expect(bob.stats.last.online, equals(2));
    });

    test('says nothing when nobody is connected', () {
      relay.broadcastStats();

      expect(relay.playerCount, isZero);
    });
  });

  group('the neighbour cap', () {
    /// Seats [count] players all standing on one spot, plus a watcher.
    (FakeConnection, RelaySession) crowd(int count, {double at = 150}) {
      final (watcher, watcherSession) = connect(join);
      walk(watcherSession, at, at);
      for (var i = 0; i < count; i++) {
        final (_, session) = connect(bobJoin);
        // Fanned out by a few units each, so "nearest" is a real ordering
        // and not a tie.
        walk(session, at + 1 + i * 0.5, at);
      }
      return (watcher, watcherSession);
    }

    test('a normal-sized crowd is sent whole', () {
      // The cap is a ceiling, not a quota: the ordinary case pays nothing,
      // not even the sort.
      final (watcher, _) = crowd(5);

      relay.tick();

      expect(watcher.lastSnapshot.positions, hasLength(5));
    });

    test('a packed room is trimmed to the nearest N', () {
      // The load test finding this exists for: the atrium is 400 units
      // across and a 3x3 interest block is 960, so when everybody piles into
      // the middle the grid culls nothing at all.
      relay = Relay(
        registry: PlayerRegistry(random: Random(1), cellSize: 1000),
        log: logs.add,
        neighbourCap: 8,
      );
      final (watcher, _) = crowd(30);

      relay.tick();

      expect(watcher.lastSnapshot.positions, hasLength(8));
    });

    test('the ones it keeps are the nearest ones', () {
      relay = Relay(
        registry: PlayerRegistry(random: Random(1), cellSize: 1000),
        log: logs.add,
        neighbourCap: 4,
      );
      final (watcher, watcherSession) = connect(join);
      walk(watcherSession, 100, 100);
      final sessions = <RelaySession>[];
      for (var i = 0; i < 10; i++) {
        final (_, session) = connect(bobJoin);
        walk(session, 100 + (i + 1) * 20, 100);
        sessions.add(session);
      }

      relay.tick();

      final kept = watcher.lastSnapshot.positions
          .map((position) => position.id)
          .toSet();
      expect(
        kept,
        equals(sessions.take(4).map((session) => session.playerId).toSet()),
      );
    });

    test('somebody trimmed away is reported as out of range', () {
      // The client has to be told, or the bean stands there forever.
      relay = Relay(
        registry: PlayerRegistry(random: Random(1), cellSize: 1000),
        log: logs.add,
        neighbourCap: 2,
      );
      final (watcher, watcherSession) = connect(join);
      walk(watcherSession, 100, 100);
      final (_, near1) = connect(bobJoin);
      final (_, near2) = connect(bobJoin);
      walk(near1, 110, 100);
      walk(near2, 120, 100);
      relay.tick();
      expect(watcher.lastSnapshot.positions, hasLength(2));

      // A third person shoves in closer than one of the incumbents, by more
      // than the incumbency discount.
      final (_, closest) = connect(bobJoin);
      walk(closest, 101, 100);
      relay.tick();

      expect(watcher.lastSnapshot.positions, hasLength(2));
      expect(watcher.lastSnapshot.outOfRange, hasLength(1));
    });

    test('an incumbent is not swapped out over a rounding error', () {
      // Without the discount, two people at almost identical distances trade
      // places every tick, and each trade re-sends a whole player state.
      relay = Relay(
        registry: PlayerRegistry(random: Random(1), cellSize: 1000),
        log: logs.add,
        neighbourCap: 1,
      );
      final (watcher, watcherSession) = connect(join);
      walk(watcherSession, 100, 100);
      final (_, incumbent) = connect(bobJoin);
      walk(incumbent, 200, 100);
      relay.tick();
      final held = watcher.lastSnapshot.positions.single.id;

      // Marginally closer, but not 25% closer.
      final (_, challenger) = connect(bobJoin);
      walk(challenger, 195, 100);
      relay.tick();

      expect(watcher.lastSnapshot.positions.single.id, equals(held));
    });
  });

  group('profiling', () {
    test('overruns are judged against this relay’s own tick', () {
      // A 10Hz relay has a 100ms budget. Judging it against the default 66ms
      // would report a healthy server as permanently overrunning, which is
      // exactly the wrong answer to get while sweeping the tick rate.
      final relay = Relay(
        log: (_) {},
        tickInterval: const Duration(milliseconds: 100),
      );

      relay.metrics.recordTick(
        duration: const Duration(milliseconds: 80),
        players: 1,
        snapshots: 1,
        playersInSnapshots: 0,
        busiestCell: 1,
      );

      expect(relay.metrics.tickOverruns, isZero);
    });

    test('records nothing when no CSV was configured', () {
      final relay = Relay(log: (_) {});

      expect(relay.recorder.isRecording, isFalse);
    });
  });
}
