import 'package:client/game/beach_map.dart';
import 'package:client/game/stage_screen_component.dart';
import 'package:client/game/world_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// Runs [cycler] for [seconds] at 60 Hz.
void _run(LineCycler cycler, double seconds) {
  const step = 1 / 60;
  for (var t = 0.0; t < seconds; t += step) {
    cycler.update(step);
  }
}

void main() {
  group('parsing stageLines', () {
    test('keeps good lines, in the order they were written', () {
      final config = parseAppConfig(
        '{"stageLines": ["first", "second", "third"]}',
      );

      expect(config.stageLines, equals(['first', 'second', 'third']));
    });

    test('drops empty entries and trims the rest', () {
      final config = parseAppConfig(
        '{"stageLines": ["  keep me  ", "", "   ", "and me"]}',
      );

      expect(config.stageLines, equals(['keep me', 'and me']));
    });

    test('drops entries that are not strings', () {
      final config = parseAppConfig(
        '{"stageLines": ["keep me", 42, null, {"a": 1}]}',
      );

      expect(config.stageLines, equals(['keep me']));
    });

    test('falls back whole on a missing, empty or non-list value', () {
      // Whole, not per entry: a list is a script somebody wrote in an order
      // they meant, and half of one with our jokes filling the gaps is
      // neither their script nor ours.
      for (final raw in [
        '{}',
        '{"stageLines": []}',
        '{"stageLines": ["", "  "]}',
        '{"stageLines": "one line"}',
        '{"stageLines": 42}',
        '{"stageLines": null}',
        'not json at all',
      ]) {
        expect(
          parseAppConfig(raw).stageLines,
          equals(AppConfig.defaultStageLines),
          reason: '$raw should have fallen back whole',
        );
      }
    });

    test('ships seven built-in lines', () {
      expect(AppConfig.defaultStageLines, hasLength(7));
      expect(
        AppConfig.defaultStageLines.every((line) => line.trim().isNotEmpty),
        isTrue,
      );
    });
  });

  group('LineCycler', () {
    test('starts on the first line', () {
      final cycler = LineCycler(lines: const ['a', 'b', 'c']);

      expect(cycler.current, equals('a'));
      expect(cycler.fade, equals(1));
      expect(cycler.outgoing, isNull);
    });

    test('advances on the interval, not before it', () {
      final cycler = LineCycler(lines: const ['a', 'b', 'c']);

      _run(cycler, 5.5);
      expect(cycler.current, equals('a'));

      _run(cycler, 1);
      expect(cycler.current, equals('b'));
      expect(cycler.advances, equals(1));
    });

    test('wraps at the end of the list', () {
      final cycler = LineCycler(lines: const ['a', 'b']);

      _run(cycler, 6.2);
      expect(cycler.current, equals('b'));
      _run(cycler, 6.2);
      expect(cycler.current, equals('a'));
      expect(cycler.advances, equals(2));
    });

    test('holds still on a single-line list', () {
      // Nothing to cross-fade to. Holding is the correct behaviour and also
      // the cheap one: no timer, no fade, no swap.
      final cycler = LineCycler(lines: const ['only one']);

      _run(cycler, 60);

      expect(cycler.current, equals('only one'));
      expect(cycler.advances, isZero);
      expect(cycler.fade, equals(1));
      expect(cycler.outgoing, isNull);
    });

    test('an empty list says nothing, rather than throwing', () {
      final cycler = LineCycler(lines: const []);

      _run(cycler, 30);

      expect(cycler.current, isNull);
      expect(cycler.outgoing, isNull);
    });

    test('the crossfade is monotonic across a switch', () {
      // A fade that dipped would read as the screen flickering.
      final cycler = LineCycler(lines: const ['a', 'b']);
      _run(cycler, 5.9);

      const step = 1 / 60;
      var previous = cycler.fade;
      var sawTheSwap = false;
      var sawBothLines = false;

      for (var i = 0; i < 40; i++) {
        cycler.update(step);
        if (cycler.fade < previous) {
          // The only legal drop is the instant the line changes, and it
          // restarts from zero plus the one step of that same frame.
          expect(cycler.fade, lessThanOrEqualTo(step / 0.4 + 1e-9));
          expect(sawTheSwap, isFalse, reason: 'it swapped twice');
          sawTheSwap = true;
        }
        if (cycler.outgoing != null) {
          sawBothLines = true;
          expect(cycler.outgoing, equals('a'));
          expect(cycler.current, equals('b'));
        }
        previous = cycler.fade;
      }

      expect(sawTheSwap, isTrue);
      expect(sawBothLines, isTrue, reason: 'the two lines never overlapped');
      expect(cycler.fade, equals(1));
      expect(cycler.outgoing, isNull);
    });

    test('the fade takes about as long as it says it does', () {
      final cycler = LineCycler(lines: const ['a', 'b']);
      _run(cycler, 6.02);

      expect(cycler.fade, lessThan(1));
      _run(cycler, 0.4);
      expect(cycler.fade, equals(1));
    });
  });

  group('the screen on the map', () {
    test('the conference carries the lines; the beach has none', () {
      // Conference only: the beach has no stage, and an empty list is the
      // whole of "there is nothing here to say it on".
      expect(
        WorldLayout.of(const []).stageLines,
        equals(AppConfig.defaultStageLines),
      );
      expect(const BeachMap().stageLines, isEmpty);
      expect(
        gameMapFor(MapId.beach, stageLines: const ['hello']).stageLines,
        isEmpty,
      );
      expect(
        gameMapFor(MapId.conference, stageLines: const ['hello']).stageLines,
        equals(['hello']),
      );
    });

    test('the component sits over the stage screen and renders', () {
      final screen = StageScreenComponent(
        lines: AppConfig.defaultStageLines,
      );

      expect(screen.cycler.current, equals(AppConfig.defaultStageLines.first));
      // Above the furniture, below the beans: a bean standing in front of the
      // screen has to be in front of it.
      expect(screen.priority, lessThan(0));
    });
  });
}
