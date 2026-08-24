import 'dart:ui';

import 'package:client/game/game_map.dart';
import 'package:client/game/static_art.dart';
import 'package:flame/components.dart';

/// Everything standing on the floor, whichever floor it is.
///
/// Sits between the floor and the beans in the z-order, so a bean walking
/// past a booth is drawn over it. That is not physically right for a bean
/// standing *behind* a tall booth, and it is deliberately not fixed: proper
/// y-sorting means re-sorting the draw list every frame, and the payoff at
/// this camera angle is a few pixels of overlap nobody looks at.
///
/// Since Phase 9 every shape is recorded into a single [Picture] in [onLoad]
/// and replayed with one `drawPicture` per frame — see [recordPicture]. Since
/// Phase 10 this component no longer knows *what* it is drawing: it asks
/// [layout] to paint itself, so a beach costs this file zero lines. The booths
/// come from config, but config is read before the game loads, so they are
/// just as static as the stage is.
class FurnitureComponent extends PositionComponent {
  /// Creates the furniture for [layout].
  FurnitureComponent({required this.layout}) : super(priority: -20);

  /// What to draw and where.
  final GameMap layout;

  Picture? _picture;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _picture = recordPicture(layout.paintFurniture);
  }

  /// Records the furniture again, because the map's words changed.
  ///
  /// The whole cost of a live config edit, and it is a load-time cost paid
  /// once rather than a per-frame one paid forever — which is the entire
  /// argument for the picture in the first place. The old one is disposed
  /// first: a `Picture` holds native memory, and a moderator who edits the
  /// projector six times should not leak six display lists.
  void rebuild() {
    _picture?.dispose();
    _picture = recordPicture(layout.paintFurniture);
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
}
