import 'dart:async';
import 'dart:convert';

import 'package:client/core/event_clock.dart';
import 'package:client/services/network_client.dart';
import 'package:flutter/foundation.dart';
import 'package:protocol/protocol.dart';

/// Where the moderation screen is in its own little lifecycle.
enum AdminStage {
  /// Asking for the token. Where every session starts.
  locked,

  /// The token has been sent; waiting for the server to answer.
  authenticating,

  /// Authorised. The player list is live.
  unlocked,
}

/// One thing the screen has to tell the moderator, once.
///
/// Carries a flag rather than a colour: the ViewModel must not import
/// `material.dart` (see `client-architecture.md`), and "this went wrong" is a
/// fact about the world while red is a decision about pixels.
@immutable
class AdminFeedback {
  /// Creates a message.
  const AdminFeedback(this.message, {required this.isError});

  /// What to show.
  final String message;

  /// Whether it is a failure.
  final bool isError;

  @override
  bool operator ==(Object other) =>
      other is AdminFeedback &&
      other.message == message &&
      other.isError == isError;

  @override
  int get hashCode => Object.hash(message, isError);

  @override
  String toString() => 'AdminFeedback($message, isError: $isError)';
}

/// State and commands for the moderation screen.
///
/// No `material.dart` import, on purpose — that is what makes this a plain
/// unit test rather than a widget test.
///
/// The one thing worth noticing about the design: **the token is held here,
/// in memory, and nowhere else.** It is not persisted, not put in
/// `shared_preferences`, and not written into the URL. A moderator's phone
/// that is picked up off a table after the event has no token on it, and a
/// refresh asks for it again. That is a deliberate trade of convenience for
/// the one credential in the project that actually matters.
class AdminViewModel extends ChangeNotifier {
  /// Creates the view model over [network].
  ///
  /// [network] is injected so tests drive a real client over a fake socket,
  /// which is how every other network path in this app is tested.
  AdminViewModel({required NetworkClient network})
    : // A named parameter cannot be private, so this cannot be an
      // initializing formal.
      // ignore: prefer_initializing_formals
      _network = network;

  final NetworkClient _network;

  StreamSubscription<ProtocolMessage>? _messages;
  String _token = '';
  AdminStage _stage = AdminStage.locked;
  String _search = '';
  MapId? _mapFilter;
  List<AdminPlayerSummary> _players = const [];
  int _online = 0;
  Map<MapId, int> _onlineByMap = const {};
  AppConfig _config = AppConfig.defaults;
  int _configRevision = 0;
  AdminFeedback? _feedback;
  bool _disposed = false;

  /// Where the screen is in its lifecycle.
  AdminStage get stage => _stage;

  /// Whether this session has been authorised by the server.
  bool get isUnlocked => _stage == AdminStage.unlocked;

  /// Whether a token has been sent and not yet answered.
  bool get isAuthenticating => _stage == AdminStage.authenticating;

  /// How many people are in the event, on every map together.
  int get online => _online;

  /// How many people are on each map, as the server last reported it.
  Map<MapId, int> get onlineByMap => Map.unmodifiable(_onlineByMap);

  /// Which map the list is filtered to, or `null` for all of them.
  MapId? get mapFilter => _mapFilter;

  /// The count to show on the chip for [map], or on **All** when it is null.
  ///
  /// From the server's own `onlineByMap` rather than counted from the rows,
  /// so a chip can never disagree with the number beside it. Falls back to
  /// counting when an older server sends no breakdown — a chip with a
  /// slightly stale count still beats a chip with none.
  int countFor(MapId? map) {
    if (map == null) return _online;
    final reported = _onlineByMap[map];
    if (reported != null) return reported;
    return _players.where((player) => player.map == map).length;
  }

  /// Everybody in the world, as last reported.
  List<AdminPlayerSummary> get players => List.unmodifiable(_players);

  /// The current search text.
  String get search => _search;

