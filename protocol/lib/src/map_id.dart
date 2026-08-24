/// Which of the world's places a client is standing in.
///
/// A closed set, in `protocol/`, because both ends have to agree on it and
/// they agree about it in three separate places: the client puts it in the
/// socket's query string, the server picks a relay with it, and the admin
/// screen groups a roster by it. A string passed around between those three
/// would be three chances to typo the same word.
///
/// It travels on the wire in exactly one place — `?map=` at socket-open — and
/// in one message field, `AdminPlayerSummary.map`. It is deliberately **not**
/// on `PlayerPosition` or in a snapshot: a client only ever receives players
/// from its own map, so repeating the map on every position sixty times a
/// minute would be paying per frame for a fact that is fixed for the session.
enum MapId {
  /// The conference venue: seven zones around a central atrium.
  conference('conference', 'Conference'),

  /// The beach: a boardwalk, a band of sand, and a swimmable sea.
  beach('beach', 'Beach');

  const MapId(this.id, this.label);

  /// The stable identifier this map travels as.
  final String id;

  /// The name a human sees.
  final String label;

  /// The map named by [id], or [MapId.conference].
  ///
  /// Unknown reads as the conference rather than as an error on purpose.
  /// This parses a **query string**, which is the least trustworthy thing on
  /// the wire and the easiest to get wrong by hand; refusing the socket over
  /// a typo would turn a mistyped link into a broken front door, and the
  /// conference is the place somebody who did not choose a place should be.
  static MapId fromId(String? id) {
    for (final map in MapId.values) {
      if (map.id == id) return map;
    }
    return MapId.conference;
  }

  /// The map named by [id], or `null` if it is not one.
  ///
  /// The strict reading, for the one caller that has to tell "they asked for
  /// the beach" from "they asked for nothing": startup logging and tests.
  static MapId? tryFromId(String? id) {
    for (final map in MapId.values) {
      if (map.id == id) return map;
    }
    return null;
  }
}
