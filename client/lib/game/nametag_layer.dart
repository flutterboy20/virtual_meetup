import 'dart:ui';

import 'package:client/core/app_fonts.dart';
import 'package:client/game/bean_component.dart';
import 'package:client/game/bot_component.dart';
import 'package:client/game/floor_component.dart';
import 'package:client/game/remote_players.dart';
import 'package:flame/components.dart';

/// The names floating above nearby players.
///
/// Three rules make this readable in a crowd rather than in a demo:
///
/// **A tighter radius than the network's.** The server sends you everybody in
/// a 3×3 grid block — up to ~480 units away — because interest range has to
/// exceed the screen or people would pop into existence at its edge. Naming
/// all of them would put text on beans halfway across the map. Names fade in
/// at [fadeRadius] — two floor tiles — and are solid inside [fullRadius],
/// one tile: close enough that you have walked up to the person.
///
/// **A cap on how many are drawn.** Forty people packed into the atrium at
/// spawn is the real case, and forty overlapping labels is a grey smear that
/// hides the beans underneath. Only the [maxTags] nearest get a tag; the rest
/// simply have none, which is honest — you cannot read a name in a scrum in
/// real life either.
///
/// **Distance-based fade, not a hard cut.** A tag that blinks on at exactly
/// 260 units draws the eye to the boundary rather than to the person.
///
/// Your **own** name is the exception to all three rules: given [localBean]
/// and [localName] it is drawn every frame, at full opacity, outside the cap.
/// The rules above exist to stop other people's names becoming clutter, and
/// none of them apply to the one bean you are always looking for.
class NametagLayer extends Component {
  /// Creates the layer.
  NametagLayer({
    required this.remotePlayers,
    required this.localPosition,
    this.fullRadius = defaultFullRadius,
    this.fadeRadius = defaultFadeRadius,
    this.maxTags = defaultMaxTags,
    this.localBean,
    this.localName = '',
    this.bots = const [],
  }) : super(priority: 20);

  /// Inside this distance a name is fully opaque, in world units.
  ///
  /// One floor tile — [FloorComponent.gridStep] — so a name is solid only for
  /// somebody standing right next to you.
  static const double defaultFullRadius = FloorComponent.gridStep;

  /// Beyond this distance a name is gone, in world units.
  ///
  /// Two tiles. Names are for the person you have walked up to, not for the
  /// room: past two tiles the tag says nothing you were going to act on and
  /// costs a label over somebody else's head.
  static const double defaultFadeRadius = FloorComponent.gridStep * 2;

  /// How many names may be drawn at full detail at once.
  static const int defaultMaxTags = 10;

  /// How far above a bean's head the tag sits, in world units.
  static const double tagLift = 12;

  /// Where the tag's alpha is rounded to, as a number of steps.
  ///
  /// A [Paragraph] bakes its colour in, so fading one means rebuilding it.
  /// Rebuilding every tag every frame would be text layout at 60Hz; rounding
  /// the alpha to eight steps means a rebuild only when a tag visibly
  /// changes, which is a handful per second across the whole crowd.
  static const int alphaSteps = 8;

  static const Color _ink = Color(0xFFEAF6FB);
  static const Color _backdrop = Color(0xFF0B1A22);

  /// Where everybody else is.
  final RemotePlayers remotePlayers;

  /// Where the local bean is, read fresh every frame.
  final Vector2 Function() localPosition;

  /// Inside this distance a name is fully opaque, in world units.
  final double fullRadius;

  /// Beyond this distance a name is gone, in world units.
  final double fadeRadius;

  /// How many names may be drawn at once.
  final int maxTags;

  /// Your own bean, if its name should be shown, or `null` if it should not.
  final BeanComponent? localBean;

  /// The name to draw over [localBean].
  ///
  /// Mutable, alone among this layer's fields, because it is the one that a
  /// moderator can change while the game is running: a muted player has to
  /// see the placeholder over their own head, or they cannot tell a mute from
  /// a bug. Written by `ConferenceGame` when a rename arrives; read fresh
  /// every frame, so no rebuild is needed.
  String localName;

  /// The beans standing around who are not players.
  ///
  /// Named by **exactly the same rules** as everybody else — same radii, same
  /// fade, same cap, same paint. That is the point: a bot with a quieter or
  /// differently-styled tag is a bot with a label on it, and the whole reason
  /// these beans exist is to make the room feel populated.
  final List<BotComponent> bots;

  /// What a bot's cache key starts with.
  ///
  /// Bots have no id of their own — they are scenery, and the server has
  /// never heard of them — so their tags are keyed by roster index behind a
  /// prefix no player id can have.
  static const String botTagPrefix = 'bot:';

  /// The id the local player's own tag is cached under.
  ///
  /// Not a real player id and deliberately not one the server could ever
  /// mint, so it can never collide with a remote player's entry in the cache.
  static const String localTagId = '__you__';

  final Map<String, _Tag> _tags = {};
  final List<VisibleTag> _candidates = [];

  @override
  void render(Canvas canvas) {
    for (final candidate in visibleTags()) {
      _tagFor(candidate.id, candidate.name).render(
        canvas,
        candidate.bean,
        candidate.alpha,
      );
    }
    final me = localTag();
    if (me != null) {
      _tagFor(me.id, me.name).render(canvas, me.bean, me.alpha);
    }
  }

  /// Your own tag, or `null` if this layer was not given one.
  ///
  /// Always full opacity and never counted against [maxTags]: it is not
  /// competing for attention with the crowd, it *is* the thing you look for
  /// in one. Drawn after everybody else's so a packed atrium cannot bury it.
  VisibleTag? localTag() {
    final bean = localBean;
    if (bean == null || localName.isEmpty) return null;
    return VisibleTag(
      id: localTagId,
      name: localName,
      bean: bean,
      distanceSquared: 0,
      alpha: 1,
    );
  }

