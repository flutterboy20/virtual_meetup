import 'dart:math' as math;

/// A cell address in the grid: column, then row.
///
/// A record rather than a class because Dart gives records value equality and
/// a hash code for free, which is exactly what a map key needs.
typedef GridCell = (int column, int row);

/// A uniform grid over world space, used to answer "who is near this point?"
///
/// This is the whole scaling story of the project. Without it, telling every
/// client about every other client costs `players² × send rate` messages —
/// ~400,000/sec at 200 attendees, which is dead on arrival. With it, a
/// client's cost depends on how many people are *near them*, which barely
/// changes as the conference grows.
///
/// The structure is deliberately the simplest one that works: a hash map from
/// cell to the set of ids in it. No quadtree, no k-d tree. Those pay off when
/// density varies wildly or the world is unbounded; here the world is a fixed
/// rectangle and players are roughly evenly spread, so a flat grid wins on
/// every axis that matters — O(1) insert, O(1) move, no rebalancing, and
/// nothing to get subtly wrong.
///
/// Pure data structure: no sockets, no protocol, no clock. It knows about ids
/// and coordinates and nothing else.
class SpatialGrid {
  /// Creates an empty grid whose cells are [cellSize] world units square.
  ///
  /// Throws if [cellSize] is not positive — a zero or negative cell size
  /// would make every coordinate map to the same (or an inverted) cell, and
  /// the failure would show up much later as "everybody can see everybody".
  SpatialGrid({this.cellSize = defaultCellSize}) {
    if (cellSize <= 0) {
      throw ArgumentError.value(cellSize, 'cellSize', 'must be positive');
    }
  }

  /// The default cell edge length, in world units.
  ///
  /// Sized so that the 3×3 block a client receives (960 units across) is
  /// comfortably wider than what fits on screen — a phone sees roughly
  /// 250×500 world units at the game's fixed zoom, a laptop roughly 875×560.
  /// Interest range has to exceed the visible area, or players would pop into
  /// existence at the edge of the screen instead of already being there.
  static const double defaultCellSize = 320;

  /// The edge length of one cell, in world units.
  final double cellSize;

  final Map<GridCell, Set<String>> _cells = {};
  final Map<String, GridCell> _cellOf = {};

  /// How many ids the grid is holding.
  int get count => _cellOf.length;

  /// How many cells currently hold at least one id.
  ///
  /// Empty cells are dropped rather than kept around, so this is also the
  /// grid's memory footprint in practice.
  int get occupiedCellCount => _cells.length;

  /// The cell [id] is currently in, or `null` if it is not in the grid.
  GridCell? cellOfId(String id) => _cellOf[id];

  /// Returns the cell that contains ([x], [y]).
  ///
  /// Uses `floor`, not truncation: at negative coordinates truncation would
  /// fold -0.5 and +0.5 into the same cell and put a seam through the origin.
  /// The world never goes negative today, but a grid that is wrong outside
  /// its expected input is a trap for whoever moves the world origin later.
  GridCell cellAt(double x, double y) =>
      ((x / cellSize).floor(), (y / cellSize).floor());

  /// Puts [id] at ([x], [y]), moving it between cells if needed.
  ///
  /// Insert and move are one operation on purpose: the caller does not have
  /// to know whether this id was already here, so there is no way to leak an
  /// id into two cells at once by calling the wrong one.
  void upsert(String id, double x, double y) {
    final cell = cellAt(x, y);
    final previous = _cellOf[id];
    if (previous == cell) return;
    if (previous != null) _removeFromCell(id, previous);

    _cells.putIfAbsent(cell, () => <String>{}).add(id);
    _cellOf[id] = cell;
  }

  /// Removes [id] from the grid.
  ///
  /// Removing an id that is not there is a no-op, not an error: a socket can
  /// die at any moment, and the cleanup path should not have to check first.
  void remove(String id) {
    final cell = _cellOf.remove(id);
    if (cell != null) _removeFromCell(id, cell);
  }

  /// Removes everything.
  void clear() {
    _cells.clear();
    _cellOf.clear();
  }

  /// Every id in the 3×3 block of cells centred on ([x], [y]).
  ///
  /// Three by three, not one: two players standing either side of a cell
  /// boundary are two units apart and must still see each other. A
  /// single-cell query would make them invisible to one another, which is the
  /// classic interest-management bug — and the reason the interest area is
  /// always bigger than the screen.
  ///
  /// The result includes an id sitting exactly at ([x], [y]), so a caller
  /// asking on behalf of a player gets themselves back and must skip it.
  Iterable<String> near(double x, double y) sync* {
    final (column, row) = cellAt(x, y);
    for (var dc = -1; dc <= 1; dc++) {
      for (var dr = -1; dr <= 1; dr++) {
        final ids = _cells[(column + dc, row + dr)];
        if (ids != null) yield* ids;
      }
    }
  }

  /// How many ids are in the 3×3 block centred on ([x], [y]).
  ///
  /// Cheaper than counting [near] because it never materialises the ids —
  /// used by the metrics, which run every tick and must not become the cost
  /// they are measuring.
  int countNear(double x, double y) {
    final (column, row) = cellAt(x, y);
    var total = 0;
    for (var dc = -1; dc <= 1; dc++) {
      for (var dr = -1; dr <= 1; dr++) {
        total += _cells[(column + dc, row + dr)]?.length ?? 0;
      }
    }
    return total;
  }

  /// The ids in exactly one cell, for tests and diagnostics.
  Set<String> idsInCell(GridCell cell) =>
      Set.unmodifiable(_cells[cell] ?? const <String>{});

  /// The largest number of ids in any single cell.
  ///
  /// The honest measure of how lumpy the crowd is: a hot cell is what makes
  /// one client's snapshot much more expensive than the average.
  int get busiestCellCount =>
      _cells.values.fold(0, (worst, ids) => math.max(worst, ids.length));

  void _removeFromCell(String id, GridCell cell) {
    final ids = _cells[cell];
    if (ids == null) return;
    ids.remove(id);
    // Drop the empty set rather than keeping it: 200 people wandering a big
    // world would otherwise leave a permanent map entry per cell they ever
    // touched, and `busiestCellCount` would walk them all every tick.
    if (ids.isEmpty) _cells.remove(cell);
  }
}
