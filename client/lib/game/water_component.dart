import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/world_palette.dart';
import 'package:client/game/splash_field.dart';
import 'package:client/game/water_lod.dart';
import 'package:client/game/water_watcher.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/components.dart';
import 'package:protocol/protocol.dart';

/// One crest on the surface: where it sits, and its own phase offset.
typedef CrestPoint = ({double x, double y, double seed});

/// Live water, and the wakes trailing behind whoever is in it.
///
/// One component for every swimmable rectangle on the map — the conference's
/// pool, the beach's sea — because they are the same idea at two sizes.
///
/// This is the one part of the world that is deliberately **not** in the
/// static picture. A display list is a recording; putting an animation in one
/// freezes its first frame.
///
/// **Vector, not a fragment shader.** A `FragmentProgram` over the pool is
/// about 1.1M fragments a frame at a camera zoom of 1.6 on a 2x-DPR phone. The
/// GPU would cope. What it would not cope with is the first frame: CanvasKit
/// compiles SkSL on first use, and that is tens of milliseconds of hitch, on a
/// mid-range Android phone, on venue wifi, at the exact moment somebody walks
/// up to the pool. Sin-driven gradient bands plus ~40 stroked arcs off one
/// accumulator buy the same read for roughly 50 draw ops and no compile.
///
/// Water renders below the beans; the droplets a dive throws render above them
/// — see [SplashLayer]. A wake belongs on the surface *behind* a swimmer, and
/// a droplet belongs in the air *in front of* one, and one z-order cannot be
/// both.
///
/// ## Why the crests are viewport-scoped (Phase 10)
///
/// Phase 9's version drew a **fixed** 40 crests over the whole water rect.
/// That is right for a pool smaller than the screen and wrong twice over for
/// a sea:
///
/// - The beach's sea is **13.8x the pool's area** (576k square units against
///   41.8k). Forty crests spread over that is one per ~120 units; a phone at
///   zoom 1.6 shows roughly 244x527 world units, so about **nine crests would
///   be on screen** where the pool shows all forty. It stops reading as water
///   and starts reading as flat blue paint.
/// - Scaling the count with the area instead would be ~550 stroked arcs a
///   frame on a mid-range Android under CanvasKit, which is a slideshow.
///
/// So the crest lattice is generated **from the camera's visible rectangle**
/// each frame, and only the cells inside it are emitted. Cost becomes
/// O(screen) — the same ~40 arcs the pool costs today — at any sea size.
///
/// The lattice is anchored at the **world origin** and jittered by a pure
/// hash of the cell index, which is what stops a crest swimming as you walk:
/// the point at cell (i, j) is at the same world coordinate on every frame,
/// on every device, forever. The spacing is fixed at load rather than
/// recomputed per frame for the same reason — a spacing that tracked the
/// visible water area would slide every crest sideways as you walked towards
/// the shore.
///
/// The gradient [Paint] is built once per region and cached. A `Gradient` is
/// a shader object, and allocating one per region per frame was the second
/// cost this task removed.
class WaterComponent extends PositionComponent {
  /// Creates the pool, fed by [swimmers] once per frame.
  WaterComponent({
    required this.swimmers,
    GameMap? map,
    SplashField? field,
    WaterWatcher? watcher,
    WaterLod? lod,
    this.visibleWorldRect,
    this.frameP95Millis,
    this.localSwimmerId,
    this.isLocalSubmerged,
  }) : map = map ?? ConferenceMap.empty,
       field = field ?? SplashField(),
       lod = lod ?? WaterLod(),
       watcher =
           watcher ??
           WaterWatcher(
             regions: (map ?? ConferenceMap.empty).waterRegions,
             dryPlatforms: (map ?? ConferenceMap.empty).dryPlatforms,
             localId: localSwimmerId,
           ),
       super(priority: -27);

  /// The world this water belongs to.
  final GameMap map;

