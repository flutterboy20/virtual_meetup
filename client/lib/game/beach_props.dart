import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/world_palette.dart';
import 'package:client/game/beach_layout.dart';
import 'package:protocol/protocol.dart';

/// Everything standing on the beach, drawn.
///
/// The beach's answer to `ZoneProps`, and recorded once into the furniture
/// picture exactly like it. **The draw list and the collision list come from
/// the same constants** — every rectangle and circle here is read out of
/// [BeachLayout], which is also what `BeachLayout.fixedObstacles` is built
/// from.
abstract final class BeachProps {
  /// The rounding every prop shares, so the beach looks like one set.
  static const Radius corner = Radius.circular(6);

  /// The board's stripe colour, and the hint bubble's fill.
  ///
  /// Shared with `HintBeanComponent` so the secret's two halves look like one
  /// set — the same reason every other colour on this map is a constant here
  /// rather than typed twice.
  static const Color boardStripe = Color(0xFF2F9E8F);

  static const Color _canvasWhite = Color(0xFFF6F1E4);
  static const Color _ember = Color(0xFFFF8A3D);
  static const Color _ink = Color(0xFF3A2210);

  /// The four umbrella canopy colours, so a row of them is not one colour.
  static const List<Color> umbrellaColors = [
    Color(0xFFE2574C),
    Color(0xFF2F9E8F),
    Color(0xFFEFA92F),
    Color(0xFF5C7FD1),
  ];

  /// The four towel colours, in the same spirit.
  static const List<Color> towelColors = [
    Color(0xFF4C7BE2),
    Color(0xFFE2578F),
    Color(0xFF41A85F),
    Color(0xFFE8B23A),
  ];

  /// Draws the whole beach: sea landmarks first, then sand, then boardwalk.
  ///
  /// Bottom of the map first, top last. There is no y-sorting anywhere in
  /// this renderer — see `FurnitureComponent` — so the draw order *is* the
  /// depth, and drawing the far things first is the whole of what makes an
  /// umbrella sit in front of a shack rather than behind it.
  static void paintAll(Canvas canvas) {
    paintSea(canvas);
    paintSand(canvas);
    paintBoardwalk(canvas);
  }

  // ---- Sea ----------------------------------------------------------------

  /// The three landmarks in the water: sandbar, buoys, raft.
  ///
  /// Under the live water, not over it: `WaterComponent` renders at priority
  /// -27 and furniture at -20, so these are drawn *above* the surface. They
  /// are things floating on it, which is exactly right for a raft and a buoy,
  /// and the sandbar gets away with it because it is drawn as something seen
  /// **through** the water — pale, low-contrast, no outline.
  static void paintSea(Canvas canvas) {
    _paintSandbar(canvas);
    _paintBuoys(canvas);
    _paintRaft(canvas);
  }

  static void _paintSandbar(Canvas canvas) {
    final bar = rect(BeachLayout.sandbar);
    final sand = WorldPalette.of(WorldZone.beachSand).floor;
    canvas
      // Two ovals rather than a rectangle: a sandbar has no edges, it has a
      // middle that shallows out. The outer one is barely there.
      ..drawOval(
        bar.inflate(16),
        Paint()..color = sand.withValues(alpha: 0.13),
      )
      ..drawOval(bar, Paint()..color = sand.withValues(alpha: 0.24))
      ..drawOval(
        bar.deflate(34),
        Paint()..color = sand.withValues(alpha: 0.30),
      );
  }

  static void _paintBuoys(Canvas canvas) {
    for (final buoy in BeachLayout.buoys) {
      final at = Offset(buoy.x, buoy.y);
      canvas
        // The disturbed ring of water around a floating thing.
        ..drawCircle(
          at,
          buoy.radius + 7,
          Paint()
            ..color = _canvasWhite.withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        )
        ..drawCircle(at, buoy.radius, Paint()..color = _ember)
        ..drawCircle(
          at,
          buoy.radius * 0.55,
          Paint()..color = _canvasWhite,
        );
    }
  }

  static void _paintRaft(Canvas canvas) {
    final deck = rect(BeachLayout.raft);
    final timber = WorldPalette.of(WorldZone.beachBoardwalk).floor;

    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(deck.inflate(5), corner),
        Paint()..color = _canvasWhite.withValues(alpha: 0.26),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(deck, corner),
        Paint()..color = timber,
      );

    // Planks along the raft, so it is not a brown rectangle.
    final joint = Paint()
      ..color = shade(timber, -0.28)
      ..strokeWidth = 2;
    for (var y = deck.top + 15; y < deck.bottom; y += 15) {
      canvas.drawLine(
        Offset(deck.left + 4, y),
        Offset(deck.right - 4, y),
        joint,
      );
    }

