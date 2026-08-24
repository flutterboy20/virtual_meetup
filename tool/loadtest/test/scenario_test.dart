import 'package:loadtest/loadtest.dart';
import 'package:test/test.dart';

void main() {
  group('LoadScenario', () {
    test('parses its own names, case-insensitively', () {
      expect(LoadScenario.parse('spread'), equals(LoadScenario.spread));
      expect(LoadScenario.parse(' Cluster '), equals(LoadScenario.cluster));
      expect(LoadScenario.parse('CHURN'), equals(LoadScenario.churn));
    });

    test('refuses a name it does not have', () {
      expect(LoadScenario.parse('stampede'), isNull);
      expect(LoadScenario.parse(''), isNull);
    });

    test('only the crowded scenario clusters', () {
      expect(LoadScenario.spread.clusterRadius, isNull);
      expect(LoadScenario.churn.clusterRadius, isNull);
      expect(LoadScenario.cluster.clusterRadius, isNotNull);
    });

    test('only the churn scenario recycles bots', () {
      expect(LoadScenario.spread.churnFraction, isZero);
      expect(LoadScenario.cluster.churnFraction, isZero);
      expect(LoadScenario.churn.churnFraction, greaterThan(0));
    });
  });

  group('rampGap', () {
    test('spreads the connections over the window', () {
      // 201 bots over 10s: the first goes immediately, the other 200 are
      // 50ms apart.
      final gap = rampGap(count: 201, over: const Duration(seconds: 10));

      expect(gap, equals(const Duration(milliseconds: 50)));
    });

    test('has nothing to spread for one bot or no window', () {
      expect(
        rampGap(count: 1, over: const Duration(seconds: 10)),
        equals(Duration.zero),
      );
      expect(rampGap(count: 200, over: Duration.zero), equals(Duration.zero));
    });
  });

  group('ChurnPlan', () {
    test('recycles the asked-for fraction over a minute', () {
      final plan = ChurnPlan(count: 200, fractionPerMinute: 0.2);

      var recycled = 0;
      for (var second = 0; second < 60; second++) {
        recycled += plan.take(1);
      }

      expect(recycled, equals(40));
    });

    test('carries the remainder instead of rounding it away', () {
      // 50 bots at 20%/min is 0.167 bots a second. Rounding each step to zero
      // would mean this scenario never churns at all.
      final plan = ChurnPlan(count: 50, fractionPerMinute: 0.2);

      expect(plan.take(1), isZero);
      expect(plan.owed, closeTo(0.167, 0.001));

      var recycled = 0;
      for (var second = 1; second < 60; second++) {
        recycled += plan.take(1);
      }

      expect(recycled, equals(10));
    });

    test('a steady scenario never recycles', () {
      final plan = ChurnPlan(count: 200, fractionPerMinute: 0);

      expect(plan.take(60), isZero);
    });

    test('never recycles more than the whole swarm in one step', () {
      // A pathological rate must not turn one step into a disconnect storm.
      final plan = ChurnPlan(count: 10, fractionPerMinute: 100);

      expect(plan.take(60), equals(10));
    });
  });
}