  /// The rows the list should show.
  ///
  /// Filtering lives here rather than in the widget because it is a rule, not
  /// a layout — and because a raw 200-row list on a phone is unusable, which
  /// makes this the feature rather than a nicety. Matches the chosen name and
  /// the player id, so a muted row is still findable by what it used to say
  /// and a report that names an id is actionable.
  ///
  /// **The map filter and the search compose.** They answer different
  /// questions — "where" and "who" — and a moderator acting on a report is
  /// usually holding both halves of the answer at once.
  ///
  /// With **All** selected the rows are grouped by map, so one scroll reads
  /// as both a master list and two per-map lists. Within a map, muted players
  /// come first and then it is alphabetical: the people you have already
  /// acted on are the ones you are most likely to still be watching.
  List<AdminPlayerSummary> get visiblePlayers {
    final needle = _search.trim().toLowerCase();
    final rows = _players.where((player) {
      if (_mapFilter != null && player.map != _mapFilter) return false;
      if (needle.isEmpty) return true;
      return player.name.toLowerCase().contains(needle) ||
          player.id.toLowerCase().contains(needle);
    }).toList();

    return List.unmodifiable(rows..sort(_byMapThenName));
  }

  /// Whether the list should show a heading before each map's rows.
  ///
  /// Only with **All** selected: a heading over a list that is already one
  /// map is a heading that says what the chip above it just said.
  bool get isGroupedByMap => _mapFilter == null;

  static int _byMapThenName(AdminPlayerSummary a, AdminPlayerSummary b) {
    if (a.map != b.map) return a.map.index.compareTo(b.map.index);
    if (a.isNameMuted != b.isNameMuted) return a.isNameMuted ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// The event's config, as the server last reported it.
  AppConfig get config => _config;

  /// [config] as the text the editor shows.
  ///
  /// Pretty-printed rather than compact, because it is meant to be read and
  /// edited by a person on a phone at an event, not diffed by a machine.
  ///
  /// Built from the parsed config rather than echoed back from whatever the
  /// moderator last pasted, so what the editor shows is what the server
  /// actually holds — including the keys they left out, which are the ones
  /// most likely to be the reason they opened it.
  String get configDocument => _prettyJson(_config.toJson());

  /// How many configs the server has sent down this socket.
  ///
  /// A counter rather than a comparison of documents, because the two are not
  /// the same question. A moderator who reorders the keys, fixes the
  /// indentation or deletes a key that was already at its default pushes a
  /// document that comes back **byte-identical to the one before it** — and
  /// an editor watching [configDocument] for a change would sit there
  /// insisting the push had not happened. This ticks on every accepted push,
  /// so "the server answered" is answerable without guessing from the text.
  int get configRevision => _configRevision;

  /// The last thing that happened, for the screen to show once.
  AdminFeedback? get feedback => _feedback;

  /// Whether the socket to the server is currently open.
  bool get isConnected => _network.isConnected;

  /// Connects, then offers [token] to the server.
  ///
  /// Everything about this is a soft failure. A server that is down, a token
  /// that is wrong, a socket that drops between the two — all of them land
  /// the screen back on the token field with a sentence, and none of them
  /// throws into a widget.
  Future<void> submitToken(String token) async {
    if (_stage == AdminStage.authenticating) return;
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      _fail('Enter the moderation token.');
      return;
    }

    _token = trimmed;
    _stage = AdminStage.authenticating;
    _feedback = null;
    _notify();

    _messages ??= _network.messages.listen(_apply);
    await _network.connect();
    if (_disposed) return;

    if (!_network.isConnected) {
      _stage = AdminStage.locked;
      _fail('Could not reach the server.');
      return;
    }
    _network.send(AdminAuthMessage(token: _token));
  }

  /// Updates the search text.
  void setSearch(String value) {
    if (_search == value) return;
    _search = value;
    _notify();
  }

  /// Filters the list to one map, or to all of them when [map] is null.
  ///
  /// Deliberately does **not** clear the search. The two compose, and
  /// silently dropping half of what the moderator typed the moment they tap a
  /// chip is the kind of helpfulness that costs somebody the row they were
  /// looking at.
  void setMapFilter(MapId? map) {
    if (_mapFilter == map) return;
    _mapFilter = map;
    _notify();
  }

