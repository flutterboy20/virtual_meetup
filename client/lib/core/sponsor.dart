import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart' show Color;
import 'package:protocol/protocol.dart';

/// One sponsor booth in the world.
///
/// Deliberately **data, not code**. Sponsor lists change late and they change
/// often — a logo lands the week of the event, somebody's legal name is spelt
/// differently on the banner, a booth swaps sides. None of that should need a
/// rebuild, so every field here comes out of a config file and nothing about
/// a specific sponsor is written into the app.
@immutable
class Sponsor {
  /// Creates a sponsor.
  const Sponsor({
    required this.id,
    required this.name,
    required this.blurb,
    required this.x,
    required this.y,
    required this.color,
    this.tagline = '',
  });

  /// Reads a sponsor from one entry of the config file.
  ///
  /// Throws a [FormatException] naming the offending entry: a booth that
  /// silently fails to appear is far harder to notice on event morning than
  /// a startup error that says which line of JSON is wrong.
  factory Sponsor.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('a sponsor entry has no "id"');
    }
    String text(String key, {bool required = false}) {
      final value = json[key];
      if (value is String) return value;
      if (required) throw FormatException('sponsor "$id" has no "$key"');
      return '';
    }

    double number(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      throw FormatException('sponsor "$id" has no numeric "$key"');
    }

    return Sponsor(
      id: id,
      name: text('name', required: true),
      blurb: text('blurb'),
      tagline: text('tagline'),
      x: number('x'),
      y: number('y'),
      color: parseColor(text('color', required: true), id),
    );
  }

  /// Returns the config entry this booth was read from.
  ///
  /// The inverse of [Sponsor.fromJson], and it exists so the moderation
  /// screen can hand the bundled list back into the event document without a
  /// second, hand-rolled idea of what a booth looks like on the wire.
  ///
  /// The colour goes back as `#RRGGBB`. Alpha is dropped rather than written,
  /// because [parseColor] treats every booth as opaque and a round trip that
  /// invented an `#FF` prefix would produce a document nobody typed.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tagline': tagline,
    'blurb': blurb,
    'x': x,
    'y': y,
    'color': hexColor,
  };

  /// This booth's brand colour as `#RRGGBB`.
  String get hexColor {
    final rgb = (color.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    return '#$rgb';
  }

  /// Width of a booth's footprint, in world units.
  ///
  /// Fixed rather than per-sponsor: booths that are all the same size read as
  /// a row, and a row is what makes the east arm legible at a glance on a
  /// phone. It also means nobody can buy a bigger booth by editing JSON.
  static const double boothWidth = 120;

  /// Depth of a booth's footprint, in world units.
  static const double boothDepth = 64;

  /// How close a bean must get before the booth's info panel opens.
  static const double approachRadius = 118;

  /// How far a bean must get before it closes again.
  ///
  /// Wider than [approachRadius] on purpose. With one radius, a bean standing
  /// exactly on the boundary flickers the panel on and off every frame as the
  /// idle animation bobs it back and forth; the gap between the two is what
  /// makes that impossible.
  static const double leaveRadius = 158;

  /// The stable identifier used in the config file.
  final String id;

  /// The sponsor's display name.
  final String name;

  /// A sentence about them, shown in the info panel.
  final String blurb;

  /// A short line under the name — a product, a role, a category.
  final String tagline;

  /// The x coordinate of the booth's centre, in world units.
  final double x;

  /// The y coordinate of the booth's centre, in world units.
  final double y;

  /// The brand colour the booth is painted in.
  final Color color;

  /// The zone this booth stands in, or `null` if it is off the map.
  WorldZone? get zone => WorldZone.at(x, y);

  /// The booth's footprint, in world units.
  WorldRect get footprint => WorldRect(
    x - boothWidth / 2,
    y - boothDepth / 2,
    x + boothWidth / 2,
    y + boothDepth / 2,
  );

  /// Returns the squared distance from ([px], [py]) to this booth's centre.
  ///
  /// Squared, because the only thing that is ever done with it is a
  /// comparison against a radius, and this runs for every booth every frame.
  double distanceSquaredTo(double px, double py) {
    final dx = px - x;
    final dy = py - y;
    return dx * dx + dy * dy;
  }

  /// Parses a colour written as `#RRGGBB`, `#AARRGGBB` or `0xAARRGGBB`.
  ///
  /// Hex text rather than an int, because the config is edited by whoever has
  /// the brand guidelines open, and `#3DDC84` is a thing they can copy out of
  /// them. [context] names the sponsor in the error.
  static Color parseColor(String raw, String context) {
    var text = raw.trim();
    if (text.startsWith('#')) {
      text = text.substring(1);
    } else if (text.startsWith('0x') || text.startsWith('0X')) {
      text = text.substring(2);
    }
    if (text.length == 6) text = 'FF$text';
    final value = int.tryParse(text, radix: 16);
    if (text.length != 8 || value == null) {
      throw FormatException('sponsor "$context" has an unreadable colour');
    }
    return Color(value);
  }

  /// Two booths are equal when **every field** matches, not just the id.
  ///
  /// It used to be the id alone, on the reasoning that the id is what
  /// identifies a booth. That is true and it was still the wrong answer: the
  /// booth list is rebuilt from config every time one arrives, so everything
  /// downstream asks "is this the same list as before?" to decide whether to
  /// do any work — and under id-only equality a moderator renaming a sponsor
  /// produced a list that compared *equal* to the old one. The new name
  /// reached the config, the config reached the client, and nothing on screen
  /// moved: not the booth's sign, not the panel that was open in front of it.
  ///
  /// The identity reading is still available where it is wanted, and it is
  /// wanted in exactly one place: `readSponsors` rejects duplicates by
  /// comparing `id` strings directly.
  @override
  bool operator ==(Object other) =>
      other is Sponsor &&
      other.id == id &&
      other.name == name &&
      other.blurb == blurb &&
      other.tagline == tagline &&
      other.x == x &&
      other.y == y &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, name, blurb, tagline, x, y, color);

  @override
  String toString() => 'Sponsor($id at $x,$y)';
}
