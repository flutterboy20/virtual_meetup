import 'dart:async';

import 'package:client/core/player_identity.dart';
import 'package:client/services/identity_store.dart';
import 'package:client/services/server_status_service.dart';
import 'package:flutter/foundation.dart';
import 'package:protocol/protocol.dart';

/// State and commands for the welcome screen.
///
/// No `material.dart` import, on purpose — that is what makes this a plain
/// unit test instead of a widget test (see `client-architecture.md`). It
/// holds two facts: how many people are in the world, and whether this device
/// already knows who it is.
class WelcomeViewModel extends ChangeNotifier {
  /// Creates the view model.
  ///
  /// [refreshInterval] is how often the online count is re-read while the
  /// screen is open. Injectable so a test can drive it, though the tests here
  /// call [refresh] directly rather than waiting on a timer.
  WelcomeViewModel({
    required ServerStatusService status,
    required IdentityStore store,
    this.refreshInterval = const Duration(seconds: 5),
  }) : // Named parameters cannot be private, so neither of these can be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _status = status,
       // A named parameter cannot be private.
       // ignore: prefer_initializing_formals
       _store = store;

  final ServerStatusService _status;
  final IdentityStore _store;

  /// How often the online count is re-read.
  final Duration refreshInterval;

  Timer? _timer;
  bool _disposed = false;
  bool _isLoading = true;
  ServerStatus? _serverStatus;
  PlayerIdentity? _identity;
  MapId _selectedMap = MapId.conference;

  /// Whether the first load is still in flight.
  bool get isLoading => _isLoading;

  /// The last answer from the server, or `null` before the first one.
  ServerStatus? get serverStatus => _serverStatus;

  /// How many people are in the event, or `null` if that is not known.
  int? get onlineCount => switch (_serverStatus) {
    ServerOnline(:final players) => players,
    // Deliberately null rather than zero. "0 people are here" and "we could
    // not ask" look identical as a number and are opposite as facts.
    ServerUnreachable() || null => null,
  };

  /// Which map the player is about to walk into.
  ///
  /// Loaded from the device, so a returning player lands back where they
  /// were, and written back the moment they pick the other one — not when
  /// they press Join. Somebody who taps Beach and then closes the tab meant
  /// the beach.
  MapId get selectedMap => _selectedMap;

  /// How many people are on [map], or `null` if that is not known.
  ///
  /// Null on an older server that does not report the breakdown, and the
  /// cards then show without counts. A zero would be a lie, and on this
  /// particular screen it is the *discouraging* lie.
  int? playersOn(MapId map) => switch (_serverStatus) {
    ServerOnline(:final byMap) => byMap[map],
    ServerUnreachable() || null => null,
  };

  /// Whether the server answered the last time we asked.
  bool get isServerReachable => _serverStatus is ServerOnline;

  /// The saved identity, or `null` if this device has never been set up.
  PlayerIdentity? get identity => _identity;

  /// Whether this device already has a name and a bean.
  ///
  /// The whole point of the welcome screen's Join button: a returning player
  /// goes straight into the world, and only a new one is sent to setup.
  bool get isReturning => _identity != null;

  /// The saved display name, for the "continue as…" label.
  String? get savedName => _identity?.name;

  /// Changes which map Join will walk into, and remembers it.
  ///
  /// Returns straight away and persists in the background: the card has to
  /// light up under a thumb, and a write to local storage is not something to
  /// make somebody wait for.
  void selectMap(MapId map) {
    if (_selectedMap == map) return;
    _selectedMap = map;
    notifyListeners();
    unawaited(_store.writeMapId(map));
  }

  /// Loads the saved identity and the online count, then starts refreshing.
  Future<void> load() async {
    _identity = await _store.readIdentity();
    _selectedMap = await _store.readMapId();
    if (_disposed) return;
    notifyListeners();

    await refresh();
    if (_disposed) return;

    _timer ??= Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
  }

  /// Re-reads the online count.
  Future<void> refresh() async {
    final result = await _status.fetch();
    if (_disposed) return;
    _serverStatus = result;
    _isLoading = false;
    notifyListeners();
  }

  /// Re-reads the saved identity.
  ///
  /// Called when returning to this screen from setup, so the Join button
  /// reflects a name that was chosen while it was off screen.
  Future<void> reloadIdentity() async {
    _identity = await _store.readIdentity();
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
