import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  // A small cell keeps the arithmetic in these tests readable: cell (0,0) is
  // 0..99 on both axes, cell (1,0) is 100..199, and so on.
  const cellSize = 100.0;

  late SpatialGrid grid;

  setUp(() => grid = SpatialGrid(cellSize: cellSize));

  /// Everyone [grid] would report near ([x], [y]), as a set for order-free
  /// comparison — the grid promises *which* ids, never in what order.
  Set<String> near(double x, double y) => grid.near(x, y).toSet();

  group('construction', () {
    test('a non-positive cell size is refused', () {
      expect(() => SpatialGrid(cellSize: 0), throwsArgumentError);
      expect(() => SpatialGrid(cellSize: -1), throwsArgumentError);
    });

    test('an empty grid holds nothing', () {
      expect(grid.count, isZero);
      expect(grid.occupiedCellCount, isZero);
      expect(grid.busiestCellCount, isZero);
      expect(near(0, 0), isEmpty);
    });
  });

  group('cellAt', () {
    test('maps a point to the cell containing it', () {
      expect(grid.cellAt(0, 0), equals((0, 0)));
      expect(grid.cellAt(99.99, 99.99), equals((0, 0)));
      expect(grid.cellAt(100, 0), equals((1, 0)));
      expect(grid.cellAt(250, 380), equals((2, 3)));
    });

    test('floors rather than truncates below zero', () {
      // Truncation would fold -0.5 and +0.5 into the same cell and put a
      // seam through the origin.
      expect(grid.cellAt(-0.5, -0.5), equals((-1, -1)));
      expect(grid.cellAt(-100, -100), equals((-1, -1)));
      expect(grid.cellAt(-100.5, 0), equals((-2, 0)));
    });
  });

  group('insertion', () {
    test('an inserted id is found near its own position', () {
      grid.upsert('a', 50, 50);

      expect(near(50, 50), equals({'a'}));
      expect(grid.count, equals(1));
      expect(grid.cellOfId('a'), equals((0, 0)));
    });

    test('two players in the same cell see each other', () {
      grid
        ..upsert('a', 10, 10)
        ..upsert('b', 90, 90);

      expect(near(10, 10), equals({'a', 'b'}));
      expect(near(90, 90), equals({'a', 'b'}));
      expect(grid.occupiedCellCount, equals(1));
    });

    test('inserting the same id twice moves it instead of duplicating it', () {
      grid
        ..upsert('a', 50, 50)
        ..upsert('a', 550, 550);

      expect(grid.count, equals(1));
      expect(near(50, 50), isEmpty);
      expect(near(550, 550), equals({'a'}));
    });
  });

  group('the boundary problem', () {
    // The whole reason interest is a 3x3 block and not one cell. Two people
    // standing a couple of units apart must see each other even when a cell
    // edge runs between them.
    test('players either side of a vertical boundary see each other', () {
      grid
        ..upsert('left', 99, 50)
        ..upsert('right', 101, 50);

      expect(grid.cellOfId('left'), isNot(equals(grid.cellOfId('right'))));
      expect(near(99, 50), equals({'left', 'right'}));
      expect(near(101, 50), equals({'left', 'right'}));
    });

    test('players either side of a horizontal boundary see each other', () {
      grid
        ..upsert('above', 50, 99)
        ..upsert('below', 50, 101);

      expect(near(50, 99), equals({'above', 'below'}));
      expect(near(50, 101), equals({'above', 'below'}));
    });

    test('players meeting at a four-cell corner all see each other', () {
      grid
        ..upsert('nw', 99, 99)
        ..upsert('ne', 101, 99)
        ..upsert('sw', 99, 101)
        ..upsert('se', 101, 101);

      const everyone = {'nw', 'ne', 'sw', 'se'};
      expect(near(99, 99), equals(everyone));
      expect(near(101, 101), equals(everyone));
      expect(grid.occupiedCellCount, equals(4));
    });

    test('visibility is symmetric across a boundary', () {
      // A one-way interest relationship would be worse than none: you would
      // watch somebody who cannot see you.
      grid
        ..upsert('a', 199, 199)
        ..upsert('b', 200, 200);

      expect(near(199, 199).contains('b'), isTrue);
      expect(near(200, 200).contains('a'), isTrue);
    });
  });

  group('range', () {
    test('a player two cells away is not visible', () {
      grid
        ..upsert('here', 50, 50)
        ..upsert('far', 250, 50);

      expect(near(50, 50), equals({'here'}));
      expect(near(250, 50), equals({'far'}));
    });

    test('the block reaches exactly one cell in every direction', () {
      // Ring the centre cell with one player per neighbouring cell, plus one
      // two cells out, and check precisely who comes back.
      grid
        ..upsert('centre', 150, 150)
        ..upsert('n', 150, 50)
        ..upsert('s', 150, 250)
        ..upsert('e', 250, 150)
        ..upsert('w', 50, 150)
        ..upsert('ne', 250, 50)
        ..upsert('nw', 50, 50)
        ..upsert('se', 250, 250)
        ..upsert('sw', 50, 250)
        ..upsert('outside', 350, 150);

      expect(
        near(150, 150),
        equals({'centre', 'n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'}),
      );
    });

    test('countNear agrees with near without building the list', () {
      grid
        ..upsert('a', 150, 150)
        ..upsert('b', 90, 90)
        ..upsert('c', 350, 150);

      expect(grid.countNear(150, 150), equals(near(150, 150).length));
      expect(grid.countNear(150, 150), equals(2));
      expect(grid.countNear(1000, 1000), isZero);
    });

    test('an empty region reports nobody', () {
      grid.upsert('a', 50, 50);

      expect(near(5000, 5000), isEmpty);
      expect(grid.idsInCell((50, 50)), isEmpty);
    });
  });

  group('movement', () {
    test('moving within a cell keeps the id where it was', () {
      grid
        ..upsert('a', 10, 10)
        ..upsert('a', 90, 90);

      expect(grid.cellOfId('a'), equals((0, 0)));
      expect(grid.idsInCell((0, 0)), equals({'a'}));
    });

    test('moving across a boundary re-files the id', () {
      grid
        ..upsert('a', 50, 50)
        ..upsert('a', 150, 50);

      expect(grid.cellOfId('a'), equals((1, 0)));
      expect(grid.idsInCell((0, 0)), isEmpty);
      expect(grid.idsInCell((1, 0)), equals({'a'}));
    });

    test('walking out of range makes a player invisible', () {
      grid
        ..upsert('watcher', 50, 50)
        ..upsert('walker', 50, 50);

      expect(near(50, 50), equals({'watcher', 'walker'}));

      grid.upsert('walker', 550, 550);

      expect(near(50, 50), equals({'watcher'}));
      expect(near(550, 550), equals({'walker'}));
    });

    test('walking back into range makes them visible again', () {
      grid
        ..upsert('watcher', 50, 50)
        ..upsert('walker', 550, 550)
        ..upsert('walker', 60, 60);

      expect(near(50, 50), equals({'watcher', 'walker'}));
    });

    test('a vacated cell is dropped rather than left behind empty', () {
      grid
        ..upsert('a', 50, 50)
        ..upsert('a', 550, 550);

      expect(grid.occupiedCellCount, equals(1));
    });
  });

  group('removal', () {
    test('a removed id disappears from queries and from the count', () {
      grid
        ..upsert('a', 50, 50)
        ..upsert('b', 50, 50)
        ..remove('a');

      expect(near(50, 50), equals({'b'}));
      expect(grid.count, equals(1));
      expect(grid.cellOfId('a'), isNull);
    });

    test('removing an id that was never there is harmless', () {
      grid
        ..upsert('a', 50, 50)
        ..remove('ghost')
        ..remove('a')
        ..remove('a');

      expect(grid.count, isZero);
      expect(grid.occupiedCellCount, isZero);
    });

    test('clear empties everything', () {
      grid
        ..upsert('a', 50, 50)
        ..upsert('b', 550, 550)
        ..clear();

      expect(grid.count, isZero);
      expect(grid.occupiedCellCount, isZero);
      expect(near(50, 50), isEmpty);
    });
  });

  group('density', () {
    test('busiestCellCount reports the worst cell, not the average', () {
      grid
        ..upsert('a', 50, 50)
        ..upsert('b', 50, 50)
        ..upsert('c', 50, 50)
        ..upsert('d', 550, 550);

      expect(grid.busiestCellCount, equals(3));
    });

    test('busiestCellCount falls when the crowd spreads out', () {
      grid
        ..upsert('a', 50, 50)
        ..upsert('b', 50, 50)
        ..upsert('b', 550, 550);

      expect(grid.busiestCellCount, equals(1));
    });
  });

  group('at scale', () {
    test('culling really does cull', () {
      // 400 ids spread over a 20x20 arrangement of cells. Anyone querying
      // from the middle should see the 3x3 neighbourhood — nine of them —
      // and not the other 391. This is the property the whole phase exists
      // for, asserted rather than assumed.
      for (var i = 0; i < 400; i++) {
        final column = i % 20;
        final row = i ~/ 20;
        grid.upsert('p$i', column * cellSize + 50, row * cellSize + 50);
      }

      expect(grid.count, equals(400));
      expect(near(1050, 1050).length, equals(9));
      expect(grid.busiestCellCount, equals(1));
    });

    test('a corner query is not penalised for the missing neighbours', () {
      for (var i = 0; i < 400; i++) {
        final column = i % 20;
        final row = i ~/ 20;
        grid.upsert('p$i', column * cellSize + 50, row * cellSize + 50);
      }

      // Bottom-left corner: only four of the nine cells exist.
      expect(near(50, 50).length, equals(4));
    });
  });
}