    // The oil drums it floats on, showing at the corners.
    final drum = Paint()..color = shade(timber, -0.34);
    for (final at in [
      deck.topLeft,
      deck.topRight,
      deck.bottomLeft,
      deck.bottomRight,
    ]) {
      canvas.drawCircle(at, 9, drum);
    }
  }

  // ---- Sand ---------------------------------------------------------------

  /// The towels, the umbrellas, the volleyball net, the dance floor, the
  /// board.
  static void paintSand(Canvas canvas) {
    _paintTowels(canvas);
    _paintNet(canvas);
    _paintDanceFloor(canvas);
    _paintUmbrellas(canvas);
    // Last, so it stands *in front of* the easternmost umbrella rather than
    // behind it. Draw order is depth here — see [paintAll].
    paintBigBoard(canvas);
  }

  /// The surfboard stood upright in the sand at the east end of the beach.
  ///
  /// Eight shapes, recorded once into the furniture picture like everything
  /// else on this map. It never animates: a prop that reacted to a tap would
  /// need an animation state living outside the recording, and the toast
  /// already confirms the tap.
  ///
  /// Public because the bench measures it, and because a test asserts it sits
  /// where [BeachLayout.bigBoard] says it does.
  static void paintBigBoard(Canvas canvas) {
    final board = rect(BeachLayout.bigBoard);
    final nose = Radius.circular(board.width / 2);
    final shape = RRect.fromRectAndRadius(board, nose);
    final timber = WorldPalette.of(WorldZone.beachBoardwalk).floor;

    canvas
      // Leant into the sand, so it throws a shadow the way the umbrellas do.
      ..drawRRect(
        RRect.fromRectAndRadius(board.translate(11, 9), nose),
        Paint()..color = const Color(0x33000000),
      )
      // The little trench it is planted in.
      ..drawOval(
        Rect.fromCenter(
          center: board.bottomCenter,
          width: board.width * 1.5,
          height: 14,
        ),
        Paint()..color = shade(sandFloor, -0.18),
      )
      ..drawRRect(shape, Paint()..color = _canvasWhite)
      ..drawRRect(
        shape,
        Paint()
          ..color = shade(boardStripe, -0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      )
      // Two racing stripes down the deck, which is what makes it read as a
      // board and not as a paddle.
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            board.center.dx - 9,
            board.top + 18,
            board.center.dx - 2,
            board.bottom - 18,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = boardStripe,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            board.center.dx + 2,
            board.top + 18,
            board.center.dx + 9,
            board.bottom - 18,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = _ember,
      )
      // The stringer: the seam a real board is built around.
      ..drawLine(
        Offset(board.center.dx, board.top + 10),
        Offset(board.center.dx, board.bottom - 10),
        Paint()
          ..color = shade(timber, -0.1)
          ..strokeWidth = 1.4,
      )
      // The fin, poking out at the tail.
      ..drawPath(
        Path()
          ..moveTo(board.right - 4, board.bottom - 26)
          ..lineTo(board.right + 13, board.bottom - 12)
          ..lineTo(board.right - 4, board.bottom - 8)
          ..close(),
        Paint()..color = shade(boardStripe, -0.32),
      )
      // The leash, coiled at its foot.
      ..drawCircle(
        board.bottomCenter.translate(-16, -2),
        9,
        Paint()
          ..color = _ink.withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      )
      ..drawCircle(
        board.bottomCenter.translate(-16, -2),
        4.5,
        Paint()
          ..color = _ink.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
  }

  static void _paintTowels(Canvas canvas) {
    for (var i = 0; i < BeachLayout.towels.length; i++) {
      final towel = rect(BeachLayout.towels[i]);
      final color = towelColors[i % towelColors.length];
      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(towel, const Radius.circular(4)),
          Paint()..color = color,
        )
        // Two stripes across it, which is what a towel is.
        ..drawRect(
          Rect.fromLTRB(
            towel.left,
            towel.top + 12,
            towel.right,
            towel.top + 20,
          ),
          Paint()..color = _canvasWhite.withValues(alpha: 0.7),
        )
        ..drawRect(
          Rect.fromLTRB(
            towel.left,
            towel.bottom - 20,
            towel.right,
            towel.bottom - 12,
          ),
          Paint()..color = _canvasWhite.withValues(alpha: 0.7),
        );
    }
  }

  static void _paintUmbrellas(Canvas canvas) {
    for (var i = 0; i < BeachLayout.umbrellas.length; i++) {
      final pole = BeachLayout.umbrellas[i];
      final at = Offset(pole.x, pole.y);
      final color = umbrellaColors[i % umbrellaColors.length];

      // The shade it throws, offset like every other prop's shadow.
      canvas.drawOval(
        Rect.fromCenter(
          center: at.translate(10, 14),
          width: BeachLayout.umbrellaRadius * 2,
          height: BeachLayout.umbrellaRadius * 1.5,
        ),
        Paint()..color = const Color(0x2E000000),
      );

      // The canopy, as alternating panels off one centre.
      const panels = 8;
      for (var panel = 0; panel < panels; panel++) {
        final start = panel * 2 * math.pi / panels;
        canvas.drawArc(
          Rect.fromCircle(center: at, radius: BeachLayout.umbrellaRadius),
          start,
          2 * math.pi / panels,
          true,
          Paint()..color = panel.isEven ? color : _canvasWhite,
        );
      }

      canvas
        ..drawCircle(
          at,
          BeachLayout.umbrellaRadius,
          Paint()
            ..color = shade(color, -0.25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        )
        ..drawCircle(at, BeachLayout.umbrellaPoleRadius, Paint()..color = _ink);
    }
  }

  static void _paintNet(Canvas canvas) {
    final first = BeachLayout.netPosts.first;
    final last = BeachLayout.netPosts.last;
    final top = Offset(first.x, first.y);
    final bottom = Offset(last.x, last.y);
    final timber = WorldPalette.of(WorldZone.beachBoardwalk).floor;

    // The mesh: a band between the posts, hatched. Drawn and not collided —
    // see `BeachLayout.netPosts`.
    final band = Rect.fromLTRB(
      top.dx - 13,
      top.dy,
      bottom.dx + 13,
      bottom.dy,
    );
    canvas.drawRect(
      band,
      Paint()..color = _canvasWhite.withValues(alpha: 0.34),
    );

    final mesh = Paint()
      ..color = _canvasWhite.withValues(alpha: 0.75)
      ..strokeWidth = 1.2;
    for (var y = band.top; y <= band.bottom; y += 11) {
      canvas.drawLine(Offset(band.left, y), Offset(band.right, y), mesh);
    }
    for (var x = band.left; x <= band.right; x += 11) {
      canvas.drawLine(Offset(x, band.top), Offset(x, band.bottom), mesh);
    }

    for (final post in BeachLayout.netPosts) {
      canvas.drawCircle(
        Offset(post.x, post.y),
        BeachLayout.netPostRadius,
        Paint()..color = shade(timber, -0.2),
      );
    }
  }

  /// The checkered dance floor outside the pub.
  ///
  /// Static, like everything else in the picture. What *moves* over it is
  /// `DiscoComponent` — the record, the mirrorball and the light sweep — for
  /// the same reason the water is a component and the pool is not: a display
  /// list is a recording, and a recorded light sweep is a stripe that never
  /// moves again.
  static void _paintDanceFloor(Canvas canvas) {
    final floor = rect(BeachLayout.danceFloor);
    const tile = 20.0;

    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(floor.inflate(6), corner),
        Paint()..color = _ink.withValues(alpha: 0.22),
      )
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(floor, corner));

    // The checkers. Two tones off the boardwalk timber rather than black and
    // white: a chessboard on a beach reads as a chessboard.
    final timber = WorldPalette.of(WorldZone.beachBoardwalk).floor;
    final light = Paint()..color = shade(timber, 0.34);
    final dark = Paint()..color = shade(timber, -0.06);
    var row = 0;
    for (var y = floor.top; y < floor.bottom; y += tile) {
      var col = 0;
      for (var x = floor.left; x < floor.right; x += tile) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, tile, tile),
          (row + col).isEven ? light : dark,
        );
        col++;
      }
      row++;
    }

    canvas
      ..restore()
      ..drawRRect(
        RRect.fromRectAndRadius(floor, corner),
        Paint()
          ..color = shade(timber, -0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
  }

  /// The DJ booth in front of the pub: a plinth, two decks and a mixer.
  ///
  /// Drawn and **not** collided — see `BeachLayout.djBooth`. The DJ standing
  /// behind it is a bot, which is what stops this being a box with nobody in
  /// it.
  static void _paintDjBooth(Canvas canvas) {
    final booth = rect(BeachLayout.djBooth);
    final timber = WorldPalette.of(WorldZone.beachBoardwalk).floor;

    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(booth.translate(3, 4), corner),
        Paint()..color = const Color(0x2E000000),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(booth, corner),
        Paint()..color = shade(timber, -0.24),
      )
      // The top surface the gear sits on.
      ..drawRRect(
        RRect.fromRectAndRadius(booth.deflate(5), const Radius.circular(3)),
        Paint()..color = const Color(0xFF17242C),
      );

    // Two decks and a mixer between them. The record that *turns* is drawn by
    // `DiscoComponent` over the left deck; this is the platter under it.
    for (final at in [
      booth.centerLeft.translate(24, 0),
      booth.centerRight.translate(-24, 0),
    ]) {
      canvas
        ..drawCircle(at, 11, Paint()..color = shade(timber, 0.20))
        ..drawCircle(at, 3, Paint()..color = _ember);
    }
    final mixer = Rect.fromCenter(
      center: booth.center,
      width: 22,
      height: 16,
    );
    canvas.drawRect(mixer, Paint()..color = shade(timber, 0.06));
    for (var i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(mixer.left + 5 + i * 6, mixer.top + 4),
        Offset(mixer.left + 5 + i * 6, mixer.bottom - 4),
        Paint()
          ..color = _canvasWhite.withValues(alpha: 0.6)
          ..strokeWidth = 1.6,
      );
    }
  }

  // ---- Boardwalk ----------------------------------------------------------

  /// The shacks and the deck rail.
  static void paintBoardwalk(Canvas canvas) {
    _paintShacks(canvas);
    _paintRail(canvas);
    // After the rail, so the booth stands in front of it rather than behind:
    // draw order is depth here — see [paintAll].
    _paintDjBooth(canvas);
  }

  static void _paintShacks(Canvas canvas) {
    final colors = WorldPalette.of(WorldZone.beachBoardwalk);

    for (var i = 0; i < BeachLayout.shacks.length; i++) {
      final shack = rect(BeachLayout.shacks[i].rect);
      final accent = umbrellaColors[(i + 1) % umbrellaColors.length];

      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(shack.translate(3, 4), corner),
          Paint()..color = const Color(0x2E000000),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(shack, corner),
          Paint()..color = shade(colors.floor, -0.12),
        )
        // The serving hatch: the one part of a shack a walking player reads.
        ..drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              shack.left + 14,
              shack.bottom - 42,
              shack.right - 14,
              shack.bottom - 10,
            ),
            corner,
          ),
          Paint()..color = const Color(0xFF17242C),
        );

      // A striped awning over the hatch, in the shack's own colour.
      const stripe = 18.0;
      var index = 0;
      for (var x = shack.left; x < shack.right; x += stripe) {
        canvas.drawRect(
          Rect.fromLTRB(
            x,
            shack.top + 8,
            math.min(x + stripe, shack.right),
            shack.top + 30,
          ),
          Paint()..color = index.isEven ? accent : _canvasWhite,
        );
        index++;
      }

      final label = _sign(BeachLayout.shackNames[i]);
      canvas.drawParagraph(
        label,
        Offset(shack.center.dx - label.width / 2, shack.top + 44),
      );
    }
  }

  static void _paintRail(Canvas canvas) {
    final timber = WorldPalette.of(WorldZone.beachBoardwalk).floor;
    const posts = BeachLayout.railPosts;
    if (posts.isEmpty) return;

    final rail = Paint()
      ..color = shade(timber, 0.16)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    // Two horizontals between the first and last post, and a cap on each
    // post. The rail is drawn and walked through — only the posts are solid.
    canvas
      ..drawLine(
        Offset(posts.first.x, BeachLayout.railY - 7),
        Offset(posts.last.x, BeachLayout.railY - 7),
        rail,
      )
      ..drawLine(
        Offset(posts.first.x, BeachLayout.railY + 6),
        Offset(posts.last.x, BeachLayout.railY + 6),
        rail,
      );

    for (final post in posts) {
      canvas.drawCircle(
        Offset(post.x, post.y),
        BeachLayout.railPostRadius,
        Paint()..color = shade(timber, -0.26),
      );
    }
  }

  // ---- Shared prop primitives ---------------------------------------------

  /// Converts a world rectangle into a drawable one.
  static Rect rect(WorldRect r) =>
      Rect.fromLTRB(r.left, r.top, r.right, r.bottom);

  /// The sand this map's props stand on.
  static Color get sandFloor => WorldPalette.of(WorldZone.beachSand).floor;

  /// Returns [base] moved towards white (positive) or black (negative).
  static Color shade(Color base, double amount) => Color.lerp(
    base,
    amount < 0 ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
    amount.abs(),
  )!;

  static Paragraph _sign(String text) {
    final builder =
        ParagraphBuilder(
            ParagraphStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.center,
            ),
          )
          ..pushStyle(TextStyle(color: _canvasWhite, letterSpacing: 3))
          ..addText(text);
    return builder.build()..layout(const ParagraphConstraints(width: 180));
  }
}
