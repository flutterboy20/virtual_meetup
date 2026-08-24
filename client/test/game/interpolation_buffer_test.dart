import 'package:client/game/interpolation_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InterpolationBuffer buffer;

  setUp(() => buffer = InterpolationBuffer());

  group('an empty buffer', () {
    test('knows it is empty', () {
      expect(buffer.isEmpty, isTrue);
      expect(buffer.newest, isNull);
      expect(buffer.length, isZero);
    });

    test('refuses to invent a position', () {
      // A buffer is always seeded with the position a player appeared at, so
      // asking before that is a bug worth hearing about, not a zero to draw.
      expect(() => buffer.positionAt(0), throwsStateError);
    });
  });

  group('one sample', () {
    test('holds still at it, whenever it is asked', () {
      buffer.add(1, 100, 200);

      expect(buffer.positionAt(0.5), equals((x: 100.0, y: 200.0)));
      expect(buffer.positionAt(1), equals((x: 100.0, y: 200.0)));
      expect(buffer.positionAt(99), equals((x: 100.0, y: 200.0)));
    });
  });

  group('interpolation', () {
    setUp(() {
      buffer
        ..add(1, 0, 0)
        ..add(2, 100, 200);
    });

    test('lands halfway at the halfway point', () {
      expect(buffer.positionAt(1.5), equals((x: 50.0, y: 100.0)));
    });

    test('lands a quarter of the way at a quarter of the time', () {
      expect(buffer.positionAt(1.25), equals((x: 25.0, y: 50.0)));
    });

    test('moves smoothly rather than in steps', () {
      // The point of the whole exercise: sixty render calls between two
      // samples have to produce sixty different positions, not two.
      final seen = <double>{};
      for (var i = 0; i <= 60; i++) {
        seen.add(buffer.positionAt(1 + i / 60).x);
      }

      expect(seen.length, equals(61));
    });

    test('never overshoots either end', () {
      for (var i = 0; i <= 60; i++) {
        final position = buffer.positionAt(1 + i / 60);
        expect(position.x, inInclusiveRange(0, 100));
        expect(position.y, inInclusiveRange(0, 200));
      }
    });
  });

  group('clamping instead of extrapolating', () {
    test('before the first sample it holds at the first position', () {
      buffer
        ..add(1, 10, 10)
        ..add(2, 90, 90);

      // What a freshly appeared bean does while the render head is still
      // 100ms behind its first sample: it stands where it appeared.
      expect(buffer.positionAt(0), equals((x: 10.0, y: 10.0)));
    });

    test('past the last sample it holds, it does not guess ahead', () {
      buffer
        ..add(1, 0, 0)
        ..add(2, 100, 0);

      // A guess would send the bean walking through a wall and then snap it
      // back when the truth arrived. Standing still is the quieter failure.
      expect(buffer.positionAt(5), equals((x: 100.0, y: 0.0)));
    });

    test('a late snapshot resumes from where the bean was held', () {
      buffer
        ..add(1, 0, 0)
        ..add(2, 100, 0);
      expect(buffer.positionAt(2.5).x, equals(100));

      // The missing snapshot finally lands, covering a double-length gap.
      buffer.add(3, 200, 0);

      expect(buffer.positionAt(2.5), equals((x: 150.0, y: 0.0)));
    });

    test('a stall does not make the bean jump when data returns', () {
      buffer
        ..add(1, 0, 0)
        ..add(2, 100, 0);
      for (var i = 0; i < 30; i++) {
        buffer.positionAt(2 + i / 60);
      }

      buffer.add(3, 110, 0);

      // Resuming from 100, not from wherever an extrapolation had drifted to.
      expect(buffer.positionAt(2), equals((x: 100.0, y: 0.0)));
      expect(buffer.positionAt(2.5).x, closeTo(105, 0.001));
    });

    test('reports when the render head has outrun the data', () {
      buffer.add(1, 0, 0);

      expect(buffer.isStarvedAt(0.9), isFalse);
      expect(buffer.isStarvedAt(1.5), isTrue);
    });
  });

  group('sample bookkeeping', () {
    test('an out-of-order sample is dropped, not spliced in', () {
      buffer
        ..add(2, 100, 0)
        ..add(1, 0, 0);

      expect(buffer.length, equals(1));
      expect(buffer.newest?.x, equals(100));
    });

    test('a second sample at the same instant replaces the first', () {
      buffer
        ..add(1, 10, 0)
        ..add(1, 20, 0);

      expect(buffer.length, equals(1));
      expect(buffer.positionAt(1), equals((x: 20.0, y: 0.0)));
    });

    test('the buffer does not grow without bound', () {
      for (var i = 0; i < 200; i++) {
        buffer.add(i.toDouble(), i.toDouble(), 0);
      }

      expect(buffer.length, lessThanOrEqualTo(buffer.capacity));
      expect(buffer.newest?.x, equals(199));
    });

    test('samples the render head has passed are dropped', () {
      for (var i = 0; i < 5; i++) {
        buffer.add(i.toDouble(), i * 10, 0);
      }

      buffer.positionAt(3.5);

      // Only the pair around the render head has to survive.
      expect(buffer.length, equals(2));
      expect(buffer.positionAt(3.5), equals((x: 35.0, y: 0.0)));
    });

    test('a full buffer still interpolates correctly', () {
      for (var i = 0; i < 200; i++) {
        buffer.add(i.toDouble(), i * 10, 0);
      }

      expect(buffer.positionAt(198.5), equals((x: 1985.0, y: 0.0)));
    });
  });

  group('the delay constant', () {
    test('leaves slack beyond one server tick', () {
      // 15Hz is one sample every ~66ms. A delay of exactly that would leave
      // the render head with nothing to interpolate towards the moment a
      // single snapshot ran late.
      expect(interpolationDelay, greaterThan(1 / 15));
    });
  });
}
