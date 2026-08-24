import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:protocol/src/map_id.dart';

/// Everything about this event that a moderator can change without a rebuild.
///
/// Started as the words on the front door and is now the whole editable
/// surface of the world: the wordmark, the two lines around it, the Code Lab's
/// projector, the hall's screen, and how many beans stand around each map.
///
/// It lives in `protocol/` rather than in the client because **the server
/// holds it**. A moderator pushes a document up the admin socket, the server
/// writes it to disk and hands it to everybody who is connected, and the
/// welcome screen fetches it over HTTP before anybody has a socket at all.
/// Two ends have to agree on this shape, so it is defined once, here — the
/// same rule every message in this package follows.
///
/// The whole type is **defaults with overrides**, not required fields. A front
/// door that renders nothing because a fetched document was truncated is a
/// worse failure than one showing last week's tagline, and the same rule the
/// online count follows applies here: the network never blocks the door.
@immutable
class AppConfig {
  /// Creates a config, falling back to the built-in copy for anything absent.
  const AppConfig({
    this.worldName = defaultWorldName,
    this.eyebrow = defaultEyebrow,
    this.tagline = defaultTagline,
    this.boardMessage = defaultBoardMessage,
    this.stageLines = defaultStageLines,
    this.botCounts = const {},
    this.maintenanceUntil,
  });

  /// Reads a config from one decoded JSON document.
  ///
  /// Never throws. A key that is missing, empty or not a string falls back to
  /// the built-in copy on its own, so half a bad document still gets the half
  /// that was fine onto the screen.
  factory AppConfig.fromJson(Map<String, Object?> json) {
    String text(String key, String fallback) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      return fallback;
    }

    // Falls back **whole**, not per entry. A list is a script somebody wrote
    // in an order they meant; half of one, with the built-in jokes filling
    // the gaps, is neither their script nor ours.
    List<String> lines(String key, List<String> fallback) {
      final value = json[key];
      if (value is! List) return fallback;
      final kept = [
        for (final entry in value)
          if (entry is String && entry.trim().isNotEmpty) entry.trim(),
      ];
      return kept.isEmpty ? fallback : List.unmodifiable(kept);
    }

