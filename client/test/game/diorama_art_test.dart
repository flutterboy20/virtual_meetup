import 'dart:ui';

import 'package:client/game/diorama_art.dart';
import 'package:client/game/static_art.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logs the draw calls a prop makes, in order, with the colour of each.
class _RecordingCanvas implements Canvas {
  final List<(String, int)> calls = [];

  @override
  void drawPath(Path path, Paint paint) =>
      calls.add(('path', paint.color.toARGB32()));

  @override
  void drawRRect(RRect rrect, Paint paint) =>
      calls.add(('rrect-${paint.style.name}', paint.color.toARGB32()));

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      calls.add(('circle', paint.color.toARGB32()));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _footprint = Rect.fromLTRB(100, 200, 180, 240);
const double _lift = DioramaArt.lift;
const Offset _slope = DioramaArt.shadowSlope;
const _top = Color(0xFFE2B23A);
final int _shadow = DioramaArt.shadowColor.toARGB32();
final int _edge = DioramaArt.edgeColor.toARGB32();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('box faces', () {
    test('the top face is the footprint, lifted by its height', () {
      final top = DioramaArt.topFace(_footprint, height: 20);

      expect(top, equals(_footprint.translate(0, -20 * _lift)));
    });

    test('the art stays over the footprint, east to west', () {
      // Height only ever moves things up the screen. If a face grew sideways
      // past the footprint, a bean could stand "inside" a drawn wall, which
      // is the visible non-wall the layout tests exist to prevent.
      final top = DioramaArt.topFace(_footprint, height: 30, base: 8);
      final front = DioramaArt.frontFace(_footprint, height: 30, base: 8);

      for (final face in [top, front]) {
        expect(face.left, equals(_footprint.left));
        expect(face.right, equals(_footprint.right));
      }
    });

    test('the front hangs from the top face down to the floor', () {
      final top = DioramaArt.topFace(_footprint, height: 20);
      final front = DioramaArt.frontFace(_footprint, height: 20);

      // Shared edge: no crack of floor between the two faces.
      expect(front.top, equals(top.bottom));
      expect(front.bottom, equals(_footprint.bottom));
      expect(front.height, closeTo(20 * _lift, 1e-9));
    });

    test('a raised box stops short of the floor by its base', () {
      final top = DioramaArt.topFace(_footprint, height: 4, base: 56);
      final front = DioramaArt.frontFace(_footprint, height: 4, base: 56);

      expect(front.top, closeTo(top.bottom, 1e-9));
      expect(front.bottom, closeTo(_footprint.bottom - 56 * _lift, 1e-9));
      expect(front.height, closeTo(4 * _lift, 1e-9));
    });

    test('a flat box is just its footprint, with no front at all', () {
      expect(DioramaArt.topFace(_footprint, height: 0), equals(_footprint));
      expect(DioramaArt.frontFace(_footprint, height: 0).isEmpty, isTrue);
    });

    test('a negative height is a bug, not a box', () {
      expect(
        () => DioramaArt.topFace(_footprint, height: -1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => DioramaArt.frontFace(_footprint, height: 4, base: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('box shadow', () {
    test('a box on the floor casts from its own footprint', () {
      final outline = DioramaArt.boxShadow(_footprint, height: 20);

      expect(outline, hasLength(6));
      expect(outline.first, equals(_footprint.topLeft));
      expect(outline.last, equals(_footprint.bottomLeft));
    });

    test('falls south-east, away from the north-west light', () {
      final outline = DioramaArt.boxShadow(_footprint, height: 20);

      for (final corner in outline) {
        expect(corner.dx, greaterThanOrEqualTo(_footprint.left));
        expect(corner.dy, greaterThanOrEqualTo(_footprint.top));
      }
      expect(outline[3], equals(_footprint.bottomRight + _slope * 20));
    });

    test('a taller box casts a longer shadow', () {
      final short = DioramaArt.boxShadow(_footprint, height: 8)[3];
      final tall = DioramaArt.boxShadow(_footprint, height: 60)[3];

      expect(tall.dx, greaterThan(short.dx));
      expect(tall.dy, greaterThan(short.dy));
    });

    test('a raised box casts a shadow that has come loose from it', () {
      // What makes a canopy read as overhead rather than as a rug.
      final outline = DioramaArt.boxShadow(
        _footprint,
        height: 4,
        base: 56,
      );

      expect(outline.first, equals(_footprint.topLeft + _slope * 56));
      for (final corner in outline) {
        expect(corner.dx, greaterThan(_footprint.left));
        expect(corner.dy, greaterThan(_footprint.top));
      }
    });

    test('a flat box casts nothing past its own footprint', () {
      final outline = DioramaArt.boxShadow(_footprint, height: 0);

      expect(
        outline.toSet(),
        equals({
          _footprint.topLeft,
          _footprint.topRight,
          _footprint.bottomRight,
          _footprint.bottomLeft,
        }),
      );
    });
  });

  group('cylinder', () {
    const centre = Offset(470, 466);

    test('the top is the footprint centre, lifted', () {
      expect(
        DioramaArt.cylinderTop(centre, height: 18),
        equals(centre.translate(0, -18 * _lift)),
      );
    });

    test('the foot is on the floor unless the cylinder is raised', () {
      expect(DioramaArt.cylinderFoot(centre), equals(centre));
      expect(
        DioramaArt.cylinderFoot(centre, base: 20),
        equals(centre.translate(0, -20 * _lift)),
      );
    });

    test('the shadow runs from the foot to where the top lands', () {
      final (:from, :to) = DioramaArt.cylinderShadow(
        centre,
        height: 84,
        base: 6,
      );

      expect(from, equals(centre + _slope * 6));
      expect(to, equals(centre + _slope * 90));
    });

    test('a negative height is a bug, not a cylinder', () {
      expect(
        () => DioramaArt.cylinderTop(centre, height: -2),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('painting', () {
    test('a box draws shadow, front, top, then its edge', () {
      final canvas = _RecordingCanvas();

      DioramaArt.paintBox(canvas, _footprint, height: 20, color: _top);

      expect(canvas.calls.map((c) => c.$1), [
        'path',
        'rrect-fill',
        'rrect-fill',
        'rrect-stroke',
      ]);
      expect(canvas.calls[0].$2, equals(_shadow));
      expect(canvas.calls[2].$2, equals(_top.toARGB32()));
      expect(canvas.calls[3].$2, equals(_edge));
    });

    test('the front face is the top in shade', () {
      final canvas = _RecordingCanvas();

      DioramaArt.paintBox(canvas, _footprint, height: 20, color: _top);

      final front = Color(canvas.calls[1].$2);
      expect(front.computeLuminance(), lessThan(_top.computeLuminance()));
    });

    test('a box can skip its shadow, or take its own front colour', () {
      // Both for the overhead layer: the shadow goes on the floor picture and
      // the canopy on the one above the beans.
      final canvas = _RecordingCanvas();
      const wall = Color(0xFF0553B1);

      DioramaArt.paintBox(
        canvas,
        _footprint,
        height: 62,
        color: _top,
        front: wall,
        shadow: false,
      );

      expect(canvas.calls.map((c) => c.$1), isNot(contains('path')));
      expect(canvas.calls.first.$2, equals(wall.toARGB32()));
    });

    test('a cylinder draws shadow, side, top, then its edge', () {
      final canvas = _RecordingCanvas();

      DioramaArt.paintCylinder(
        canvas,
        const Offset(800, 600),
        40,
        height: 84,
        color: _top,
      );

      expect(canvas.calls.map((c) => c.$1), [
        'rrect-fill',
        'rrect-fill',
        'circle',
        'rrect-stroke',
      ]);
      expect(canvas.calls[0].$2, equals(_shadow));
      expect(canvas.calls[2].$2, equals(_top.toARGB32()));
      expect(canvas.calls[3].$2, equals(_edge));
    });

    test('records into a real picture, flat props included', () {
      // A zero-length capsule asks `rotate` for the direction of a zero
      // offset; this is the check that it does not throw on a real canvas.
      final picture = recordPicture((canvas) {
        DioramaArt.paintBox(
          canvas,
          _footprint,
          height: 0,
          color: _top,
          corner: const Radius.circular(6),
        );
        DioramaArt.paintBox(canvas, _footprint, height: 20, color: _top);
        DioramaArt.paintCylinder(
          canvas,
          const Offset(470, 466),
          26,
          height: 0,
          color: _top,
        );
        DioramaArt.paintCylinder(
          canvas,
          const Offset(470, 466),
          26,
          height: 18,
          base: 4,
          color: _top,
        );
      });
      addTearDown(picture.dispose);
    });
  });
}
