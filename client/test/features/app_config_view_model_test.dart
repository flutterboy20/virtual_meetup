import 'package:client/features/app_config/view_model/app_config_view_model.dart';
import 'package:client/services/app_config_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// A repository that answers with whatever the test says, or throws.
class _FakeRepository implements AppConfigRepository {
  _FakeRepository({this.config, this.fails = false});

  final AppConfig? config;
  final bool fails;
  int calls = 0;

  @override
  Future<AppConfig> load() async {
    calls++;
    if (fails) throw StateError('no network');
    return config ?? AppConfig.defaults;
  }
}

void main() {
  test('shows the built-in copy before anybody has answered', () {
    final model = AppConfigViewModel(repository: _FakeRepository());
    addTearDown(model.dispose);

    // The first frame has to render real words, not a blank door.
    expect(model.config, equals(AppConfig.defaults));
    expect(model.isLoaded, isFalse);
  });

  test('swaps in the loaded copy and says so', () async {
    const fetched = AppConfig(eyebrow: 'A tiny world', tagline: 'day two');
    final repository = _FakeRepository(config: fetched);
    final model = AppConfigViewModel(repository: repository);
    addTearDown(model.dispose);

    var notified = 0;
    model.addListener(() => notified++);

    await model.load();

    expect(model.config, equals(fetched));
    expect(model.isLoaded, isTrue);
    expect(notified, equals(1));
    expect(repository.calls, equals(1));
  });

  test('a failed load is not an error, it is the built-in copy', () async {
    // The whole reason this ViewModel exists rather than a bare `await` in
    // the view: copy on a lobby screen must never surface an exception.
    final model = AppConfigViewModel(repository: _FakeRepository(fails: true));
    addTearDown(model.dispose);

    await model.load();

    expect(model.config, equals(AppConfig.defaults));
    expect(model.isLoaded, isTrue);
  });

  test('does not notify after being disposed', () async {
    // The app-level provider outlives no screen, but a hot restart or a
    // route swap can dispose it while a load is still in flight.
    final model = AppConfigViewModel(repository: _FakeRepository());
    var notified = 0;
    model.addListener(() => notified++);

    final pending = model.load();
    model.dispose();
    await pending;

    expect(notified, isZero);
  });

  group('a config pushed down the socket', () {
    test('replaces what the repository answered with', () async {
      // The other half of `load`: the repository answers once, before anybody
      // is in the world, and from there on the server pushes.
      final model = AppConfigViewModel(repository: _FakeRepository());
      addTearDown(model.dispose);
      await model.load();

      model.update(const AppConfig(worldName: 'DashConf'));

      expect(model.config.worldName, equals('DashConf'));
    });

    test('an identical config does not notify', () async {
      // The server pushes on every join. A notify per arrival would rebuild
      // the app's whole subtree to say nothing.
      final model = AppConfigViewModel(repository: _FakeRepository());
      addTearDown(model.dispose);
      await model.load();
      var notified = 0;
      model.addListener(() => notified++);

      model
        ..update(model.config)
        ..update(model.config);

      expect(notified, isZero);
    });

    test('a push before the repository has answered still lands', () async {
      // The socket can beat the fetch on a slow network, and the newer
      // answer is the socket's either way.
      final model = AppConfigViewModel(repository: _FakeRepository());
      addTearDown(model.dispose);

      model.update(const AppConfig(worldName: 'DashConf'));

      expect(model.config.worldName, equals('DashConf'));
      expect(model.isLoaded, isTrue);
    });

    test('a disposed model does not notify', () async {
      final model = AppConfigViewModel(repository: _FakeRepository());
      var notified = 0;
      model
        ..addListener(() => notified++)
        ..dispose()
        ..update(const AppConfig(worldName: 'DashConf'));

      expect(notified, isZero);
    });
  });
}
