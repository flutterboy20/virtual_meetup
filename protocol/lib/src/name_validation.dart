// Display-name rules, shared by both ends.
//
// These live in `protocol/` for the same reason the messages do: the client
// and the server must agree, and two copies of a rule is how they stop
// agreeing. The client runs them to show a message while somebody types; the
// server runs the *same* functions before it lets anybody in. The client's
// pass is UX. The server's pass is the rule.

/// The shortest display name a player may join with.
const int minNameLength = 2;

/// The longest display name a player may join with.
///
/// Sixteen is a layout number, not a moral one: a nametag floats over a bean
/// 26 world units wide, and anything longer turns the world into a wall of
/// text.
const int maxNameLength = 16;

/// The verdict on one candidate display name.
///
/// An enum rather than a `bool` because the caller has three different jobs
/// with the answer: the client picks a message to show, the server picks a
/// rejection reason to send, and the tests assert on *which* rule fired
/// rather than merely that something did.
enum NameValidation {
  /// The name may be used as-is.
  valid('valid'),

  /// Shorter than [minNameLength] after trimming.
  tooShort('tooShort'),

  /// Longer than [maxNameLength] after trimming.
  tooLong('tooLong'),

  /// Contains something outside the allowed character set.
  badChars('badChars'),

  /// Matched the blocked-word list.
  blocked('blocked');

  const NameValidation(this.wireName);

  /// The string this verdict travels as.
  final String wireName;

  /// Whether the name passed every rule.
  bool get isValid => this == NameValidation.valid;

  /// Returns the verdict named by [wireName], or [NameValidation.blocked].
  ///
  /// An unrecognised verdict from a newer peer is treated as a refusal rather
  /// than as a pass: failing open here would mean a client that does not
  /// understand a new rule quietly ignores it.
  static NameValidation fromWireName(String? wireName) {
    for (final value in NameValidation.values) {
      if (value.wireName == wireName) return value;
    }
    return NameValidation.blocked;
  }

  /// A short, calm sentence to show the person typing.
  ///
  /// Deliberately never repeats the offending text back, and never says
  /// *which* word was blocked — that would turn the rejection message into a
  /// list of things to try next.
  String get message => switch (this) {
    NameValidation.valid => '',
    NameValidation.tooShort =>
      'A bit short — use at least $minNameLength characters.',
    NameValidation.tooLong =>
      'A bit long — keep it to $maxNameLength characters.',
    NameValidation.badChars =>
      'Letters, numbers, spaces and . - _ apostrophes only, please.',
    NameValidation.blocked => 'Please pick a different name.',
  };
}

/// Returns [raw] trimmed with runs of whitespace collapsed to one space.
///
/// Every rule below is applied to this form, and it is what actually gets
/// stored — so `"  Ada   Lovelace "` and `"Ada Lovelace"` are the same name,
/// and neither can pad itself into somebody else's nametag space.
String normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// The characters a display name may be built from.
///
/// A whitelist, not a blacklist of bad characters, and that is the whole
/// point of it: it is what stops zalgo, right-to-left overrides, zero-width
/// joiners, emoji walls, and Cyrillic homoglyphs (an `Admin` whose A is
/// U+0410) without needing to know any of them by name. A wordlist can only
/// block what somebody thought of; a whitelist blocks everything nobody
/// thought of.
///
/// The cost is real and worth naming: this rejects names written in
/// Devanagari, Tamil, Arabic and every other non-Latin script, at events
/// whose attendees write in them. The trade accepted here is that a
/// transliteration is available to everybody, while a rule that is safe for
/// arbitrary Unicode is not something this project can write correctly today.
/// If that changes, this regex is the single place it changes.
final RegExp _allowedCharacters = RegExp(r"^[A-Za-z0-9 ._'-]+$");

/// Digits that stand in for letters in the usual dodges.
///
/// Applied only when checking against the wordlist, never to the stored name:
/// `L33t` is a perfectly good name to walk around as, it just does not get to
/// smuggle a blocked word past the filter.
///
/// Only characters the whitelist already allows are worth listing — `@` and
/// `$` never reach this code, because the charset rule rejected them first.
const Map<String, String> _leetLetters = {
  '0': 'o',
  '1': 'i',
  '3': 'e',
  '4': 'a',
  '5': 's',
  '7': 't',
  '8': 'b',
};

