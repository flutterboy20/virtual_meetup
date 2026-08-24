import 'package:flame/components.dart';
import 'package:flame/experimental.dart' show Rectangle;

// Where the camera's centre is allowed to go, given how much world one screen
// shows. Pure math, kept out of the game class so it can be tested without a
// game loop.

/// The rectangle the camera's centre may move inside.
///
/// Flame's own `setBounds(considerViewport: true)` subtracts the viewport in
/// *pixels* from the world in *world units*, which is only correct at zoom 1.
/// At zoom 1.6 it shrinks the allowed area 1.6x too much, so the camera stops
/// short of the map edge and the local bean walks off the side of the screen
/// while still showing up on the minimap. Hence: our own bounds.
///
/// [viewportSize] is in pixels; [worldSize] and the result are in world units.
///
/// When the screen is wider (or taller) than the world, there is no room to
/// pan on that axis at all, so the bound collapses to the world's centre line
/// and the world sits centred with the void showing at both edges.
Rectangle cameraBounds({
  required Vector2 viewportSize,
  required Vector2 worldSize,
  required double zoom,
}) {
  final halfX = _halfVisible(viewportSize.x, zoom, worldSize.x);
  final halfY = _halfVisible(viewportSize.y, zoom, worldSize.y);
  return Rectangle.fromLTRB(
    halfX,
    halfY,
    worldSize.x - halfX,
    worldSize.y - halfY,
  );
}

/// Half of what one screen shows on an axis, never more than half the world.
double _halfVisible(double viewportExtent, double zoom, double worldExtent) {
  if (zoom <= 0) {
    return worldExtent / 2;
  }
  final half = viewportExtent / (2 * zoom);
  return half > worldExtent / 2 ? worldExtent / 2 : half;
}