  /// Disconnects [playerId]. They may rejoin.
  void kick(String playerId) => _send(AdminKickMessage(playerId: playerId));

  /// Disconnects [playerId] and blocks their session for the event.
  void ban(String playerId) => _send(AdminBanMessage(playerId: playerId));

  /// Takes [playerId]'s name away, or gives it back.
  void setNameMuted(String playerId, {required bool muted}) =>
      _send(AdminMuteNameMessage(playerId: playerId, muted: muted));

  /// Replaces the event's config with [document].
  ///
  /// The raw text goes up exactly as typed. This end deliberately does not
  /// parse it first: the server is the thing that holds the config, so the
  /// server is the thing that gets to say whether a document is one — and a
  /// screen that pre-approved a document the server then rejected would be
  /// lying to the only person who can fix it.
  ///
  /// The one check here is that there is *something* to send, because an
  /// empty box is a slip rather than an intention.
  void pushConfig(String document) {
    if (document.trim().isEmpty) {
      _fail('There is nothing in the editor to push.');
      return;
    }
    _send(AdminSetConfigMessage(document: document));
  }

  /// Sets how many bots [map] shows, and pushes it.
  ///
  /// The dial and the editor are two views of one document, which is why
  /// this rebuilds the whole config rather than sending a number: there is
  /// one config on the server, and a second message type that edited one
  /// field of it would be a second way for the two to disagree.
  ///
  /// Clamped at zero. A negative crowd is not a thing, and the server would
  /// drop the key rather than the sign — leaving the dial reading -1 and the
  /// map showing everybody.
  void setBotCount(MapId map, int count) {
    final counts = Map<MapId, int>.from(_config.botCounts)
      ..[map] = count < 0 ? 0 : count;
    pushConfig(_prettyJson(_config.withBotCounts(counts).toJson()));
  }

  /// Puts [map] back to showing its whole roster.
  ///
  /// Deleting the key rather than writing a big number, because "as many as
  /// there are" and "at most forty" are different intentions and only one of
  /// them survives somebody adding a bean to the roster later.
  void clearBotCount(MapId map) {
    if (_config.botCountFor(map) == null) return;
    final counts = Map<MapId, int>.from(_config.botCounts)..remove(map);
    pushConfig(_prettyJson(_config.withBotCounts(counts).toJson()));
  }

  /// How many bots [map] is set to show, or `null` for its whole roster.
  int? botCountFor(MapId map) => _config.botCountFor(map);

  /// When the event reopens, or `null` when it is open.
  DateTime? get maintenanceUntil => _config.maintenanceUntil;

  /// Whether the event is currently closed to attendees.
  bool get isUnderMaintenance => _config.isUnderMaintenanceAt(DateTime.now());

  /// Closes the event until [until], or reopens it when that is `null`.
  ///
  /// Takes the token as an argument rather than reusing the one this object
  /// is holding, because the point of asking again is that it is *asked*. A
  /// method that quietly reached for `_token` would give the confirmation
  /// dialog the shape of a security check and none of the substance, and the
  /// server — which is where the check actually happens — would accept it
  /// either way.
  ///
  /// Both refusals here are courtesies to the person tapping, not controls:
  /// the server re-checks the token and re-checks the time, and would refuse
  /// exactly the same two things if these lines were deleted.
  void setMaintenance({required String token, DateTime? until}) {
    if (token.trim().isEmpty) {
      _fail('Enter the moderation token to confirm.');
      return;
    }
    if (until != null && !until.isAfter(DateTime.now())) {
      _fail('That time has already passed.');
      return;
    }
    _send(
      AdminSetMaintenanceMessage(token: token.trim(), until: until?.toUtc()),
    );
  }

  /// Clears the last message, once the screen has shown it.
  void clearFeedback() {
    if (_feedback == null) return;
    _feedback = null;
    _notify();
  }

