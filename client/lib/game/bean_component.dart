import 'dart:ui';

import 'package:client/game/bean_animation.dart';
import 'package:client/game/bean_appearance.dart';
import 'package:client/game/bean_art.dart';
import 'package:client/game/swim_state.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/components.dart';

/// One bean: the character a player walks around as.
///
/// The bean is drawn from vector shapes rather than a sprite sheet — it is a
/// few dozen bytes of code instead of an image download, it recolours per
/// player for free, and it stays crisp at any zoom.
///
/// The component is deliberately *only* a view: it renders itself from
/// [appearance] and from [animation], which it advances from [velocity].
/// Whoever owns the bean (the local input code now, the network layer from
/// Phase 2) writes [velocity] and `position`; the bean never decides where it
/// is.
class BeanComponent extends PositionComponent {
  /// Creates a bean whose `position` is the point its feet stand on.
  BeanComponent({
    required super.position,
    required this.animation,
    GameMap? map,
    BeanAppearance appearance = const BeanAppearance(),
  }) : map = map ?? ConferenceMap.empty,
       super(
         size: Vector2(bodyWidth, bodyHeight),
         anchor: Anchor.bottomCenter,
       ) {
    _appearance = appearance;
    _rebuildPaints();
  }

  /// Width of the bean's body, in world units.
  ///
  /// The shapes themselves live in [BeanArt], which the setup screen's live
  /// preview draws with too — one bean, two renderers, no chance of the
  /// preview showing a hat the game does not.
  static const double bodyWidth = BeanArt.bodyWidth;

  /// Height of the bean's body, in world units.
  static const double bodyHeight = BeanArt.bodyHeight;

  static const Color _shadowColor = Color(0xFF000000);

  /// The foam ring where a submerged body meets the surface.
  static const Color _waterlineColor = Color(0xFFE4F7FF);

  /// The board's deck.
  static const Color _boardColor = Color(0xFFF6F1E4);

  /// The stripe down it, so it is not a white smear on white foam.
  static const Color _boardStripeColor = Color(0xFF2F9E8F);

  /// How long the board is, as a fraction of the bean's height.
  static const double _boardLength = 1.34;

  /// How wide the board is, as a fraction of the bean's width.
  static const double _boardWidth = 0.72;

  /// The animation state driving the bean's "alive" touches.
  final BeanAnimation animation;

  /// The world this bean is standing in, so it knows where the water is.
  final GameMap map;

  /// How submerged this bean is, and whether it is mid-dive.
  ///
  /// Driven from the bean's **own position** rather than from anything the
  /// owner sets, and that is the whole trick: `GameMap.isWater` is pure map
  /// geometry that every client has a copy of, so a remote bean swims on this
  /// screen without the server ever mentioning water. Nothing about swimming
  /// is on the wire — see `GameMap.waterRegions`.
  final SwimState swim = SwimState();

  /// Current velocity in world units per second, written by the owner.
  final Vector2 velocity = Vector2.zero();

  bool _hasBoard = false;

  late BeanAppearance _appearance;
  late BeanPaints _paints;
  final Paint _shadowPaint = Paint();

  /// How this bean looks. Assigning rebuilds the cached paints.
  BeanAppearance get appearance => _appearance;

  set appearance(BeanAppearance value) {
    _appearance = value;
    _rebuildPaints();
  }

  /// Whether this player has found the board.
  ///
  /// A fact about the *player*, which is why it is set from the outside — by
  /// the game for the local bean, by `RemotePlayers` for everybody else.
  /// Whether it is drawn is this class's business, and it depends on two more
  /// things: the bean has to be in the water, and the map has to allow
  /// surfing at all.
  ///
  /// `GameMap.surfSpeedFactor` being `null` is the whole of "no surfing on
  /// this map", and it is applied here rather than at every call site — so a
  /// player who carries a board onto the conference map swims in the pool
  /// like everybody else without anybody having to remember to strip it.
  bool get hasBoard => _hasBoard;

  set hasBoard(bool value) {
    _hasBoard = value;
    swim.onBoard = value && map.surfSpeedFactor != null;
  }

  @override
  void update(double dt) {
    super.update(dt);
    animation.update(dt, velocity);
    swim.update(dt, inWater: map.isWater(position.x, position.y));
  }