/// Words blocked wherever they appear inside a name.
///
/// Only strings with no innocent superstring in normal use belong here — a
/// substring rule is the aggressive one, and every entry is a promise that no
/// real name contains it. `cunt` is deliberately *not* on this list for
/// exactly that reason (Scunthorpe), and neither is `rape` (grapes, drape,
/// scrape, trapeze).
const Set<String> _blockedFragments = {
  'fuck',
  'bitch',
  'asshole',
  'nigger',
  'nigga',
  'faggot',
  'whore',
  'wanker',
  'cocksucker',
  'dickhead',
  'motherfucker',
};

/// Words blocked only when they stand alone as a word.
///
/// These have common, innocent superstrings, so they are matched against each
/// separated word and against the name with its separators removed — never as
/// a free substring. `Shitole` and `Scunthorpe` are real surnames; `sex` sits
/// inside `Sussex` and `Middlesex`; `anal` sits inside `Analytics`.
const Set<String> _blockedWords = {
  'cunt',
  'rape',
  'rapist',
  'shit',
  'bullshit',
  'piss',
  'dick',
  'cock',
  'penis',
  'vagina',
  'anal',
  'porn',
  'sex',
  'slut',
  'retard',
  'nazi',
  'hitler',
};

/// Returns the verdict on [raw] as a display name.
///
/// Rules run cheapest-first and in a deliberate order: length, then the
/// character whitelist, then the wordlist. Charset before wordlist matters —
/// once the name is known to be plain Latin text, the wordlist only has to
/// think about tricks made of *allowed* characters (spacing, dots,
/// substituted digits) instead of the entire Unicode plane.
NameValidation validateName(String raw) {
  final name = normalizeName(raw);

  if (name.length < minNameLength) return NameValidation.tooShort;
  if (name.length > maxNameLength) return NameValidation.tooLong;
  if (!_allowedCharacters.hasMatch(name)) return NameValidation.badChars;
  if (_isBlocked(name)) return NameValidation.blocked;

  return NameValidation.valid;
}

/// Whether [name] matches the blocked lists, separator tricks included.
///
/// Checked three ways, because `f.u.c.k`, `f u c k` and `Fu_ck` are the same
/// attempt wearing different hats:
///
/// 1. the name with every separator stripped, as a substring, against the
///    fragment list — that one check catches all three of the above;
/// 2. the same stripped form as a whole word, against the word list;
/// 3. each separated word on its own, against the word list.
bool _isBlocked(String name) {
  final stripped = _foldForMatching(name);
  if (stripped.isEmpty) return false;

  for (final fragment in _blockedFragments) {
    if (stripped.contains(fragment)) return true;
  }
  if (_blockedWords.contains(stripped)) return true;

  for (final word in name.split(_separators)) {
    final folded = _foldForMatching(word);
    if (folded.isNotEmpty && _blockedWords.contains(folded)) return true;
  }
  return false;
}

/// The allowed non-alphanumeric characters, which is what "a word ends here"
/// means for the wordlist check.
final RegExp _separators = RegExp("[ ._'-]+");

/// Returns [text] lowercased, with separators dropped and leet digits mapped
/// back to the letters they imitate.
///
/// This is the form the wordlist is compared against, and nothing else — the
/// player's actual name is never rewritten by it.
String _foldForMatching(String text) {
  final buffer = StringBuffer();
  for (final character in text.toLowerCase().split('')) {
    final letter = _leetLetters[character];
    if (letter != null) {
      buffer.write(letter);
    } else if (_alphanumeric.hasMatch(character)) {
      buffer.write(character);
    }
    // Anything else is a separator and is simply dropped, which is what
    // collapses `f.u.c.k` onto `fuck`.
  }
  return buffer.toString();
}

final RegExp _alphanumeric = RegExp('[a-z0-9]');
