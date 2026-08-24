import 'package:flutter/foundation.dart' show immutable;
import 'package:protocol/protocol.dart';

/// The things on a map a tap can mean something to.
///
/// An enum rather than a string id, so the `switch` that decides what a tap
/// *does* is checked by the compiler. A third target added here breaks that
/// switch at build time, which is the same trick `ProtocolMessage` uses on
/// the wire.
enum TapTargetId {
  /// The big surfboard in the sand.
  board,

  /// The bean with the `!` over its head.
  hint,
}

/// A rectangle in world space that answers to a tap.
///
/// Deliberately not a component. A tappable prop that was a component would
/// need a position, a size, an anchor and a place in the render tree, and it
/// draws nothing — the board is already in the furniture picture and the hint
/// bean draws itself. All this has to do is say "a tap here means that", and
/// the whole of the input path is one containment test over a list of two.
@immutable
class TapTarget {
  /// Creates a target covering [rect].
  const TapTarget(this.id, this.rect);

  /// What this target is.
  final TapTargetId id;

  /// Its footprint in world units.
  final WorldRect rect;

  /// Whether a tap at ([x], [y]) in world space lands on this target.
  bool contains(double x, double y) => rect.contains(x, y);
}
