import 'dart:math' as math;

import 'package:client/game/bean_appearance.dart';
import 'package:client/game/bean_art.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';

/// A strip of beans walking past, drawn with the game's own bean code.
///
/// This is the welcome screen's one piece of showing-rather-than-telling: it
/// answers "what is this thing?" before anybody reads a word of it. Two lanes
/// give it depth — the back lane is smaller, dimmer and slower — and every
/// bean bobs, leans and casts a shrinking shadow exactly like a real one.
///
/// It reuses [BeanArt], not a hand-drawn copy, for the same reason the setup
/// preview does: a lobby that advertises a character the world does not draw
/// is a lie with a very short shelf life.
///
/// Like the backdrop it is a pure painter — [phase] is a 0–1 loop from
/// the welcome screen's single ticker.
class BeanParade extends StatelessWidget {
  /// Creates the parade at [phase] of its loop.
  const BeanParade({required this.phase, super.key});

  /// Where in the walk loop we are, 0–1.
  final double phase;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _ParadePainter(phase), size: Size.infinite),
    );
  }
}

/// One bean in the parade and how it walks.
class _Walker {
  const _Walker({
    required this.color,
    required this.cosmetic,
    required this.laps,
    required this.start,
    required this.lane,
    this.facingLeft = false,
  });

  /// Body colour, from the same palette the setup screen offers.
  final Color color;

  /// What it wears.
  final PlayerCosmetic cosmetic;

  /// How many times it crosses the strip per loop. Whole numbers only, or
  /// the bean teleports when the loop wraps.
  final int laps;

  /// Its head start along the crossing, 0–1.
  final double start;

  /// `0` for the far lane, `1` for the near one.
  final int lane;

  /// Whether it walks right-to-left.
  final bool facingLeft;
}

class _ParadePainter extends CustomPainter {
  _ParadePainter(this.phase);

  final double phase;

  static const List<_Walker> _walkers = [
    _Walker(
      color: Color(0xFFB78BE8),
      cosmetic: PlayerCosmetic.headphones,
      laps: 1,
      start: 0.16,
      lane: 0,
    ),
    _Walker(
      color: Color(0xFF9BD35A),
      cosmetic: PlayerCosmetic.none,
      laps: 1,
      start: 0.5,
      lane: 0,
      facingLeft: true,
    ),
    _Walker(
      color: Color(0xFFF58FC7),
      cosmetic: PlayerCosmetic.cap,
      laps: 1,
      start: 0.84,
      lane: 0,
    ),
    _Walker(
      color: Color(0xFF54C5F8),
      cosmetic: PlayerCosmetic.cap,
      laps: 2,
      start: 0.55,
      lane: 1,
    ),
    _Walker(
      color: Color(0xFFF2B33D),
      cosmetic: PlayerCosmetic.none,
      laps: 2,
      start: 0.88,
      lane: 1,
      facingLeft: true,
    ),
    _Walker(
      color: Color(0xFF7ED9B6),
      cosmetic: PlayerCosmetic.headphones,
      laps: 2,
      start: 0.21,
      lane: 1,
    ),
  ];

  static const double _tau = 2 * math.pi;

  /// The colour of the panel behind the strip, used to fade its edges.
  static const Color _panel = Color(0xFF11212B);

  /// Bob cycles per lap. Whole, so the walk cycle wraps where the loop does.
  static const int _stepsPerLap = 13;

  static const double _bobHeight = 3.4;
  static const double _lean = 0.07;

  /// How tall a bean stands in each lane, as a fraction of the strip.
  static const List<double> _laneScale = [0.28, 0.39];
  static const List<double> _laneBaseline = [0.66, 0.95];
  static const List<double> _laneDim = [0.42, 0];

  static final Paint _shadowPaint = Paint()
    ..color = const Color(0xFF000000).withValues(alpha: 0.26);

  @override
  void paint(Canvas canvas, Size size) {
    _paintFloor(canvas, size);
    for (final walker in _walkers) {
      _paintWalker(canvas, size, walker);
    }
    _paintEdgeFade(canvas, size);
  }

  /// Softens both ends of the strip so beans walk out of view instead of
  /// being guillotined by the panel's corner.
  void _paintEdgeFade(Canvas canvas, Size size) {
    const stop = 0.12;
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          stops: const [0, stop, 1 - stop, 1],
          colors: [
            _panel,
            _panel.withValues(alpha: 0),
            _panel.withValues(alpha: 0),
            _panel,
          ],
        ).createShader(bounds),
    );
  }

  void _paintWalker(Canvas canvas, Size size, _Walker walker) {
    // Scaled off the strip's height so the parade shrinks with the screen
    // instead of overflowing a small phone.
    final scale = size.height * _laneScale[walker.lane] / BeanArt.bodyHeight;
    final margin = BeanArt.bodyWidth * scale;
    final span = size.width + margin * 2;

    final travelled = (phase * walker.laps + walker.start) % 1;
    final x = walker.facingLeft
        ? size.width + margin - travelled * span
        : travelled * span - margin;
    final baseline = size.height * _laneBaseline[walker.lane];

    final bobPhase = _tau * (phase * walker.laps * _stepsPerLap + walker.start);
    final lift = _bobHeight * math.sin(bobPhase).abs();
    // The shadow stays on the ground and shrinks as the body rises; a shadow
    // that hops with the bean reads as a trampoline, not a walk.
    final shadowScale = 1 - 0.35 * (lift / _bobHeight);

    // The far lane is washed towards the background rather than drawn with
    // opacity, which would need a save layer per bean.
    final body = Color.lerp(
      walker.color,
      const Color(0xFF0B1A22),
      _laneDim[walker.lane],
    )!;
    final paints = BeanPaints(
      BeanAppearance(
        bodyColor: body,
        cosmetic: walker.cosmetic,
        cosmeticColor: BeanAppearance.darken(body, 0.34),
      ),
    );

    canvas
      ..save()
      ..translate(x, baseline)
      ..scale(scale);
    BeanArt.paintShadow(
      canvas,
      Offset.zero,
      paint: _shadowPaint,
      scale: shadowScale,
    );
    canvas
      // Mirroring the whole bean is how the game faces one left, so the lean
      // below stays "forward" in both directions.
      ..scale(walker.facingLeft ? -1.0 : 1.0, 1)
      ..translate(0, -lift)
      ..rotate(_lean);
    BeanArt.paintBean(canvas, paints);
    canvas.restore();
  }

  /// The ground they walk on: a soft band, not a hard line, so the strip has
  /// no edge for the eye to catch on.
  void _paintFloor(Canvas canvas, Size size) {
    final band = Rect.fromLTRB(0, size.height * 0.52, size.width, size.height);
    canvas.drawRect(
      band,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00214454), Color(0x66214454)],
        ).createShader(band),
    );

    for (final lane in [_laneBaseline[0], _laneBaseline[1]]) {
      final y = size.height * lane;
      canvas.drawLine(
        Offset(size.width * 0.06, y),
        Offset(size.width * 0.94, y),
        Paint()
          ..shader =
              const LinearGradient(
                colors: [
                  Color(0x008FD3E8),
                  Color(0x338FD3E8),
                  Color(0x008FD3E8),
                ],
              ).createShader(
                Rect.fromLTWH(size.width * 0.06, y, size.width * 0.88, 1),
              )
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_ParadePainter oldDelegate) => oldDelegate.phase != phase;
}
