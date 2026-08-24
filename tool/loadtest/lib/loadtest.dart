/// A bot load-tester for the relay server.
///
/// Load testing here is a design tool, not a final checkbox: the numbers it
/// produces are what decide the tick rate, the cell size, and whether JSON on
/// the wire survives to the conference.
library;

export 'src/scenario.dart';
export 'src/swarm.dart';
export 'src/wander.dart';