  @override
  void render(Canvas canvas) {
    final feet = Offset(size.x / 2, size.y);
    _renderShadow(canvas, feet);

    final sunk = swim.sinkFraction * size.y;
    final submerged = swim.submersion > 0.01;
    final surfing = swim.isSurfing;

    // Under the bean's feet, over the water, before the body — so the bean
    // stands on it rather than behind it.
    if (surfing) _renderBoard(canvas, feet);

    canvas.save();
    if (submerged) {
      // Cut the body off at the waterline. Everything below the surface is
      // simply not drawn — cheaper and more legible than trying to tint it,
      // and at this camera angle "the bottom half is missing" is exactly what
      // being in a pool looks like.
      canvas.clipRect(
        Rect.fromLTRB(-size.x, -size.y, size.x * 2, feet.dy - sunk),
      );
    }
    canvas
      // Everything below is drawn in "bean space": the origin sits between
      // the feet and up is negative y. Mirroring first means the lean
      // rotation is mirrored too, so a lean is always *forwards*.
      ..translate(
        feet.dx + swim.wobble,
        feet.dy + animation.bobOffset - swim.diveLift,
      )
      ..scale(animation.facing, 1)
      ..rotate(animation.lean)
      ..scale(animation.scaleX, animation.scaleY);
    BeanArt.paintBean(canvas, _paints);
    canvas.restore();

    // No waterline ring while the board is up: the ring says "this body is
    // cut off by the surface", and a bean standing on a board is not.
    if (submerged && !surfing) _renderWaterline(canvas, feet, sunk);
  }

  /// The board under a surfing bean.
  ///
  /// Five shapes, drawn only while [SwimState.isSurfing], so it costs nothing
  /// at all for the 99% of beans that are on dry land. Faded in with the
  /// submersion so it appears as the bean wades out rather than snapping into
  /// existence at the waterline.
  ///
  /// Rocked by the same [SwimState.wobble] the body uses, which is what keeps
  /// the two attached to each other.
  void _renderBoard(Canvas canvas, Offset feet) {
    final fade = swim.submersion.clamp(0.0, 1.0);
    final at = Offset(feet.dx + swim.wobble, feet.dy - swim.diveLift);
    final deck = Rect.fromCenter(
      center: at,
      width: size.y * _boardLength,
      height: size.x * _boardWidth,
    );
    final shape = RRect.fromRectAndRadius(
      deck,
      Radius.circular(deck.height / 2),
    );

    canvas
      // The water it pushes aside.
      ..drawOval(
        deck.inflate(4),
        Paint()..color = _waterlineColor.withValues(alpha: 0.30 * fade),
      )
      ..drawRRect(
        shape,
        Paint()..color = _boardColor.withValues(alpha: fade),
      )
      ..drawRRect(
        shape,
        Paint()
          ..color = _boardStripeColor.withValues(alpha: 0.55 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      )
      // The stringer, along the length of the deck.
      ..drawLine(
        Offset(deck.left + 5, at.dy),
        Offset(deck.right - 5, at.dy),
        Paint()
          ..color = _boardStripeColor.withValues(alpha: 0.7 * fade)
          ..strokeWidth = 1.6,
      )
      // The wake it leaves, as a smear off the tail.
      ..drawOval(
        Rect.fromCenter(
          center: at.translate(-deck.width * 0.62, 1),
          width: deck.width * 0.5,
          height: deck.height * 0.8,
        ),
        Paint()..color = _waterlineColor.withValues(alpha: 0.22 * fade),
      );
  }

  /// The ring of disturbed water where the body meets the surface.
  ///
  /// Without it the clipped body reads as a rendering glitch — a bean with its
  /// legs chopped off — rather than as a bean standing in water.
  void _renderWaterline(Canvas canvas, Offset feet, double sunk) {
    final at = Offset(feet.dx + swim.wobble, feet.dy - sunk);
    final width = BeanArt.bodyWidth * (0.92 + 0.10 * swim.submersion);
    canvas
      ..drawOval(
        Rect.fromCenter(center: at, width: width, height: width * 0.30),
        Paint()..color = _waterlineColor.withValues(alpha: 0.55),
      )
      ..drawOval(
        Rect.fromCenter(
          center: at,
          width: width * 1.24,
          height: width * 0.38,
        ),
        Paint()
          ..color = _waterlineColor.withValues(alpha: 0.34)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
  }

  void _renderShadow(Canvas canvas, Offset feet) {
    // No shadow on water. A contact shadow says "this body is resting on that
    // surface", which is the one thing a swimming bean is not doing.
    final afloat = 1 - swim.submersion;
    if (afloat <= 0.01) return;
    final scale = animation.shadowScale;
    _shadowPaint.color = _shadowColor.withValues(alpha: 0.30 * scale * afloat);
    BeanArt.paintShadow(canvas, feet, paint: _shadowPaint, scale: scale);
  }

  void _rebuildPaints() => _paints = BeanPaints(_appearance);
}
