import 'dart:typed_data';

import 'package:protocol/protocol.dart';

/// Picks the nearest N players to a point, without sorting the rest.
///
/// This is the server's hot loop inside its hot loop: it runs once per player
/// per tick, so at 300 attendees and 15Hz it runs 4,500 times a second, over
/// however many candidates the interest grid handed back — which in a packed
/// atrium is very nearly everybody.
///
/// **Why it is not just a sort.** The obvious version sorts the candidates by
/// distance and takes the first N. That costs `O(n log n)` *comparisons*, and
/// every comparison recomputes both operands' distances, so the real cost is
/// about `2 n log n` distance calculations and set lookups. Measured at 300
/// bots clustered at spawn, that put the tick at 49.9 ms out of a 66 ms
/// budget.
///
/// This keeps a bounded max-heap of the best `cap` seen so far instead. Each
/// candidate's rank is computed exactly **once**, and only the ones that beat
/// the current worst do any further work: `O(n)` rank computations and
/// `O(n log cap)` heap operations, where `cap` is 40 and does not grow with
/// the crowd.
///
/// The heap is a max-heap — the *worst* of the keepers sits at the root —
/// because the only question asked of it is "is this candidate better than
/// the worst one I am holding?", and that answer must be free.
///
/// The buffers are reused between calls. One allocation per player per tick
/// is 4,500 allocations a second thrown at the garbage collector for no
/// reason, and GC pauses land on the tick as overruns.
class NearestPlayers {
  /// Creates a selector that keeps at most [cap] players.
  NearestPlayers({required this.cap})
    : // Fixed-size and **unboxed**. A growable `List<double>` boxes every
      // value it is given, and this writes one rank per candidate per player
      // per tick — over a million boxed doubles a second at 300 attendees.
      // Measured: switching these two to fixed-size typed storage took the
      // resident set from 93 MB back to 73 MB at 300 clustered.
      _ranks = Float64List(cap < 0 ? 0 : cap),
      _heap = List<PlayerState?>.filled(cap < 0 ? 0 : cap, null);

  /// How much closer an incumbent is treated as being.
  ///
  /// 0.8 squared, applied to a squared distance: an incumbent has to be 25%
  /// further away than a newcomer before it loses its place. Without this,
  /// two people at almost identical distances trade the last slot every tick,
  /// and each trade re-sends a whole player state — precisely the cost the
  /// cap exists to avoid.
  static const double incumbentDiscount = 0.64;

  /// The most players this will return.
  final int cap;

  final List<PlayerState?> _heap;
  final Float64List _ranks;
  int _size = 0;

  /// Returns the nearest [cap] of [candidates] to ([x], [y]).
  ///
  /// [isKnown] reports whether this client already knows about a player, so
  /// incumbents can be given [incumbentDiscount].
  ///
  /// Returns [candidates] itself, untouched, when it is already short enough
  /// — which is the normal case everywhere except a packed atrium, so a quiet
  /// world pays nothing at all for this.
  ///
  /// The result is in no particular order. Nothing downstream cares: the
  /// snapshot is a set of positions, not a ranking, and sorting the survivors
  /// afterwards would be work done for a reader that does not exist.
  List<PlayerState> select(
    List<PlayerState> candidates, {
    required double x,
    required double y,
    required bool Function(String id) isKnown,
  }) {
    if (candidates.length <= cap || cap <= 0) return candidates;

    _size = 0;
    for (final player in candidates) {
      final dx = player.x - x;
      final dy = player.y - y;
      // Squared distance throughout: the square root is monotonic, so it
      // cannot change any ordering, and it is the single most expensive
      // arithmetic operation on this path.
      var rank = dx * dx + dy * dy;
      if (isKnown(player.id)) rank *= incumbentDiscount;

      if (_size < cap) {
        _heap[_size] = player;
        _ranks[_size] = rank;
        _size++;
        _siftUp(_size - 1);
      } else if (rank < _ranks[0]) {
        _heap[0] = player;
        _ranks[0] = rank;
        _siftDown(0);
      }
    }
    // The one allocation this makes, and it is the result itself. Every
    // entry below `_size` was written this call, so the casts are safe.
    return List<PlayerState>.generate(
      _size,
      (index) => _heap[index]!,
      growable: false,
    );
  }

  void _siftUp(int start) {
    var index = start;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_ranks[parent] >= _ranks[index]) break;
      _swap(parent, index);
      index = parent;
    }
  }

  void _siftDown(int start) {
    var index = start;
    while (true) {
      final left = index * 2 + 1;
      final right = left + 1;
      var largest = index;
      if (left < _size && _ranks[left] > _ranks[largest]) largest = left;
      if (right < _size && _ranks[right] > _ranks[largest]) largest = right;
      if (largest == index) break;
      _swap(largest, index);
      index = largest;
    }
  }

  void _swap(int a, int b) {
    final player = _heap[a];
    _heap[a] = _heap[b];
    _heap[b] = player;
    final rank = _ranks[a];
    _ranks[a] = _ranks[b];
    _ranks[b] = rank;
  }
}
