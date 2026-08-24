import 'dart:io';
import 'dart:math';

import 'package:loadtest/loadtest.dart';
import 'package:protocol/protocol.dart';
import 'package:server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  // A handful of bots against a really running relay. The 200-bot run is a
  // manual exercise with a real browser attached; this is the CI-sized
  // version of it, and it is what stops the load tester quietly measuring
  // nothing after a protocol change.
  late HttpServer httpServer;
  late MapRelays hub;
  late Relay relay;
  late Uri url;

  setUp(() async {
    hub = MapRelays(
      log: (_) {},
      tickInterval: const Duration(milliseconds: 20),
    );
    relay = hub.relayFor(MapId.conference);
    hub.start();
    httpServer = await shelf_io.serve(
      buildHandler(relays: hub),
      InternetAddress.loopbackIPv4,
      0,
    );
    url = Uri.parse('ws://127.0.0.1:${httpServer.port}/$webSocketPath');
  });

  tearDown(() async {
    hub.stop();
    await httpServer.close(force: true);
  });

  test('bots connect, join and are counted by the server', () async {
    final swarm = Swarm(url: url, count: 5, random: Random(1));
    addTearDown(swarm.stop);

    await swarm.connect(ramp: Duration.zero);

    expect(swarm.stats.connected, equals(5));
    expect(swarm.stats.failed, isZero);
    // The socket is open before the join it carries has been read, so the
    // server's own count is asserted once it has caught up.
    await _until(() => relay.playerCount == 5);
  });

  test('bots walk and the server relays them to each other', () async {
    final swarm = Swarm(
      url: url,
      count: 6,
      random: Random(1),
      sendInterval: const Duration(milliseconds: 20),
    );
    addTearDown(swarm.stop);
    await swarm.connect(ramp: Duration.zero);

    swarm.start();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(swarm.stats.movesSent, greaterThan(0));
    expect(swarm.stats.received, greaterThan(0));
    expect(swarm.stats.snapshots, greaterThan(0));
    expect(relay.metrics.ticks, greaterThan(0));
  });

  test('a swarm pointed at nothing fails softly', () async {
    // A refused connection is data about the run, not a crash of the tool.
    final swarm = Swarm(
      url: Uri.parse('ws://127.0.0.1:1/ws'),
      count: 2,
      random: Random(1),
    );
    addTearDown(swarm.stop);

    await swarm.connect(ramp: Duration.zero);

    expect(swarm.stats.connected, isZero);
    expect(swarm.stats.failed, equals(2));
  });

  test('the crowded scenario puts every bot near spawn', () async {
    final swarm = Swarm(
      url: url,
      count: 8,
      scenario: LoadScenario.cluster,
      random: Random(1),
    );
    addTearDown(swarm.stop);

    await swarm.connect(ramp: Duration.zero);

    final radius = LoadScenario.cluster.clusterRadius!;
    for (final bot in swarm.bots) {
      final dx = bot.wanderer.x - spawnCenterX;
      final dy = bot.wanderer.y - spawnCenterY;
      expect(sqrt(dx * dx + dy * dy), lessThanOrEqualTo(radius + 1));
    }
  });

  test('churn takes bots out and brings them back', () async {
    // The whole point of the scenario: the player count comes back to where
    // it started, so anything that does not is a leak and not a departure.
    final swarm = Swarm(
      url: url,
      count: 6,
      scenario: LoadScenario.churn,
      random: Random(1),
    );
    addTearDown(swarm.stop);
    await swarm.connect(ramp: Duration.zero);
    await _until(() => relay.playerCount == 6);

    // Four recycles, so both halves of the alternation run twice: two bots
    // re-seat with the session they had, two arrive as new people.
    await swarm.recycle(4);

    expect(swarm.stats.left, equals(4));
    expect(swarm.stats.reseated, equals(2));
    expect(swarm.stats.arrived, equals(2));
    expect(swarm.stats.connected, equals(6));
    expect(swarm.bots, hasLength(6));
    await _until(() => relay.playerCount == 6);
  });

  test('a deliberate disconnect is not counted as a failure', () async {
    final swarm = Swarm(
      url: url,
      count: 4,
      scenario: LoadScenario.churn,
      random: Random(1),
    );
    addTearDown(swarm.stop);
    await swarm.connect(ramp: Duration.zero);

    await swarm.recycle(2);
    // Give the closed sockets time to deliver their onDone.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(swarm.stats.failed, isZero);
    expect(swarm.stats.opened, equals(6));
  });

  group('SwarmStats', () {
    test('averages players per snapshot over snapshots received', () {
      final stats = SwarmStats()
        ..snapshots = 4
        ..playersInSnapshots = 10;

      expect(stats.averagePlayersPerSnapshot, equals(2.5));
    });

    test('reports zero rather than dividing by it', () {
      final stats = SwarmStats();

      expect(stats.averagePlayersPerSnapshot, isZero);
      expect(stats.summary(Duration.zero), contains('connected=0'));
    });

    test('the summary carries the numbers a run is judged on', () {
      final stats = SwarmStats()
        ..connected = 200
        ..movesSent = 2000
        ..received = 3000
        ..receivedBytes = 1024000
        ..snapshots = 3000
        ..playersInSnapshots = 24000;

      final summary = stats.summary(const Duration(seconds: 1));
      expect(summary, contains('connected=200'));
      expect(summary, contains('perSnapshot=8.0'));
      expect(summary, contains('KiB/s/client'));
    });
  });

  group('bot identity', () {
    test('every bot name the swarm can produce is one the server accepts', () {
      // The server rejects a bad name outright now rather than trimming it,
      // so a naming scheme that overruns the 16-character cap would produce
      // a load test where every bot is turned away at the door and the
      // numbers look wonderful.
      for (var index = 0; index < 5000; index++) {
        expect(
          validateName(botName(index)),
          equals(NameValidation.valid),
          reason: botName(index),
        );
      }
    });

    test('each bot carries a session id the server will accept', () {
      final random = Random(1);
      final bots = List.generate(
        50,
        (index) => Bot(
          url: Uri.parse('ws://test/ws'),
          index: index,
          random: random,
        ),
      );

      for (final bot in bots) {
        expect(isValidSessionId(bot.sessionId), isTrue, reason: bot.sessionId);
      }
      // Two bots sharing one session id would be one bot as far as the
      // server is concerned, and the swarm would never reach its target.
      expect(bots.map((bot) => bot.sessionId).toSet(), hasLength(bots.length));
    });
  });
}

/// Polls [condition] until it holds, or the test times out.
Future<void> _until(bool Function() condition) async {
  while (!condition()) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