  /// What the camera can currently see, in world units.
  ///
  /// A callback rather than a `CameraComponent`, so this class never learns
  /// what a camera is and a test can hand it a rectangle. `null` means "no
  /// camera": the whole water rect is treated as visible, which is what a
  /// headless render wants and what the benchmark measures against.
  final Rect Function()? visibleWorldRect;

  /// The frame profile's p95, in milliseconds, or `null` to never drop tier.
  final double Function()? frameP95Millis;

  /// Which swimmer id is this client's own bean.
  final String? localSwimmerId;

  /// Whether the local bean is currently under the surface.
  final bool Function()? isLocalSubmerged;

  /// How much detail this device can currently afford.
  final WaterLod lod;

  /// Every bean this client can currently see, local one included.
  ///
  /// A callback rather than a list of players, so the pool never learns what a
  /// player *is*. It is handed positions and works out the rest — which is
  /// exactly why none of this costs a byte on the wire.
  final Iterable<SwimSample> Function() swimmers;

  /// The bounded particle pool. Shared with the [SplashLayer] above the beans.
  final SplashField field;

  /// Who is in the water, and who just got in.
  final WaterWatcher watcher;

  /// How many gradient bands ripple down the water.
  static const int bandCount = 7;

  /// How far a crest may be off screen and still be emitted, in world units.
  ///
  /// A crest is drawn about 24 units wide around its centre, so emitting only
  /// centres strictly inside the viewport would pop half a crest into
  /// existence at the screen edge as you walk.
  static const double crestMargin = 24;

  static const Color _deep = Color(0xFF1C6E8C);
  static const Color _shallow = Color(0xFF57BEDA);
  static const Color _crest = Color(0x59EAFBFF);

  /// How round the water's rim is, in world units.
  static const Radius shapeRadius = Radius.circular(26);

  double _phase = 0;
  double? _spacing;
  final Map<Rect, Paint> _fills = {};

  /// Every swimmable rectangle, as drawable rects.
  Iterable<Rect> get _rects => map.waterRegions.map(
    (region) =>
        Rect.fromLTRB(region.left, region.top, region.right, region.bottom),
  );

