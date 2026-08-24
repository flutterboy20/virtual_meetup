import 'dart:math' as math;

import 'package:client/core/theme.dart';
import 'package:flutter/material.dart';

/// The moving wallpaper behind the welcome screen.
///
/// Three soft colour clouds drifting over the page background, plus the same
/// faint grid the world's floor is drawn with. It exists to make the front
/// door feel like the room behind it: a phone screen full of flat navy says
/// "form", and this is not a form.
///
/// It paints, it does not tick. [phase] is a 0–1 loop handed down from the
/// one [AnimationController] the welcome screen owns, so the whole screen
/// animates off a single ticker instead of three.
class WelcomeBackdrop extends StatelessWidget {
  /// Creates the backdrop at [phase] of its loop.
  const WelcomeBackdrop({required this.phase, super.key});

  /// Where in the drift loop we are, 0–1.
  final double phase;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackdropPainter(phase),
        size: Size.infinite,
      ),
    );
  }
}

/// One drifting colour cloud.
class _Cloud {
  const _Cloud({
    required this.color,
    required this.origin,
    required this.radius,
    required this.travel,
    required this.offset,
  });

  final Color color;

  /// Where it sits, as a fraction of the screen.
  final Offset origin;

  /// Its radius, as a fraction of the screen's shortest side.
  final double radius;

  /// How far it wanders from [origin], as a fraction of the screen.
  final Offset travel;

  /// Its head start in the loop, so the three never move in lockstep.
  final double offset;
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.phase);

  final double phase;

  /// Zone accents from the world, so the lobby hints at the map's palette.
  static const List<_Cloud> _clouds = [
    _Cloud(
      color: Color(0xFF3E7F94),
      origin: Offset(0.18, 0.16),
      radius: 0.85,
      travel: Offset(0.10, 0.06),
      offset: 0,
    ),
    _Cloud(
      color: Color(0xFF8464C0),
      origin: Offset(0.86, 0.34),
      radius: 0.72,
      travel: Offset(-0.09, 0.08),
      offset: 0.37,
    ),
    _Cloud(
      color: Color(0xFF44987B),
      origin: Offset(0.42, 0.92),
      radius: 0.9,
      travel: Offset(0.07, -0.05),
      offset: 0.68,
    ),
  ];

  static const double _tau = 2 * math.pi;
  static const Color _gridInk = Color(0x0E8FD3E8);
  static const double _gridSpacing = 46;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = AppTheme.background);

    final short = size.shortestSide;
    for (final cloud in _clouds) {
      // Two sine waves a quarter-turn apart trace a slow ellipse, which reads
      // as drifting rather than as sliding back and forth along one line.
      final t = _tau * (phase + cloud.offset);
      final centre = Offset(
        (cloud.origin.dx + cloud.travel.dx * math.sin(t)) * size.width,
        (cloud.origin.dy + cloud.travel.dy * math.cos(t)) * size.height,
      );
      final radius = short * cloud.radius;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              cloud.color.withValues(alpha: 0.5),
              cloud.color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    _paintGrid(canvas, size);

    // A vignette pulls the eye back to the middle, where the button is.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [
            AppTheme.background.withValues(alpha: 0),
            AppTheme.background.withValues(alpha: 0.55),
          ],
        ).createShader(bounds),
    );
  }

  void _paintGrid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = _gridInk
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += _gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 0.0; y < size.height; y += _gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter oldDelegate) =>
      oldDelegate.phase != phase;
}
