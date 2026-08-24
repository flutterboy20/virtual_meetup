// Strict readers for untrusted JSON.
//
// Nothing that arrives on a socket is trusted: a field may be missing, null,
// the wrong type, or a number that is not a number (NaN survives a JSON
// round trip through `double.parse`). Every reader here throws a
// [FormatException] on anything it does not like; the decoder catches that
// once and turns the whole message into an unknown, so one bad client can
// never take the world down.

/// Returns [value] as a JSON object, or throws a [FormatException].
Map<String, Object?> readObject(Object? value, {required String what}) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$what must be an object, got ${value.runtimeType}');
}

/// Returns the string at [key] in [json], or throws a [FormatException].
String readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('"$key" must be a string, got ${value.runtimeType}');
}

/// Returns the int at [key] in [json], or throws a [FormatException].
int readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('"$key" must be an int, got ${value.runtimeType}');
}

/// Returns the finite double at [key] in [json], or throws.
///
/// Ints are accepted: a JSON encoder is free to write `10` for `10.0`, so
/// refusing them would make the protocol depend on how a peer serialises
/// whole numbers. NaN and infinities are rejected — they would poison every
/// bit of position maths downstream.
double readDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) {
    final result = value.toDouble();
    if (result.isFinite) return result;
    throw FormatException('"$key" must be finite, got $result');
  }
  throw FormatException('"$key" must be a number, got ${value.runtimeType}');
}

/// Returns the list of JSON objects at [key] in [json], or throws.
///
/// A missing key reads as an empty list, so a sender is free to omit a list
/// it has nothing to put in.
List<Map<String, Object?>> readObjectList(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException('"$key" must be a list, got ${value.runtimeType}');
  }
  return value
      .map((element) => readObject(element, what: key))
      .toList(growable: false);
}

/// Returns the list of strings at [key] in [json], or throws.
///
/// A missing key is *not* an error here: a snapshot with nothing to report in
/// one of its three lists may omit it, and treating that as malformed would
/// make the wire format brittle for the sake of three bytes.
List<String> readStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException('"$key" must be a list, got ${value.runtimeType}');
  }
  return value
      .map((element) {
        if (element is String) return element;
        throw FormatException(
          '"$key" must hold strings, got ${element.runtimeType}',
        );
      })
      .toList(growable: false);
}

/// Returns the bool at [key] in [json], or throws a [FormatException].
///
/// Strict about the type — `"true"` and `1` are not booleans. A truthiness
/// rule here would mean a moderation flag could be set by a typo.
bool readBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('"$key" must be a bool, got ${value.runtimeType}');
}

/// Returns the bool at [key] in [json], or [orElse] when it is not one.
///
/// The lenient counterpart to [readBool], and deliberately a *second*
/// function rather than a flag on the first. This one never throws: a missing
/// key, a `null`, a string, a number — anything that is not a bool — reads as
/// [orElse]. That is what lets a new optional flag be added to a message
/// shape without a flag day, exactly as `PlayerCosmetic.fromWireName` does
/// for an unknown hat and [readStringList] does for a missing list.
///
/// Use it only for fields where "we could not read it" and "it is off" are
/// genuinely the same answer. [readBool] stays strict for everything else,
/// because a moderation flag set by a typo is a bug nobody would ever find.
bool readOptionalBool(
  Map<String, Object?> json,
  String key, {
  bool orElse = false,
}) {
  final value = json[key];
  return value is bool ? value : orElse;
}