  /// Who gets a tag right now, nearest first, with the opacity to draw it at.
  ///
  /// Public because it is the whole readability rule — the radius, the cap
  /// and the fade — and a rule that can only be checked by looking at the
  /// screen is a rule nobody checks in a crowd.
  ///
  /// The returned list is reused between calls: this runs every frame, and
  /// allocating a list per frame per crowd is exactly the kind of garbage
  /// that shows up as a stutter rather than as a slowdown.
  List<VisibleTag> visibleTags() {
    _candidates.clear();
    final me = localPosition();
    final fade = fadeRadius * fadeRadius;

    for (final view in remotePlayers.views) {
      final dx = view.bean.position.x - me.x;
      final dy = view.bean.position.y - me.y;
      final distance = dx * dx + dy * dy;
      if (distance > fade) continue;
      _candidates.add(
        VisibleTag(
          id: view.id,
          name: view.name,
          bean: view.bean,
          distanceSquared: distance,
          alpha: _alphaFor(distance),
        ),
      );
    }

    for (var i = 0; i < bots.length; i++) {
      final bot = bots[i];
      final name = bot.brain.spec.name;
      if (name.isEmpty) continue;
      final dx = bot.position.x - me.x;
      final dy = bot.position.y - me.y;
      final distance = dx * dx + dy * dy;
      if (distance > fade) continue;
      _candidates.add(
        VisibleTag(
          // Prefixed so it can never collide with a server-issued player id,
          // which is what would let a bot's cached tag be drawn over a
          // person.
          id: '$botTagPrefix$i',
          name: name,
          bean: bot,
          distanceSquared: distance,
          alpha: _alphaFor(distance),
        ),
      );
    }

    _candidates.sort((a, b) => a.distanceSquared.compareTo(b.distanceSquared));
    if (_candidates.length > maxTags) {
      _candidates.removeRange(maxTags, _candidates.length);
    }

    // Forget tags for people who have walked away, so the cache is the size
    // of the crowd around you and not of everybody you have ever stood near.
    if (_tags.length > maxTags * 3) {
      final keep = _candidates.map((candidate) => candidate.id).toSet()
        ..add(localTagId);
      _tags.removeWhere((id, _) => !keep.contains(id));
    }
    return _candidates;
  }

  /// Rounds a distance to one of [alphaSteps] opacity levels.
  double _alphaFor(double distanceSquared) {
    final full = fullRadius * fullRadius;
    if (distanceSquared <= full) return 1;
    final fade = fadeRadius * fadeRadius;
    final t = 1 - (distanceSquared - full) / (fade - full);
    return (t * alphaSteps).ceilToDouble() / alphaSteps;
  }

  _Tag _tagFor(String id, String name) {
    final existing = _tags[id];
    if (existing != null && existing.name == name) return existing;
    final tag = _Tag(name);
    _tags[id] = tag;
    return tag;
  }
}

/// One name the layer is drawing this frame.
class VisibleTag {
  /// Creates a tag.
  VisibleTag({
    required this.id,
    required this.name,
    required this.bean,
    required this.distanceSquared,
    required this.alpha,
  });

  /// Whose name this is.
  final String id;

  /// The text to draw.
  final String name;

  /// The bean to draw it above.
  final BeanComponent bean;

  /// How far away they are, squared.
  final double distanceSquared;

  /// How opaque the tag is, from just above 0 to 1.
  final double alpha;
}

/// One player's name, with its laid-out text cached per opacity step.
class _Tag {
  _Tag(this.name);

  /// Widest a tag may get before the name wraps, in world units.
  static const double maxWidth = 200;

  /// The name this tag was built for. A rename rebuilds the tag.
  final String name;

  final Map<int, Paragraph> _byAlpha = {};

  void render(Canvas canvas, BeanComponent bean, double alpha) {
    if (alpha <= 0) return;
    final step = (alpha * NametagLayer.alphaSteps).round();
    final paragraph = _byAlpha.putIfAbsent(step, () => _build(step));

    // The paragraph is laid out to its own width, so its box is the text's
    // box: centring one centres the other. Laying out to a fixed 200 and
    // measuring the text instead put the slab under a centred line of text
    // that was not where the slab was.
    final width = paragraph.width;
    final left = bean.position.x - width / 2;
    final top =
        bean.position.y - bean.size.y - NametagLayer.tagLift - paragraph.height;

    // A slab behind the text, because a light name over a light bean over a
    // light floor is unreadable exactly when the room is busiest.
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left - 5, top - 2, width + 10, paragraph.height + 4),
          const Radius.circular(6),
        ),
        Paint()..color = NametagLayer._backdrop.withValues(alpha: 0.62 * alpha),
      )
      ..drawParagraph(paragraph, Offset(left, top));
  }

  Paragraph _build(int step) {
    final alpha = step / NametagLayer.alphaSteps;
    Paragraph layout(double width) {
      final builder =
          ParagraphBuilder(
              ParagraphStyle(
                fontFamily: AppFonts.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                textAlign: TextAlign.center,
              ),
            )
            ..pushStyle(
              TextStyle(color: NametagLayer._ink.withValues(alpha: alpha)),
            )
            ..addText(name);
      return builder.build()..layout(ParagraphConstraints(width: width));
    }

    // Measure, then lay out again to the measured width. A fraction of a
    // pixel short wraps the last letter onto its own line, hence the ceil.
    final measured = layout(maxWidth).maxIntrinsicWidth.ceilToDouble();
    return layout(measured.clamp(0.0, maxWidth));
  }
}
