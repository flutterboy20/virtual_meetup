// The conference map's dimensions, as plain constants.
//
// Since Phase 10 the authority on "how big is a map" is `MapSpec`, and there
// are two of them. Everything below is the conference's numbers, kept here
// because they must stay usable in a **const context** — `MapSpec.conference`
// is a const object, but a field read off one is not a constant expression,
// and `WorldLayout.pillarX = spawnCenterX` and `Minimap.aspect` both need it
// to be. `MapSpec.conference` is built from these very constants and
// `map_spec_test.dart` asserts the two never drift.
//
// New code should take a `MapSpec` rather than reach for these: anything
// written against them is written against one map and will be wrong on the
// other.

/// The width of the conference map, in world units.
///
/// The size lives in `protocol/` because both ends need it and they must
/// agree: the client clamps its bean to these bounds and the server clamps
/// every inbound position to them before relaying it.
const double worldWidth = 1600;

/// The height of the conference map, in world units.
const double worldHeight = 1200;

/// How far a bean is kept from a map's edge, in world units.
///
/// Shared by both maps: it is a fact about how a bean is drawn (anchored at
/// its feet), not about how big a room is.
///
/// A bean is anchored at its feet, so without an inset half of it would hang
/// over the edge of the floor.
const double worldEdgeInset = 24;

/// Clamps [x] to the playable width of the conference map.
///
/// `MapSpec.clampX` is the same thing asked of a map you hold as a value.
double clampWorldX(double x) =>
    x.clamp(worldEdgeInset, worldWidth - worldEdgeInset);

/// Clamps [y] to the playable height of the conference map.
double clampWorldY(double y) =>
    y.clamp(worldEdgeInset, worldHeight - worldEdgeInset);
