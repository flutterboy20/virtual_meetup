import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  // A hand-cranked clock: rates are per-second, and a test that measured real
  // elapsed time would be a flake waiting to happen.
  late DateTime clock;
  late ServerMetrics metrics;

  setUp(() {
    clock = DateTime(2026);
    metrics = ServerMetrics(now: () => clock);
  });

  void advance(Duration by) => clock = clock.add(by);

  void tick({
    Duration duration = const Duration(milliseconds: 1),
    int players = 0,
    int snapshots = 0,
    int playersInSnapshots = 0,
    int busiestCell = 0,
  }) => metrics.recordTick(
    duration: duration,
    players: players,
    snapshots: snapshots,
    playersInSnapshots: playersInSnapshots,
    busiestCell: busiestCell,
  );

  group('a fresh collector', () {
    test('reports zeroes rather than dividing by them', () {
      expect(metrics.ticksPerSecond, isZero);
      expect(metrics.averageTickMillis, isZero);
      expect(metrics.averagePlayersPerSnapshot, isZero);
      expect(metrics.outboundBytesPerClientPerSecond, isZero);
      expect(metrics.summary, contains('players=0'));
    });
  });

  group('rates', () {
    test('are per second of the window, not per event', () {
      for (var i = 0; i < 15; i++) {
        tick(players: 3);
      }
      advance(const Duration(seconds: 1));

      expect(metrics.ticksPerSecond, closeTo(15, 0.001));
    });

    test('count outbound messages and bytes', () {
      metrics
        ..recordOutbound(100)
        ..recordOutbound(300);
      advance(const Duration(seconds: 2));
      tick(players: 2);

      expect(metrics.outboundMessagesPerSecond, closeTo(1, 0.001));
      expect(metrics.outboundBytesPerSecond, closeTo(200, 0.001));
      expect(metrics.outboundBytesPerClientPerSecond, closeTo(100, 0.001));
    });

    test('count inbound messages', () {
      metrics
        ..recordInbound()
        ..recordInbound()
        ..recordInbound();
      advance(const Duration(seconds: 3));

      expect(metrics.inboundMessagesPerSecond, closeTo(1, 0.001));
    });
  });

  group('tick cost', () {
    test('averages the ticks and keeps the worst one', () {
      tick(duration: const Duration(milliseconds: 2));
      tick(duration: const Duration(milliseconds: 8));

      expect(metrics.averageTickMillis, closeTo(5, 0.001));
      // The average would hide it, but one 8ms tick is what a player feels.
      expect(metrics.worstTickMillis, closeTo(8, 0.001));
    });
  });

  group('the culling number', () {
    test('averages over snapshots actually sent', () {
      tick(players: 10, snapshots: 4, playersInSnapshots: 12);

      expect(metrics.averagePlayersPerSnapshot, closeTo(3, 0.001));
      expect(metrics.players, equals(10));
    });

    test('players online can climb while players per snapshot does not', () {
      // The entire scaling claim of the phase, as an assertion: doubling the
      // world does not double what any one client is told about.
      tick(players: 50, snapshots: 50, playersInSnapshots: 400);
      final atFifty = metrics.averagePlayersPerSnapshot;
      metrics.resetWindow();
      tick(players: 200, snapshots: 200, playersInSnapshots: 1600);

      expect(metrics.players, equals(200));
      expect(metrics.averagePlayersPerSnapshot, equals(atFifty));
    });

    test('keeps the worst cell, not the latest one', () {
      tick(busiestCell: 9);
      tick(busiestCell: 2);

      expect(metrics.busiestCell, equals(9));
    });

    test('tracks the peak player count within the window', () {
      tick(players: 7);
      tick(players: 3);

      expect(metrics.players, equals(3));
      expect(metrics.peakPlayers, equals(7));
    });
  });

  group('windows', () {
    test('resetting clears the counters but keeps the player gauge', () {
      tick(players: 5, snapshots: 5, playersInSnapshots: 20, busiestCell: 4);
      metrics
        ..recordOutbound(1000)
        ..recordInbound()
        ..resetWindow();
      advance(const Duration(seconds: 1));

      expect(metrics.players, equals(5));
      expect(metrics.peakPlayers, equals(5));
      expect(metrics.ticks, isZero);
      expect(metrics.busiestCell, isZero);
      expect(metrics.outboundBytesPerSecond, isZero);
      expect(metrics.inboundMessagesPerSecond, isZero);
      expect(metrics.averagePlayersPerSnapshot, isZero);
    });

    test('uptime survives a window reset', () {
      advance(const Duration(minutes: 5));
      metrics.resetWindow();
      advance(const Duration(seconds: 30));

      expect(metrics.uptime, equals(const Duration(minutes: 5, seconds: 30)));
      expect(metrics.window, equals(const Duration(seconds: 30)));
    });
  });

  group('reporting', () {
    test('the summary names the numbers a load run needs', () {
      tick(players: 200, snapshots: 200, playersInSnapshots: 1600);
      metrics.recordOutbound(500);
      advance(const Duration(seconds: 1));

      final summary = metrics.summary;
      expect(summary, contains('players=200'));
      expect(summary, contains('perSnapshot=8.0'));
      expect(summary, contains('msg/s'));
      expect(summary, contains('KiB/s'));
    });

    test('the JSON form carries the same numbers', () {
      tick(players: 4, snapshots: 4, playersInSnapshots: 8);
      advance(const Duration(seconds: 1));

      final json = metrics.toJson();
      expect(json['players'], equals(4));
      expect(json['averagePlayersPerSnapshot'], equals(2.0));
      expect(json['ticksPerSecond'], equals(1.0));
      expect(json['windowSeconds'], equals(1.0));
    });
  });

  group('tick latency profile', () {
    ServerMetrics profiler({Duration? budget, int rss = 0}) => ServerMetrics(
      tickBudget: budget ?? const Duration(milliseconds: 66),
      readResidentBytes: () => rss,
    );

    void ticks(ServerMetrics metrics, int count, Duration each) {
      for (var i = 0; i < count; i++) {
        metrics.recordTick(
          duration: each,
          players: 100,
          snapshots: 100,
          playersInSnapshots: 800,
          busiestCell: 20,
        );
      }
    }

    test('p95 ignores the tail the mean hides', () {
      // Ninety fast ticks and ten slow ones: the mean stays pretty and the
      // p95 tells the truth. One player in ten feeling a 40ms hitch is a
      // server that needs tuning, and the average alone would never say so.
      final metrics = profiler();
      ticks(metrics, 90, const Duration(milliseconds: 2));
      ticks(metrics, 10, const Duration(milliseconds: 40));

      expect(metrics.averageTickMillis, lessThan(6));
      expect(metrics.p95TickMillis, greaterThanOrEqualTo(40));
    });

    test('p95 is not moved by a single outlier the way the max is', () {
      final metrics = profiler();
      ticks(metrics, 99, const Duration(milliseconds: 3));
      ticks(metrics, 1, const Duration(milliseconds: 200));

      expect(metrics.worstTickMillis, equals(200));
      expect(metrics.p95TickMillis, lessThanOrEqualTo(4));
    });

    test('reports zero rather than dividing by no ticks', () {
      expect(profiler().p95TickMillis, isZero);
      expect(profiler().tickOverrunRate, isZero);
    });

    test('counts ticks that ran past the budget', () {
      final metrics = profiler(budget: const Duration(milliseconds: 10));
      ticks(metrics, 8, const Duration(milliseconds: 5));
      ticks(metrics, 2, const Duration(milliseconds: 25));

      expect(metrics.tickOverruns, equals(2));
      expect(metrics.tickOverrunRate, closeTo(0.2, 0.001));
    });

    test('the budget is the tick this relay actually runs at', () {
      // A 30Hz relay's 33ms budget must not be judged against 66ms.
      final metrics = profiler(budget: const Duration(milliseconds: 33));
      ticks(metrics, 1, const Duration(milliseconds: 50));

      expect(metrics.tickOverruns, equals(1));
    });

    test('a tick beyond the histogram still reports the real worst', () {
      final metrics = profiler();
      ticks(metrics, 1, const Duration(milliseconds: 900));

      expect(metrics.p95TickMillis, equals(900));
    });

    test('resetting the window clears the tail and the overruns', () {
      final metrics = profiler(budget: const Duration(milliseconds: 10));
      ticks(metrics, 5, const Duration(milliseconds: 50));

      metrics.resetWindow();

      expect(metrics.tickOverruns, isZero);
      expect(metrics.p95TickMillis, isZero);
    });

    test('memory is reported as a gauge and published in the json', () {
      final metrics = profiler(rss: 42 * 1024 * 1024);

      expect(metrics.residentBytes, equals(42 * 1024 * 1024));
      expect(metrics.toJson()['residentBytes'], equals(42 * 1024 * 1024));
    });

    test('the summary carries the tail, the overruns and the memory', () {
      final metrics = profiler(budget: const Duration(milliseconds: 10));
      ticks(metrics, 4, const Duration(milliseconds: 50));

      expect(metrics.summary, contains('p95='));
      expect(metrics.summary, contains('overrun=4'));
      expect(metrics.summary, contains('rss='));
    });
  });
}
