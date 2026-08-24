import 'package:client/game/camera_bounds.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final world = Vector2(1600, 1200);

  group('cameraBounds', () {
    test('insets by half of what the screen shows, in world units', () {
      // 400x800 pixels at zoom 1.6 shows 250x500 world units.
      final bounds = cameraBounds(
        viewportSize: Vector2(400, 800),
        worldSize: world,
        zoom: 1.6,
      );

      expect(bounds.topLeft, closeToVector(Vector2(125, 250)));
      expect(bounds.bottomRight, closeToVector(Vector2(1475, 950)));
    });

    test('keeps a bean at the map edge on screen', () {
      const zoom = 1.6;
      final viewport = Vector2(400, 800);
      final bounds = cameraBounds(
        viewportSize: viewport,
        worldSize: world,
        zoom: zoom,
      );

      // A bean pressed against the bottom edge, with the camera clamped.
      const beanY = 1190.0;
      final cameraY = beanY.clamp(bounds.top, bounds.bottom);
      final pixelsFromCentre = (beanY - cameraY) * zoom;

      expect(pixelsFromCentre, lessThan(viewport.y / 2));
    });

    test(
      'collapses to the centre when the screen is bigger than the world',
      () {
        final bounds = cameraBounds(
          viewportSize: Vector2(4000, 3000),
          worldSize: world,
          zoom: 1,
        );

        expect(bounds.topLeft, closeToVector(Vector2(800, 600)));
        expect(bounds.bottomRight, closeToVector(Vector2(800, 600)));
      },
    );

    test('falls back to the world centre for a non-positive zoom', () {
      final bounds = cameraBounds(
        viewportSize: Vector2(400, 800),
        worldSize: world,
        zoom: 0,
      );

      expect(bounds.topLeft, closeToVector(Vector2(800, 600)));
    });
  });
}

Matcher closeToVector(Vector2 expected) => predicate<Vector2>(
  (actual) => (actual - expected).length < 0.001,
  'is within 0.001 of $expected',
);
