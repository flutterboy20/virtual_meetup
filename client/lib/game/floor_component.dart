import 'dart:ui';

import 'package:client/core/world_palette.dart';
import 'package:client/game/static_art.dart';
import 'package:client/game/world_layout.dart';
import 'package:client/game/zone_floor_art.dart';
import 'package:flame/components.dart';
import 'package:protocol/protocol.dart';

/// One map's zone floors, and the ground around them.
///
/// Drawn, not tiled. A tilemap would mean an image, an atlas, a loader and a
/// cold-load cost on conference wifi; a handful of rectangles and a stroked
/// outline are a few hundred bytes of coordinates that stay crisp at any zoom.
///
/// The floor is the bottom of the z-order: it renders below furniture, which
/// renders below beans, which render below the nametags and emotes.
///
/// **Nothing here moves**, which is why since Phase 9 the whole thing is
/// recorded into a single [Picture] in [onLoad] and replayed with one
/// `drawPicture` per frame. See [recordPicture] for why that is the decision
/// the rest of the phase rests on, and why it is a display list rather than a
/// rasterised image.
class FloorComponent extends PositionComponent {
  /// Creates the floor of [map], anchored at the world origin.
  ///
  /// [worldSize] defaults to the map's own size and is only a parameter
  /// because the component's `size` is what the outside ground is painted
  /// over; passing one that disagrees with the map is a test's business, not
  /// the game's.
  FloorComponent({Vector2? worldSize, GameMap? map})
    : map = map ?? ConferenceMap.empty,
      super(
        size:
            worldSize ??
            Vector2(
              (map ?? ConferenceMap.empty).spec.width,
              (map ?? ConferenceMap.empty).spec.height,
            ),
        priority: -30,
      );

  /// Which world this is the floor of.
  final GameMap map;

  /// Spacing of the motion-cue grid lines, in world units.
  ///
  /// Without them a flat colour makes walking look like standing still: there
  /// is nothing on screen for the eye to measure the movement against.
  static const double gridStep = 64;

  Picture? _picture;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _picture = recordPicture(_paintStatic);
  }

  @override
  void onRemove() {
    _picture?.dispose();
    _picture = null;
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    final picture = _picture;
    if (picture != null) canvas.drawPicture(picture);
  }

  /// Draws the entire static floor, once, into the recording canvas.
  void _paintStatic(Canvas canvas) {
    canvas.drawRect(
      size.toRect(),
      Paint()..color = WorldPalette.outside,
    );
    // The exterior ground shows only where a map has no floor — the
    // conference's two void corners. A map that tiles its whole box, like the
    // beach, has none and this loop does nothing.
    for (final area in map.voids) {
      ZoneFloorArt.paintOutside(canvas, area);
    }

    final outline = _buildOutline();
    // The shadow the building casts on the ground it sits on. Drawn as a wide
    // stroke *before* the zones, so its inner half is painted over by the
    // floors and only the outer half survives. One op for the single cue that
    // stops the void reading as a hole.
    canvas.drawPath(
      outline,
      Paint()
        ..color = const Color(0x2E23180A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 34
        ..strokeJoin = StrokeJoin.round,
    );

    for (final zone in map.spec.zones) {
      _paintZone(canvas, zone);
    }
    // One stroke around the whole silhouette rather than four per zone: a
    // per-zone border would draw a line down the middle of every walkway and
    // turn the building back into seven separate rooms.
    canvas.drawPath(
      outline,
      Paint()
        ..color = WorldPalette.wall
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Draws one zone's floor: its fill and its texture.
  ///
  /// No name on it. Phase 9 painted the zone's name flat on the ground like
  /// a sports hall; it read as clutter under the props rather than as
  /// signage, and the room is legible from its floor colour and its
  /// furniture without being captioned.
  void _paintZone(Canvas canvas, WorldZone zone) {
    final colors = WorldPalette.of(zone);
    final rect = Rect.fromLTRB(
      zone.rect.left,
      zone.rect.top,
      zone.rect.right,
      zone.rect.bottom,
    );
    canvas
      ..save()
      // Clipped so the texture cannot bleed into the next zone.
      ..clipRect(rect)
      ..drawRect(rect, Paint()..color = colors.floor);

    // The texture that used to be a bare grid of lines. It is affordable
    // because it is recorded once — see `static_art.dart`. Which texture is
    // the map's decision: sand does not want a carpet weave.
    map.paintZoneFloor(canvas, zone, rect);

    canvas.restore();
  }

  /// Builds the outline of the whole building as one path.
  Path _buildOutline() {
    var union = Path();
    for (final zone in map.spec.zones) {
      final rect = zone.rect;
      final path = Path()
        ..addRect(Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom));
      union = Path.combine(PathOperation.union, union, path);
    }
    return union;
  }
}
