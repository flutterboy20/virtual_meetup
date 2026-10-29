import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/diorama_art.dart';
import 'package:client/game/stage_screen_component.dart';
import 'package:client/game/static_art.dart';
import 'package:client/game/water_component.dart';
import 'package:client/game/world_layout.dart';
import 'package:client/game/zone_props.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// Keeps the rectangle and colour of every filled rounded rectangle drawn,
/// in order.
class _RecordingCanvas implements Canvas {
  final List<Rect> rrects = [];
  final List<int> colors = [];

  @override
  void drawRRect(RRect rrect, Paint paint) {
    rrects.add(rrect.outerRect);
    colors.add(paint.color.toARGB32());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the stage', () {
    final deck = DioramaArt.topFace(
      ZoneProps.rect(WorldLayout.stage),
      height: ZoneProps.stageHeight,
    );

    test('the screen stands on the deck, lifted with it', () {
      final face = ZoneProps.stageScreenFace;
      final flat = ZoneProps.rect(WorldLayout.stageScreen);

      expect(face.size, equals(flat.size));
      expect(face.bottom, lessThan(flat.bottom));
      expect(deck.contains(face.topLeft), isTrue);
      expect(deck.contains(face.bottomRight), isTrue);
    });

    test('the live words are drawn where the frame is', () {
      // Two components, one rectangle. If the stage grew and only the
      // furniture knew, the programme would scroll across the deck below
      // its own screen.
      final screen = StageScreenComponent(lines: const ['Keynote at ten']);
      final canvas = _RecordingCanvas();

      screen.render(canvas);

      expect(
        canvas.rrects.first,
        equals(ZoneProps.stageScreenFace.deflate(5)),
      );
    });
  });

  group('the seat rows', () {
    test('every backrest stands inside its own row', () {
      // The taller half of a row must collide exactly where the shorter half
      // always did, or the backrest is a wall nobody can see the edge of.
      for (final row in WorldLayout.seatRows) {
        final seat = ZoneProps.rect(row.rect);
        final back = ZoneProps.backrest(seat);

        expect(seat.intersect(back), equals(back));
        expect(back.bottom, equals(seat.bottom), reason: 'faces the stage');
      }
    });

    test('a backrest stands taller than the cushion in front of it', () {
      expect(ZoneProps.backrestHeight, greaterThan(ZoneProps.seatHeight));
    });
  });

  group('the atrium', () {
    test('the lit band sits inside the pillar, below its top', () {
      expect(ZoneProps.pillarBandBase, greaterThan(0));
      expect(
        ZoneProps.pillarBandBase + ZoneProps.pillarBandHeight,
        lessThan(ZoneProps.pillarHeight),
      );
    });
  });

  group('the food court', () {
    test('the raised parasol stays inside the court', () {
      // Lifted any higher, the canopy would climb over the north wall and
      // read as hanging off the next room.
      final cart = ZoneProps.rect(WorldLayout.snackCart);
      final canopy = DioramaArt.cylinderTop(
        cart.center,
        height: ZoneProps.parasolHeight,
      );

      expect(
        canopy.dy - ZoneProps.parasolRadius,
        greaterThanOrEqualTo(WorldZone.foodCourt.rect.top),
      );
    });

    test('the awning hangs higher than the counter under it', () {
      expect(ZoneProps.awningBase, greaterThan(ZoneProps.counterHeight));
    });
  });

  group('the code lab', () {
    final canvas = _RecordingCanvas();
    ZoneProps.paintCodeLab(canvas);

    test('what is on both boards lands where it always did', () {
      // The projected line is laid out against the old rectangle, so the
      // board's face has to stay exactly there and not move up with the
      // height. The lit glass and the white surface are the proof.
      final screen = ZoneProps.rect(WorldLayout.labScreen);
      final board = ZoneProps.rect(WorldLayout.whiteboard);

      expect(canvas.rrects, contains(screen.deflate(7)));
      expect(canvas.rrects, contains(board.deflate(6)));
    });

    test('every monitor screen stands on top of a desk', () {
      const lit = 0xFF43C8E0;
      final tops = [
        for (final desk in WorldLayout.labDesks)
          DioramaArt.topFace(
            ZoneProps.rect(desk.rect),
            height: ZoneProps.deskHeight,
          ),
      ];
      final screens = [
        for (var i = 0; i < canvas.rrects.length; i++)
          if (canvas.colors[i] == lit) canvas.rrects[i],
      ];

      expect(screens, hasLength(WorldLayout.labDesks.length * 4));
      for (final screen in screens) {
        expect(
          tops.any((top) => top.intersect(screen) == screen),
          isTrue,
          reason: '$screen is off the desks',
        );
      }
    });
  });

  group('the sponsor booths', () {
    final footprint = ZoneProps.rect(
      const Sponsor(
        id: 'a',
        name: 'A Corp',
        blurb: '',
        x: 1130,
        y: 478,
        color: Color(0xFF54C5F8),
      ).footprint,
    );
    final wall = ZoneProps.boothWall(footprint);

    test('the sign did not move: the band is the foot of the wall', () {
      // The brand band and the name are drawn at the same offsets from the
      // footprint as before Phase 16. The wall is built so they land on it.
      expect(wall.bottom, equals(footprint.top + 34));
      expect(wall.top, lessThan(footprint.top + 8));
      expect(wall.left, equals(footprint.left));
      expect(wall.right, equals(footprint.right));
    });

    test('the wall stands inside the booth it belongs to', () {
      // Its footprint is a strip along the bottom of its face, which has to
      // be inside the booth's own footprint, or the wall collides nowhere.
      expect(wall.bottom, lessThanOrEqualTo(footprint.bottom));
      expect(wall.bottom - 6, greaterThanOrEqualTo(footprint.top));
    });

    test("the counter's lifted top clears the bottom of the sign", () {
      final counter = ZoneProps.boothCounter(footprint);
      final top = DioramaArt.topFace(
        counter,
        height: ZoneProps.boothCounterHeight,
      );

      expect(footprint.intersect(counter), equals(counter));
      expect(top.top, greaterThanOrEqualTo(wall.bottom));
    });
  });

  group('the lounge', () {
    test("the pool's rim is the water's rim", () {
      expect(ZoneProps.poolRimRadius, equals(WaterComponent.shapeRadius));
    });

    test('the inner wall is a strip inside the north of the pool', () {
      final pool = ZoneProps.rect(WorldLayout.pool);
      final wall = ZoneProps.poolInnerWall(pool);

      expect(pool.intersect(wall), equals(wall));
      expect(wall.top, equals(pool.top));
      expect(wall.height, lessThan(pool.height / 10));
    });
  });

  group('the garden', () {
    const steps = WorldLayout.deckTreads + 1;

    test('the deck climbs in even steps to the platform', () {
      final rise = ZoneProps.deckStepHeight(0);

      for (var i = 1; i < steps; i++) {
        expect(
          ZoneProps.deckStepHeight(i) - ZoneProps.deckStepHeight(i - 1),
          closeTo(rise, 1e-9),
        );
      }
      expect(
        ZoneProps.deckStepHeight(WorldLayout.deckTreads),
        equals(ZoneProps.deckHeight),
      );
    });

    test('the steps tile the deck, the platform east of the treads', () {
      final deck = ZoneProps.rect(WorldLayout.gardenDeck);

      expect(ZoneProps.deckStep(0).left, equals(deck.left));
      for (var i = 1; i < steps; i++) {
        expect(
          ZoneProps.deckStep(i).left,
          closeTo(ZoneProps.deckStep(i - 1).right, 1e-9),
        );
      }
      expect(
        ZoneProps.deckStep(WorldLayout.deckTreads),
        equals(
          Rect.fromLTRB(
            WorldLayout.deckPlatformX,
            deck.top,
            deck.right,
            deck.bottom,
          ),
        ),
      );
    });

    test('every step keeps its face inside its own footprint', () {
      // Beans are not lifted, so the deck's tops must not be either: the
      // height shows as a face hanging inside the footprint, never as a
      // lifted top a bean would be drawn below.
      for (var i = 0; i < steps; i++) {
        final step = ZoneProps.deckStep(i);
        final face = DioramaArt.frontFace(
          step,
          height: ZoneProps.deckStepHeight(i),
        );

        expect(step.intersect(face), equals(face));
        expect(face.bottom, equals(step.bottom));
      }
    });

    test('every bench has its back to the fountain', () {
      for (final bench in WorldLayout.gardenBenches) {
        final at = ZoneProps.rect(bench.rect);
        final back = ZoneProps.benchBack(at);
        final fountain = WorldLayout.fountain.y;

        expect(at.intersect(back), equals(back));
        expect(
          (back.center.dy - fountain).abs(),
          greaterThan((at.center.dy - fountain).abs()),
          reason: '$at faces away from the fountain',
        );
      }
    });

    test("the fountain's water sits in the basin, below its rim", () {
      final centre = Offset(WorldLayout.fountain.x, WorldLayout.fountain.y);
      final rim = DioramaArt.cylinderTop(
        centre,
        height: ZoneProps.fountainBasinHeight,
      );
      final water = ZoneProps.fountainWater;

      expect(water.dx, equals(rim.dx));
      expect(water.dy, greaterThan(rim.dy), reason: 'lower than the rim');
      // The inside wall that shows is a thin crescent, not a second rim.
      expect(water.dy - rim.dy, lessThan(ZoneProps.fountainWall));
    });

    test('a tree holds its leaves above its trunk', () {
      expect(ZoneProps.treeCrownBase, greaterThan(0));
      expect(ZoneProps.treeCrownTop, greaterThan(ZoneProps.treeCrownBase));
    });
  });

  test('the conference furniture records with height', () {
    const booth = Sponsor(
      id: 'a',
      name: 'A Corp',
      blurb: '',
      x: 1130,
      y: 478,
      color: Color(0xFF54C5F8),
    );
    final picture = recordPicture(
      WorldLayout.of(const [booth]).paintFurniture,
    );
    addTearDown(picture.dispose);
  });
}
