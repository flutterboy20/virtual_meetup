import 'dart:ui';

import 'package:client/game/world_layout.dart';
import 'package:flame/components.dart';

/// Which line the stage screen is showing, and how far through a swap it is.
///
/// Pure maths: no Flame, no `Canvas`, no `Paragraph`. That is what lets the
/// cycling rule — advance on the interval, wrap at the end, hold still on a
/// one-line list, crossfade between the two — be unit-tested without a game
/// loop, which is the same trade `BeanAnimation` and `JoystickFade` make.
class LineCycler {
  /// Creates a cycler over [lines].
  ///
  /// An empty list is not an error: it is a screen with nothing to say, and
  /// [current] answers `null` rather than throwing on a config file somebody
  /// emptied.
  LineCycler({
    required List<String> lines,
    this.interval = 6,
    this.fadeDuration = 0.4,
  }) : lines = List.unmodifiable(lines);

  /// The lines to cycle through, in the order they were written.
  final List<String> lines;

  /// How long one line is held, in seconds — the fade included.
  final double interval;

  /// How long the crossfade between two lines takes, in seconds.
  final double fadeDuration;

  double _elapsed = 0;
  int _index = 0;
  int _previousIndex = 0;
  double _fade = 1;

  /// The line on screen now, or `null` if there is nothing to show.
  String? get current => lines.isEmpty ? null : lines[_index];

  /// The line being faded out, or `null` if no swap is in progress.
  String? get outgoing {
    if (lines.isEmpty || _fade >= 1 || _previousIndex == _index) return null;
    return lines[_previousIndex];
  }

  /// How far the incoming line has faded in, from 0 to 1.
  ///
  /// Monotonic across a swap: it starts at 0 the instant the line changes and
  /// climbs to 1 over [fadeDuration], and it never goes backwards in between.
  /// A fade that dipped would read as the screen flickering.
  double get fade => _fade;

  /// How many times the line has changed.
  ///
  /// Exposed so a test can say "it advanced" without comparing strings, which
  /// would give a false pass on a list with a repeated line in it.
  int get advances => _advances;

  int _advances = 0;

  /// Advances the cycler by [dt] seconds.
  void update(double dt) {
    if (dt <= 0) return;
    // One line has nothing to cross-fade to. Holding still is the correct
    // behaviour and it is also the cheap one: no timer, no fade, no swap.
    if (lines.length < 2) {
      _fade = 1;
      return;
    }

    _elapsed += dt;
    if (_elapsed >= interval) {
      _elapsed -= interval;
      _previousIndex = _index;
      _index = (_index + 1) % lines.length;
      _fade = 0;
      _advances++;
    }

    if (_fade < 1) {
      _fade = fadeDuration <= 0
          ? 1
          : (_fade + dt / fadeDuration).clamp(0.0, 1.0);
    }
  }
}

/// The hall's screen, saying something different every few seconds.
///
/// A **component**, not part of the furniture picture, and that is the whole
/// reason this file exists: a display list is a recording, and a recorded
/// sentence never changes. Everything else on the stage — the apron, the
/// backdrop panels, the dark screen this draws on top of — is still baked in
/// `ZoneProps.paintHall`, where it belongs.
///
/// **One [Paragraph] per line, built on the swap and cached.** Text layout
/// sixty times a second to draw words that change every six seconds is the
/// single easiest way to make a screen cost more than the room it is in. The
/// crossfade rides on `saveLayer`-free alpha: two paragraphs, each drawn once,
/// each at its own opacity.
class StageScreenComponent extends PositionComponent {
  /// Creates the screen over [WorldLayout.stageScreen], showing [lines].
  StageScreenComponent({required List<String> lines})
    : cycler = LineCycler(lines: lines),
      // Above the furniture (-20) and below the beans (0): the screen is a
      // thing on the back wall, and a bean standing in front of it must be in
      // front of it.
      super(priority: -10);