  /// Forgets the token and drops back to the locked screen.
  void lock() {
    _token = '';
    _stage = AdminStage.locked;
    _players = const [];
    _online = 0;
    _onlineByMap = const {};
    _mapFilter = null;
    _search = '';
    _config = AppConfig.defaults;
    _feedback = null;
    // Disconnected, not disposed: the same screen has to be unlockable
    // again without being rebuilt, and a disposed client cannot reconnect.
    unawaited(_network.disconnect());
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _token = '';
    unawaited(_messages?.cancel());
    _messages = null;
    unawaited(_network.dispose());
    super.dispose();
  }

  /// Sends a privileged message, or explains why it did not.
  ///
  /// The [isUnlocked] check here is a courtesy to the moderator, not a
  /// security control: the server refuses every one of these on its own, and
  /// would refuse them just as firmly if this line were deleted. Hiding a
  /// button is not authorization.
  static String _prettyJson(Map<String, Object?> json) =>
      const JsonEncoder.withIndent('  ').convert(json);

  void _send(ProtocolMessage message) {
    if (!isUnlocked) {
      _fail('Not authorised.');
      return;
    }
    if (!_network.isConnected) {
      _fail('Not connected — the action was not sent.');
      return;
    }
    _network.send(message);
  }

  void _apply(ProtocolMessage message) {
    switch (message) {
      case AdminAuthResultMessage():
        _stage = message.authorized ? AdminStage.unlocked : AdminStage.locked;
        if (!message.authorized) _token = '';
        _feedback = AdminFeedback(
          message.detail,
          isError: !message.authorized,
        );
        _notify();

      case AdminPlayerListMessage():
        _players = message.players;
        _online = message.online;
        _onlineByMap = message.onlineByMap;
        _notify();

      case AdminActionResultMessage():
        _feedback = AdminFeedback(
          _describe(message.action, message.targetName),
          isError: false,
        );
        _notify();

      case ConfigMessage():
        // Sent on authentication and again after every accepted push, so the
        // editor always shows what is live rather than what was typed.
        _config = message.config;
        _configRevision++;
        _notify();

      case AdminErrorMessage():
        // An `unauthorized` here means the server disagrees with what this
        // screen believes about itself — a restarted server, or a token that
        // was rotated mid-event. The server is right, so the screen locks.
        if (message.reason == AdminError.unauthorized) {
          _stage = AdminStage.locked;
          _token = '';
        }
        _feedback = AdminFeedback(message.detail, isError: true);
        _notify();

      case JoinMessage():
      case MoveMessage():
      case EmoteMessage():
      case BoardMessage():
      case WelcomeMessage():
      case SnapshotMessage():
      case PlayerLeftMessage():
      case JoinRejectedMessage():
      case PlayerEmotedMessage():
      case PlayerBoardMessage():
      case WorldStatsMessage():
      case AdminAuthMessage():
      case AdminKickMessage():
      case AdminBanMessage():
      case AdminMuteNameMessage():
      case AdminSetConfigMessage():
      case AdminSetMaintenanceMessage():
      case UnknownMessage():
        // Nothing on the admin socket sends these *back*. Ignored rather than
        // handled: this screen moderates and does nothing else.
        break;
    }
  }

  static String _describe(AdminAction action, String name) => switch (action) {
    AdminAction.kick => 'Kicked $name.',
    AdminAction.ban => 'Banned $name.',
    AdminAction.muteName => '$name is now showing as $mutedDisplayName.',
    AdminAction.unmuteName => '$name has their name back.',
    // The "name" of a maintenance action is the reopening time, because the
    // action has no target to name. Read back on the moderator's own clock,
    // not the server's: they picked a wall-clock time and are owed the same
    // one back, or they cannot tell a success from an off-by-five-hours.
    AdminAction.maintenanceOn =>
      'The event is closed until '
          '${_formatWireMoment(name)}.',
    AdminAction.maintenanceOff => 'The event is open again.',
  };

  /// Formats an ISO-8601 instant that came off the wire, falling back to the
  /// raw text.
  ///
  /// The fallback matters: this string is a *confirmation*, and a confirmation
  /// that throws because a server sent a shape this build did not expect
  /// would turn a successful action into a crash.
  static String _formatWireMoment(String raw) {
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : formatLocalMoment(parsed);
  }

  void _fail(String message) {
    _feedback = AdminFeedback(message, isError: true);
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
