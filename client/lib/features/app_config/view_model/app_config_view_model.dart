import 'package:client/services/app_config_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:protocol/protocol.dart';

/// Holds the app's configuration for whatever screen wants to read it.
///
/// No `material.dart` import, on purpose — that is what makes this a plain
/// unit test instead of a widget test (see `client-architecture.md`).
///
/// It is provided above the whole app rather than per screen because config
/// is not one screen's business: today it is two lines of copy on the front
/// door, and the next thing that wants to be editable without a rebuild will
/// find it already here.
class AppConfigViewModel extends ChangeNotifier {
  /// Creates the view model over [repository].
  AppConfigViewModel({required AppConfigRepository repository})
    : // A named parameter cannot be private, so this cannot be an
      // initializing formal.
      // ignore: prefer_initializing_formals
      _repository = repository;

  final AppConfigRepository _repository;

  AppConfig _config = AppConfig.defaults;
  bool _isLoaded = false;
  bool _disposed = false;

  /// The current configuration.
  ///
  /// Never null and never empty: it starts as [AppConfig.defaults], so the
  /// first frame renders real words before the repository has answered and
  /// keeps rendering them if it never does.
  AppConfig get config => _config;

  /// Whether an answer has come back yet.
  ///
  /// Exposed for tests and for anything that wants to wait; the views do not
  /// branch on it, because there is nothing to wait for — the defaults are
  /// already good enough to show.
  bool get isLoaded => _isLoaded;

  /// Reads the configuration.
  ///
  /// Swallows failures by design. This is copy on a lobby screen; if it
  /// cannot be fetched, the built-in copy is a perfectly good answer and an
  /// error here must never reach a person.
  Future<void> load() async {
    try {
      _config = await _repository.load();
    } on Object {
      _config = AppConfig.defaults;
    }
    if (_disposed) return;
    _isLoaded = true;
    notifyListeners();
  }

  /// Takes a config the server pushed down the socket.
  ///
  /// The other half of [load]. The repository answers once, before anybody is
  /// in the world; this arrives on join and again every time a moderator
  /// changes something, which is what makes an edit show up on two hundred
  /// screens without two hundred reloads.
  ///
  /// Ignores a config identical to the one already held, because the server
  /// pushes on every join and a notify per arrival would rebuild the app's
  /// whole subtree for nothing.
  void update(AppConfig config) {
    if (_disposed || config == _config) return;
    _config = config;
    _isLoaded = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
