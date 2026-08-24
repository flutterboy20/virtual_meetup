import 'package:client/core/player_identity.dart';
import 'package:client/features/welcome/view_model/welcome_view_model.dart';
import 'package:client/services/server_status_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_identity_store.dart';

/// A status service that answers from a script.
///
/// The point of the [ServerStatusService] interface: no HTTP, no server, no
/// timeouts, and a test that runs in microseconds.
class _ScriptedStatusService implements ServerStatusService {
  _ScriptedStatusService([this.answers = const [ServerOnline(3)]]);

  List<ServerStatus> answers;
  int calls = 0;

  @override
  Future<ServerStatus> fetch() async {
    final answer = answers[calls.clamp(0, answers.length - 1)];
    calls++;
    return answer;
  }
}

void main() {
  const saved = PlayerIdentity(
    sessionId: FakeIdentityStore.testSessionId,
    name: 'Ada',
    color: 0xFF54C5F8,
    cosmetic: PlayerCosmetic.cap,
  );

  WelcomeViewModel build({
    ServerStatusService? status,
    PlayerIdentity? identity,
  }) {
    final model = WelcomeViewModel(
      status: status ?? _ScriptedStatusService(),
      store: FakeIdentityStore(identity: identity),
    );
    addTearDown(model.dispose);
    return model;
  }

  group('online count', () {
    test('starts loading and knows nothing yet', () {
      final model = build();

      expect(model.isLoading, isTrue);
      expect(model.onlineCount, isNull);
      expect(model.serverStatus, isNull);
    });

    test('reports the count the server gave', () async {
      final model = build(status: _ScriptedStatusService());

      await model.refresh();

      expect(model.isLoading, isFalse);
      expect(model.onlineCount, 3);
      expect(model.isServerReachable, isTrue);
    });

    test('an empty world is a real answer, not a missing one', () async {
      // Zero and "we could not ask" look identical as a number and are
      // opposite as facts, which is why the count is nullable.
      final model = build(
        status: _ScriptedStatusService([const ServerOnline(0)]),
      );

      await model.refresh();

      expect(model.onlineCount, 0);
      expect(model.isServerReachable, isTrue);
    });

    test('an unreachable server leaves the count unknown, not zero', () async {
      final model = build(
        status: _ScriptedStatusService([const ServerUnreachable()]),
      );

      await model.refresh();

      expect(model.onlineCount, isNull);
      expect(model.isServerReachable, isFalse);
      expect(model.isLoading, isFalse);
    });

    test('notifies its listeners when the count arrives', () async {
      final model = build();
      var notifications = 0;
      model.addListener(() => notifications++);

      await model.refresh();

      expect(notifications, 1);
    });

    test('a later refresh replaces the earlier answer', () async {
      final model = build(
        status: _ScriptedStatusService([
          const ServerOnline(3),
          const ServerUnreachable(),
          const ServerOnline(11),
        ]),
      );

      await model.refresh();
      expect(model.onlineCount, 3);
      await model.refresh();
      expect(model.onlineCount, isNull);
      await model.refresh();
      expect(model.onlineCount, 11);
    });
  });

  group('who this device is', () {
    test('a fresh device is not returning', () async {
      final model = build();

      await model.load();

      expect(model.isReturning, isFalse);
      expect(model.identity, isNull);
      expect(model.savedName, isNull);
    });

    test('a device with a saved identity is returning', () async {
      final model = build(identity: saved);

      await model.load();

      expect(model.isReturning, isTrue);
      expect(model.savedName, 'Ada');
      expect(model.identity, equals(saved));
    });

    test('load reads the identity and the count together', () async {
      final status = _ScriptedStatusService();
      final model = build(status: status, identity: saved);

      await model.load();

      expect(model.isReturning, isTrue);
      expect(model.onlineCount, 3);
      expect(status.calls, 1);
    });

    test('reloadIdentity picks up a name changed off screen', () async {
      final store = FakeIdentityStore(identity: saved);
      final model = WelcomeViewModel(
        status: _ScriptedStatusService(),
        store: store,
      );
      addTearDown(model.dispose);
      await model.load();
      expect(model.savedName, 'Ada');

      await store.writeIdentity(saved.copyWith(name: 'Ada L'));
      await model.reloadIdentity();

      expect(model.savedName, 'Ada L');
    });
  });

  group('lifecycle', () {
    test('disposing before an in-flight fetch lands does not throw', () async {
      // Built without the usual teardown, because this test owns the
      // disposal itself.
      final model = WelcomeViewModel(
        status: _ScriptedStatusService(),
        store: FakeIdentityStore(),
      );

      final pending = model.refresh();
      model.dispose();
      await pending;

      // The point is that nothing threw: the answer came back to an object
      // that had already been torn down, and no `notifyListeners` ran.
      expect(model.isLoading, isTrue);
    });

    test('does not start a refresh timer once disposed', () async {
      final status = _ScriptedStatusService();
      final model = WelcomeViewModel(
        status: status,
        store: FakeIdentityStore(),
        refreshInterval: const Duration(milliseconds: 5),
      )..dispose();

      await model.load();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // One from `load` itself; the periodic timer must never have started.
      expect(status.calls, lessThanOrEqualTo(1));
    });
  });
}