  static RRect _shapeOf(Rect rect) =>
      RRect.fromRectAndRadius(rect, shapeRadius);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // How much world fits on screen changed, so the lattice that was sized
    // against it is stale. Rotating a phone re-lays-out everything anyway,
    // which is the one moment a crest is allowed to move.
    _spacing = null;
  }

  @override
  void onRemove() {
    _fills.clear();
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);

    final p95 = frameP95Millis?.call();
    if (p95 != null) lod.update(dt, p95Millis: p95);

    // Frozen rather than reset at the flat tier: the bands stay exactly where
    // they were instead of snapping back to phase zero, so dropping to flat
    // reads as the water settling rather than as it jumping.
    if (lod.isAnimated) _phase = (_phase + dt * 0.9) % (2 * math.pi);

    watcher
      ..localId = localSwimmerId
      ..wakeInterval = lod.wakeInterval
      ..remoteWakeInterval = lod.remoteWakeInterval(
        localIsSubmerged: isLocalSubmerged?.call() ?? false,
      );

    final events = watcher.update(dt, swimmers());
    if (lod.emitsParticles) {
      for (final dive in events.dives) {
        field.splash(dive.x, dive.y);
      }
      for (final wake in events.wakes) {
        field.wake(wake.x, wake.y);
      }
    }
    field.update(dt);
  }

  @override
  void render(Canvas canvas) {
    for (final rect in _rects) {
      _renderRegion(canvas, rect);
    }
  }

  void _renderRegion(Canvas canvas, Rect rect) {
    final visible = visibleWorldRect?.call() ?? rect;
    // Nothing of this region is on screen. Skia would cull the draw ops
    // anyway, but the lattice walk below is this class's cost, not Skia's.
    if (!visible.overlaps(rect)) return;

    canvas
      ..save()
      ..clipRRect(_shapeOf(rect))
      ..drawRect(rect, _fillFor(rect));

    _renderBands(canvas, rect, visible);
    _renderCrests(canvas, rect, visible);
    _renderWakes(canvas);

    canvas
      ..restore()
      // The coping, drawn after the clip is dropped so the rim sits on top of
      // the water rather than being cut in half by it.
      ..drawRRect(
        _shapeOf(rect),
        Paint()
          ..color = WorldPalette.of(_zoneOf(rect)).accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7,
      );
  }

  /// The vertical gradient, built once per region and kept.
  ///
  /// `Gradient.linear` allocates a shader. Doing that per region per frame is
  /// exactly the sort of per-frame allocation the static-art pipeline exists
  /// to remove, and it was invisible while there was one small pool.
  Paint _fillFor(Rect rect) => _fills.putIfAbsent(
    rect,
    () => Paint()
      ..shader = Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        const [_shallow, _deep],
      ),
  );

  /// The bands: one accumulator, seven offsets.
  ///
  /// Each band is a soft light stripe sliding down the water at its own
  /// phase, which is what sells "moving water" without a single per-pixel
  /// operation. Clipped horizontally to what is on screen, so a band across a
  /// 1200-unit sea is not a 1200-unit rectangle every frame.
  void _renderBands(Canvas canvas, Rect rect, Rect visible) {
    final left = math.max(rect.left, visible.left);
    final right = math.min(rect.right, visible.right);
    if (right <= left) return;

    for (var i = 0; i < bandCount; i++) {
      final t = (_phase + i * 2 * math.pi / bandCount) % (2 * math.pi);
      final y = rect.top + rect.height * (0.5 + 0.5 * math.sin(t));
      final alpha = 0.05 + 0.05 * (1 + math.cos(t)) / 2;
      canvas.drawRect(
        Rect.fromLTRB(left, y - 9, right, y + 9),
        Paint()..color = _shallow.withValues(alpha: alpha),
      );
    }
  }

  /// The crests: stroked arcs on a world-anchored lattice, clipped to screen.
  ///
  /// Each nods at its own offset off the same accumulator, so the whole
  /// surface moves from one number.
  void _renderCrests(Canvas canvas, Rect rect, Rect visible) {
    final lattice = crestLattice(rect, visible);
    if (lattice.isEmpty) return;

    final crest = Paint()
      ..color = _crest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (final point in lattice) {
      final nod = math.sin(_phase * 1.6 + point.seed * 2 * math.pi);
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(point.x, point.y + nod * 3),
          width: 20 + nod * 4,
          height: 9,
        ),
        math.pi * 1.08,
        math.pi * 0.84,
        false,
        crest,
      );
    }
  }

  /// Every crest this frame would draw in [rect], given what is [visible].
  ///
  /// Separated from the drawing so it can be counted in a test: a `Canvas`
  /// cannot be asked what is in it, and "how many arcs does the sea cost"
  /// is the single number this whole task is about.
  ///
  /// The lattice is deterministic rather than random, so the surface is
  /// identical on every device — two people standing at the same pool should
  /// be looking at the same water — and it is anchored at the **world
  /// origin**, so a crest stays at the same world coordinate as the camera
  /// moves. That last property is what stops crests swimming as you walk.
  List<CrestPoint> crestLattice(Rect rect, Rect visible) {
    final wanted = lod.crestCount;
    if (wanted <= 0) return const [];

    // The inset keeps a crest off the rim, exactly as Phase 9's did.
    final inner = rect.deflate(12);
    if (inner.isEmpty) return const [];

    final area = Rect.fromLTRB(
      math.max(inner.left, visible.left - crestMargin),
      math.max(inner.top, visible.top - crestMargin),
      math.min(inner.right, visible.right + crestMargin),
      math.min(inner.bottom, visible.bottom + crestMargin),
    );
    if (area.isEmpty) return const [];

    final spacing = _spacingFor(visible);

    // Half the lattice at the reduced tier, by the parity of the cell index.
    // Every surviving crest stays exactly where it was, which is what stops a
    // tier change reading as the water lurching sideways.
    final halfDensity = wanted <= WaterLod.reducedCrests;

    final firstColumn = (area.left / spacing).floor();
    final lastColumn = (area.right / spacing).ceil();
    final firstRow = (area.top / spacing).floor();
    final lastRow = (area.bottom / spacing).ceil();

    // A hard ceiling on top of the lattice maths. The spacing is already
    // sized to land near `wanted`, but a spacing left stale by a resize, or a
    // viewport far larger than the one it was sized against, must not be able
    // to turn one frame into a thousand draw calls.
    final ceiling = wanted * 3;
    final points = <CrestPoint>[];

    for (var column = firstColumn; column <= lastColumn; column++) {
      for (var row = firstRow; row <= lastRow; row++) {
        if (halfDensity && ((column + row) & 1) == 1) continue;
        final hash = _hash(column, row);
        final x = (column + 0.15 + 0.7 * _unit(hash)) * spacing;
        final y = (row + 0.15 + 0.7 * _unit(hash >> 11)) * spacing;
        if (!area.contains(Offset(x, y))) continue;

        points.add((x: x, y: y, seed: _unit(hash >> 22)));
        if (points.length >= ceiling) return points;
      }
    }
    return points;
  }

  /// The lattice spacing, sized once against what one screen shows.
  ///
  /// Cached rather than recomputed per frame **because it must not change
  /// while the player walks**: a spacing derived from the visible *water*
  /// area would shrink as you waded in, and every crest on screen would slide
  /// to a new home. Only a resize invalidates it.
  double _spacingFor(Rect visible) => _spacing ??= WaterLod.spacingFor(
    visible.width * visible.height,
    WaterLod.fullCrests,
  );

  /// A pure hash of a lattice cell.
  ///
  /// Not `Random`: the surface has to be identical on every device and every
  /// launch, and cell (i, j) has to hash the same on frame one and on frame
  /// ten thousand. The same reasoning as `ZoneFloorArt._noise`.
  static int _hash(int column, int row) {
    var h = (column * 374761393 + row * 668265263) & 0xFFFFFFFF;
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;
    return h ^ (h >> 16);
  }

  /// The low bits of [hash] as a number from 0 to 1.
  static double _unit(int hash) => (hash & 0xFFFF) / 0xFFFF;

  /// Whose palette the rim borrows: the zone the water sits in.
  WorldZone _zoneOf(Rect rect) =>
      map.spec.zoneAt(rect.center.dx, rect.center.dy) ?? WorldZone.lounge;

  void _renderWakes(Canvas canvas) {
    for (final particle in field.live) {
      if (particle.kind != SplashKind.wake) continue;
      final age = particle.age;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(particle.x, particle.y),
          width: (particle.radius + age * 34) * 2,
          // Flattened, because this is a ring seen from above at an angle.
          height: (particle.radius + age * 34) * 1.15,
        ),
        Paint()
          ..color = _crest.withValues(alpha: 0.42 * (1 - age))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * (1 - age) + 0.6,
      );
    }
  }
}

/// The droplets a dive throws, drawn above the beans.
///
/// A separate component from [WaterComponent] purely for the z-order, and it
/// shares that component's [SplashField] rather than owning one: two pools of
/// particles would be two caps, and two caps is no cap.
class SplashLayer extends PositionComponent {
  /// Creates the layer over [field].
  SplashLayer({required this.field});

  /// The bounded particle pool, owned by the water.
  final SplashField field;

  static const Color _droplet = Color(0xFFDFF6FF);

  @override
  void render(Canvas canvas) {
    for (final particle in field.live) {
      if (particle.kind != SplashKind.droplet) continue;
      final age = particle.age;
      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.radius * (1 - age * 0.65),
        Paint()..color = _droplet.withValues(alpha: 0.85 * (1 - age)),
      );
    }
  }
}
