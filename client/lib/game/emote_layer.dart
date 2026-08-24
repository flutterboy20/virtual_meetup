import 'dart:ui';

import 'package:client/game/bean_component.dart';
import 'package:flame/components.dart';
import 'package:protocol/protocol.dart';

/// The reactions floating above people's heads.
///
/// A reaction is a *moment*, not a state. Nothing here is stored, nothing is
/// synchronised, and nothing is replayed: a bubble is born when a message
/// arrives, rises, fades, and is forgotten. Somebody who walks up ten seconds
/// later sees nothing, which is exactly right — they were not there.
///
/// The layer renders above beans and below the Flutter HUD, and it never
/// blocks input: emotes decorate the world, they are not things in it.
class EmoteLayer extends Component {
  /// Creates the layer.
  EmoteLayer({this.lifetime = defaultLifetime, this.maxBubbles = 48})
    : super(priority: 15);

  /// How long one bubble lives, in seconds.
  static const double defaultLifetime = 1.7;

  /// How far a bubble rises over its life, in world units.
  static const double rise = 42;

  /// How far above a bean's head a bubble starts, in world units.
  static const double lift = 16;

  /// Font size of the reaction glyph, in world units.
  static const double glyphSize = 26;

  /// Opacity steps a glyph is cached at.
  ///
  /// Same trick as the nametags: a laid-out [Paragraph] bakes its colour in,
  /// so a smooth fade would mean re-laying-out text every frame, per bubble.
  /// Eight steps is invisible to the eye and turns 60 layouts a second into
  /// eight over the bubble's whole life.
  static const int alphaSteps = 8;

  /// How long a bubble lives.
  final double lifetime;

  /// How many bubbles may exist at once.
  ///
  /// A cap, because a packed atrium at the end of a keynote is a genuine
  /// hundred-reactions-a-second event and the frame budget is not negotiable.
  /// The oldest is dropped first — the newest reaction is the one somebody is
  /// waiting to see.
  final int maxBubbles;

  final List<_Bubble> _bubbles = [];
  static final Map<int, Paragraph> _glyphCache = {};

  /// How many bubbles are on screen.
  int get count => _bubbles.length;

  /// Puts [emote] above [bean].
  void show(EmoteKind emote, BeanComponent bean) {
    if (_bubbles.length >= maxBubbles) _bubbles.removeAt(0);
    _bubbles.add(_Bubble(emote: emote, bean: bean));
  }

  /// Drops every bubble, e.g. when the connection resets.
  void clear() => _bubbles.clear();

  @override
  void update(double dt) {
    super.update(dt);
    for (var i = _bubbles.length - 1; i >= 0; i--) {
      final bubble = _bubbles[i]..age += dt;
      // A bubble holds a reference to a bean that can be removed at any
      // moment — its owner walked out of range mid-reaction. Dropping it when
      // the bean unmounts is what stops this layer keeping dead beans alive.
      if (bubble.age >= lifetime || !bubble.bean.isMounted) {
        _bubbles.removeAt(i);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    for (final bubble in _bubbles) {
      final t = (bubble.age / lifetime).clamp(0.0, 1.0);
      // Rises fast then eases out, and only fades over the last third: a
      // reaction that starts disappearing immediately reads as a glitch.
      final lifted = rise * (1 - (1 - t) * (1 - t));
      final alpha = t < 0.66 ? 1.0 : 1 - (t - 0.66) / 0.34;
      final step = (alpha * alphaSteps).ceil().clamp(1, alphaSteps);
      final paragraph = _glyphFor(bubble.emote, step);

      canvas.drawParagraph(
        paragraph,
        Offset(
          bubble.bean.position.x - paragraph.width / 2,
          bubble.bean.position.y - bubble.bean.size.y - lift - lifted,
        ),
      );
    }
  }

  static Paragraph _glyphFor(EmoteKind emote, int step) {
    final key = emote.index * (alphaSteps + 1) + step;
    return _glyphCache.putIfAbsent(key, () {
      final builder =
          ParagraphBuilder(
              ParagraphStyle(fontSize: glyphSize, textAlign: TextAlign.center),
            )
            ..pushStyle(
              TextStyle(
                color: const Color(
                  0xFFFFFFFF,
                ).withValues(alpha: step / alphaSteps),
              ),
            )
            ..addText(emote.glyph);
      return builder.build()
        ..layout(const ParagraphConstraints(width: glyphSize * 2));
    });
  }
}

/// One reaction in flight.
class _Bubble {
  _Bubble({required this.emote, required this.bean});

  final EmoteKind emote;
  final BeanComponent bean;
  double age = 0;
}