  /// What the screen is saying, and when it changes.
  ///
  /// Replaced wholesale by [setLines] rather than mutated, because a cycler
  /// is a position in a script and a new script has no matching position in
  /// the old one.
  LineCycler cycler;

  /// How big the text is, in world units.
  static const double fontSize = 15;

  /// The lit ink on the screen.
  static const Color ink = Color(0xFFFFE9B0);

  /// The screen's own glow behind the words.
  static const Color wash = Color(0xFFFFD9A0);

  static final Map<String, Paragraph> _cache = {};

  final Paint _washPaint = Paint();

  /// Puts a new programme on the screen, from the moderator.
  ///
  /// Starts it from the top rather than trying to hold the old position: the
  /// lines are a script somebody wrote in an order they meant, and resuming
  /// one at line four because the last one was on line four is nobody's idea
  /// of what they typed.
  void setLines(List<String> lines) {
    if (_sameLines(cycler.lines, lines)) return;
    cycler = LineCycler(
      lines: lines,
      interval: cycler.interval,
      fadeDuration: cycler.fadeDuration,
    );
    // The paragraph cache is keyed on the text, so lines nobody will show
    // again would sit in it for the life of the tab. Rare event, cheap
    // clear, no unbounded static map.
    _cache.clear();
  }

  static bool _sameLines(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    cycler.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final line = cycler.current;
    if (line == null) return;

    final screen = _screenRect;
    final fade = cycler.fade;

    // The screen brightening as a new line lands. Flat alpha on a rectangle
    // — no `MaskFilter`, which on CanvasKit is a real raster cost across an
    // area this size for a glow nobody would name.
    _washPaint.color = wash.withValues(alpha: 0.10 + 0.06 * fade);
    canvas.drawRRect(
      RRect.fromRectAndRadius(screen.deflate(5), const Radius.circular(3)),
      _washPaint,
    );

    final outgoing = cycler.outgoing;
    if (outgoing != null) {
      _drawLine(canvas, screen, outgoing, 1 - fade);
    }
    _drawLine(canvas, screen, line, fade);
  }

  void _drawLine(Canvas canvas, Rect screen, String text, double alpha) {
    if (alpha <= 0.01) return;
    final paragraph = _paragraphFor(text, screen.width - _inset * 2);
    // Alpha through `saveLayer` rather than through a re-laid-out paragraph:
    // the colour is baked into a `Paragraph`, so fading one by rebuilding it
    // would be a text layout per frame — the exact cost this class exists to
    // avoid. One layer over a 232x52 rectangle, twice, only while a swap is
    // actually in progress.
    final fading = alpha < 0.99;
    if (fading) {
      canvas.saveLayer(
        screen,
        Paint()..color = const Color(0xFF000000).withValues(alpha: alpha),
      );
    }
    canvas.drawParagraph(
      paragraph,
      Offset(
        screen.left + _inset,
        screen.center.dy - paragraph.height / 2,
      ),
    );
    if (fading) canvas.restore();
  }

  static const double _inset = 12;

  static Rect get _screenRect => Rect.fromLTRB(
    WorldLayout.stageScreen.left,
    WorldLayout.stageScreen.top,
    WorldLayout.stageScreen.right,
    WorldLayout.stageScreen.bottom,
  );

  /// Lays [text] out once and keeps it.
  ///
  /// Keyed on the text rather than on an index, so a config reload that
  /// reorders the list reuses what it already laid out. The cache is bounded
  /// by the length of the config's line list, which is a hand-written array.
  static Paragraph _paragraphFor(String text, double width) =>
      _cache.putIfAbsent('$width|$text', () {
        final builder =
            ParagraphBuilder(
                ParagraphStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  ellipsis: '…',
                ),
              )
              ..pushStyle(TextStyle(color: ink, letterSpacing: 0.5))
              ..addText(text);
        return builder.build()..layout(ParagraphConstraints(width: width));
      });
}