    return AppConfig(
      worldName: text('worldName', defaultWorldName),
      eyebrow: text('eyebrow', defaultEyebrow),
      tagline: text('tagline', defaultTagline),
      boardMessage: text('boardMessage', defaultBoardMessage),
      stageLines: lines('stageLines', defaultStageLines),
      botCounts: _readBotCounts(json['botCounts']),
      maintenanceUntil: _readInstant(json['maintenanceUntil']),
    );
  }

  /// The copy the app ships with, used until — and instead of — a fetched one.
  static const AppConfig defaults = AppConfig();

  /// The wordmark on the front door: whose event this world is.
  ///
  /// Deliberately generic out of the box. An organiser sets their own name
  /// here rather than editing a widget.
  static const String defaultWorldName = 'Virtual Conference';

  /// The small capsule over the wordmark, shown in caps by the welcome screen.
  static const String defaultEyebrow = 'A LITTLE WORLD FOR PEOPLE WHO SHOW UP';

  /// The line under the wordmark.
  static const String defaultTagline = 'Pick a bean · walk around · say hi';

  /// What the Code Lab's projector says out of the box.
  ///
  /// A joke, and deliberately one an organiser will want to replace — which
  /// is the whole reason it is config. A line painted into the map would need
  /// a rebuild and a redeploy to change; this one needs a reload.
  static const String defaultBoardMessage =
      'setState is best state-management in flutter';

  /// What the hall's screen says when nobody has written a programme.
  ///
  /// Jokes, on purpose. The hall is the room whose whole job is to look like
  /// something is happening in it, and a screen cycling seven punchlines is
  /// the cheapest possible way to make an empty room read as a room between
  /// sessions rather than as a broken server.
  static const List<String> defaultStageLines = [
    'NEXT UP: Rebuilding Everything, Twice',
    'A talk about setState, by someone who lost the argument',
    'Live demo. What could go wrong.',
    'Widget tree considered harmful (it is not)',
    'Please silence your hot reloads',
    'Q&A: yes, it also runs on the web',
    'Coffee is one room west',
  ];

  /// The wordmark on the front door.
  final String worldName;

  /// The line over the wordmark.
  final String eyebrow;

  /// The line under the wordmark.
  final String tagline;

  /// The line painted on the Code Lab's projector screen.
  ///
  /// Read before the game is built and handed to the map, which paints it
  /// into the static furniture picture with everything else — so it costs
  /// nothing per frame. See `ConferenceMap.boardMessage`.
  final String boardMessage;

  /// The lines the hall's stage screen cycles through.
  ///
  /// A list rather than one string, and live rather than baked: the furniture
  /// picture is a recording, and a recorded sentence never changes. See
  /// `StageScreenComponent`.
  final List<String> stageLines;

  /// How many bots each map should show, for the maps that say.
  ///
  /// **A cap, not a target.** A map missing from this list shows its whole
  /// roster, and a number larger than the roster shows the whole roster too —
  /// bots are drawn from a hand-placed list of positions, so there is no
  /// twentieth bean to invent when somebody types 20.
  ///
  /// Client-side to the last byte, like the bots themselves. This number rides
  /// in the config only because a moderator needs a dial for it; the server
  /// stores it and forwards it and has still never heard of a bot.
  final Map<MapId, int> botCounts;

  /// When the event stops being closed, or `null` when it is open.
  ///
  /// Held in UTC and written to the wire as ISO-8601, because the two ends of
  /// this are a server in one place and a phone in another and "half past
  /// six" is not a fact until you say whose half past six it is. Every screen
  /// that shows it converts to the reader's own clock.
  ///
  /// A **moment**, not a flag. A boolean would need somebody to remember to
  /// turn it off — at the end of a maintenance window that has probably
  /// overrun, by a person who has gone home — and the failure mode of
  /// forgetting is an event nobody can get into. This expires on its own.
  ///
  /// It lives in the config rather than in a store of its own because the
  /// config is already the one document that is served over HTTP before
  /// anybody has a socket, pushed to everybody who has one, and kept across a
  /// restart. Those are exactly the three things a maintenance window needs,
  /// and none of them had to be built twice.
  final DateTime? maintenanceUntil;

  /// Whether the event is closed to attendees at [now].
  ///
  /// The one question anything should ask about [maintenanceUntil]. Reading
  /// the field and comparing by hand is how two places end up disagreeing
  /// about whether the boundary moment is in or out.
  bool isUnderMaintenanceAt(DateTime now) {
    final until = maintenanceUntil;
    return until != null && now.toUtc().isBefore(until);
  }

  /// How many bots [map] should show, or `null` for all of them.
  int? botCountFor(MapId map) => botCounts[map];

  /// Returns a copy of this config with [botCounts] replaced.
  ///
  /// The bot-count panel on the admin screen edits one number at a time and
  /// has to send a whole document; this is how it builds one without asking a
  /// moderator to hand-edit JSON to move a dial.
  AppConfig withBotCounts(Map<MapId, int> counts) => AppConfig(
    worldName: worldName,
    eyebrow: eyebrow,
    tagline: tagline,
    boardMessage: boardMessage,
    stageLines: stageLines,
    botCounts: Map.unmodifiable(counts),
    maintenanceUntil: maintenanceUntil,
  );

  /// Returns a copy of this config closed until [until], or open when it is
  /// `null`.
  ///
  /// The dial's counterpart, for the same reason: the maintenance card edits
  /// one moment and has to send a whole document, and a moderator should not
  /// have to hand-write an ISO-8601 timestamp into JSON to pause an event.
  AppConfig withMaintenanceUntil(DateTime? until) => AppConfig(
    worldName: worldName,
    eyebrow: eyebrow,
    tagline: tagline,
    boardMessage: boardMessage,
    stageLines: stageLines,
    botCounts: botCounts,
    maintenanceUntil: until?.toUtc(),
  );

  /// Returns the JSON form of this config.
  ///
  /// The exact shape [AppConfig.fromJson] reads, so a config that has been
  /// through the server and back is the config that went in. That round trip
  /// is what the admin screen's editor relies on: it shows this text, a
  /// moderator edits it, and it goes back the way it came.
  Map<String, Object?> toJson() => {
    'worldName': worldName,
    'eyebrow': eyebrow,
    'tagline': tagline,
    'boardMessage': boardMessage,
    'stageLines': stageLines,
    'botCounts': {
      for (final entry in botCounts.entries) entry.key.id: entry.value,
    },
    // Written even when it is null, on purpose. This document is also the
    // thing a moderator edits by hand, and a key that only exists once
    // somebody has already used the feature is a key nobody discovers.
    'maintenanceUntil': maintenanceUntil?.toUtc().toIso8601String(),
  };

  /// Reads an ISO-8601 instant, or `null` for anything that is not one.
  ///
  /// Tolerant like every other reader here: a truncated timestamp, a number,
  /// a missing key all mean "the event is open". The strict alternative would
  /// let one mistyped character in a hand-edited file shut an event that
  /// nobody meant to shut, and refuse to say why.
  static DateTime? _readInstant(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  static Map<MapId, int> _readBotCounts(Object? value) {
    if (value is! Map) return const {};
    final counts = <MapId, int>{};
    for (final entry in value.entries) {
      final map = MapId.tryFromId(entry.key as String?);
      final count = entry.value;
      // Negative is not "none", it is a typo. A map named with a broken
      // number keeps its whole roster rather than emptying itself.
      if (map != null && count is int && count >= 0) counts[map] = count;
    }
    return Map.unmodifiable(counts);
  }

  @override
  bool operator ==(Object other) =>
      other is AppConfig &&
      other.worldName == worldName &&
      other.eyebrow == eyebrow &&
      other.tagline == tagline &&
      other.boardMessage == boardMessage &&
      other.maintenanceUntil == maintenanceUntil &&
      _sameLines(other.stageLines, stageLines) &&
      _sameCounts(other.botCounts, botCounts);

  @override
  int get hashCode => Object.hash(
    worldName,
    eyebrow,
    tagline,
    boardMessage,
    Object.hashAll(stageLines),
    Object.hashAll(
      botCounts.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    maintenanceUntil,
  );

  static bool _sameLines(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameCounts(Map<MapId, int> a, Map<MapId, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  String toString() => 'AppConfig($worldName / $eyebrow / $tagline)';
}

/// Parses a config document, whatever state it arrives in.
///
/// A free function so the parsing — the part with rules in it — is unit
/// testable without a repository, a bundle or a server.
///
/// Unlike `parseSponsors`, this one swallows everything: unreadable JSON, a
/// list where an object was expected, a null body. Sponsors are structure and
/// a broken booth should be loud; this is a screen full of marketing copy, and
/// the only sane response to a broken one is the copy we already had.
///
/// Use [tryParseAppConfig] where somebody is waiting to be told they made a
/// mistake — which is exactly once, on the admin screen.
AppConfig parseAppConfig(String raw) =>
    tryParseAppConfig(raw) ?? AppConfig.defaults;

/// Parses a config document, or answers `null` if it is not one.
///
/// The strict half of the pair, and the difference matters in one place: a
/// moderator pasting a document into the admin screen at nine in the morning
/// needs to be **told** their JSON has a trailing comma in it. Silently
/// serving the built-in copy would look exactly like a push that worked, and
/// they would find out from the room.
///
/// Strict about the *document*, not about its contents: an object missing
/// every key parses fine and means "all defaults". The only failures here are
/// text that is not JSON and JSON that is not an object.
AppConfig? tryParseAppConfig(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  return AppConfig.fromJson(decoded);
}
