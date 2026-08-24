import 'package:client/core/player_identity.dart';
import 'package:client/game/joystick_side.dart';
import 'package:client/services/identity_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  // A real `SharedPreferencesIdentityStore` over an in-memory platform, so
  // the *store* is under test rather than a fake of it — key names, the
  // "generate a session id once" rule, and the round trip all included.
  late _InMemoryPreferences platform;
  late SharedPreferencesIdentityStore store;

  setUp(() {
    platform = _InMemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = platform;
    store = SharedPreferencesIdentityStore();
  });

  group('session id', () {
    test('is generated once and then kept', () async {
      final first = await store.sessionId();
      final second = await store.sessionId();

      expect(isValidSessionId(first), isTrue);
      expect(second, equals(first));
    });

    test('survives a new store over the same storage', () async {
      // The refresh case: a whole new app instance reading the same origin's
      // local storage has to come back as the same player.
      final first = await store.sessionId();

      final reopened = SharedPreferencesIdentityStore();

      expect(await reopened.sessionId(), equals(first));
    });

    test('two devices do not share one', () async {
      final mine = await store.sessionId();

      SharedPreferencesAsyncPlatform.instance = _InMemoryPreferences();
      final theirs = await SharedPreferencesIdentityStore().sessionId();

      expect(theirs, isNot(equals(mine)));
    });

    test('a corrupted stored id is replaced rather than sent', () async {
      // Local storage is editable by anybody with a dev console. A malformed
      // id would be rejected by the server, leaving somebody permanently
      // unable to join with no way to tell why.
      await platform.setString(
        '${identityKeyPrefix}sessionId',
        'not-a-session-id',
        const SharedPreferencesOptions(),
      );

      final id = await store.sessionId();

      expect(isValidSessionId(id), isTrue);
      expect(id, isNot('not-a-session-id'));
    });
  });

  group('identity', () {
    test('is null until something is saved', () async {
      expect(await store.readIdentity(), isNull);
    });

    test('round-trips everything the player chose', () async {
      final identity = PlayerIdentity(
        sessionId: await store.sessionId(),
        name: 'Ada Lovelace',
        color: 0xFFF2B33D,
        cosmetic: PlayerCosmetic.headphones,
      );

      await store.writeIdentity(identity);

      expect(await store.readIdentity(), equals(identity));
    });

    test('an unknown saved cosmetic reads as a bare head', () async {
      // Forward compatibility, the same rule the wire has: a hat from a
      // newer build must not make the whole identity unreadable.
      final identity = PlayerIdentity(
        sessionId: await store.sessionId(),
        name: 'Ada',
        color: 1,
        cosmetic: PlayerCosmetic.cap,
      );
      await store.writeIdentity(identity);
      await platform.setString(
        '${identityKeyPrefix}cosmetic',
        'jetpack',
        const SharedPreferencesOptions(),
      );

      expect((await store.readIdentity())?.cosmetic, PlayerCosmetic.none);
    });

    test('writing an identity adopts its session id', () async {
      const identity = PlayerIdentity(
        sessionId: 'ffffffffffffffffffffffffffffffff',
        name: 'Ada',
        color: 1,
        cosmetic: PlayerCosmetic.none,
      );

      await store.writeIdentity(identity);

      expect(await store.sessionId(), equals(identity.sessionId));
    });
  });

  group('joystick side', () {
    test('defaults to the right', () async {
      expect(await store.readJoystickSide(), JoystickSide.right);
    });

    test('round-trips', () async {
      await store.writeJoystickSide(JoystickSide.left);

      expect(await store.readJoystickSide(), JoystickSide.left);
    });

    test('an unrecognised saved value falls back to the default', () async {
      await platform.setString(
        '${identityKeyPrefix}joystickSide',
        'sideways',
        const SharedPreferencesOptions(),
      );

      expect(await store.readJoystickSide(), JoystickSide.right);
    });
  });

  group('the board', () {
    test('a device that has never found it reads false', () async {
      expect(await store.readHasBoard(), isFalse);
    });

    test('round-trips, both ways', () async {
      await store.writeHasBoard(hasBoard: true);
      expect(await store.readHasBoard(), isTrue);

      await store.writeHasBoard(hasBoard: false);
      expect(await store.readHasBoard(), isFalse);
    });

    test('survives a new store over the same storage', () async {
      // The refresh case. A secret that had to be re-hunted after every
      // reload would be a chore rather than a secret.
      await store.writeHasBoard(hasBoard: true);

      expect(await SharedPreferencesIdentityStore().readHasBoard(), isTrue);
    });

    test('clearIdentity forgets it', () async {
      // Logging out is "I am not this person any more", and the next person
      // to pick this phone up has not found anything.
      await store.writeHasBoard(hasBoard: true);

      await store.clearIdentity();

      expect(await store.readHasBoard(), isFalse);
    });

    test('clear forgets it too', () async {
      await store.writeHasBoard(hasBoard: true);

      await store.clear();

      expect(await store.readHasBoard(), isFalse);
    });

    test('editing the identity keeps it', () async {
      // A name change is not a new person: it keeps the session id, and it
      // has to keep the board with it.
      await store.writeHasBoard(hasBoard: true);
      await store.writeIdentity(
        PlayerIdentity(
          sessionId: await store.sessionId(),
          name: 'Ada',
          color: 1,
          cosmetic: PlayerCosmetic.cap,
        ),
      );

      expect(await store.readHasBoard(), isTrue);
    });

    test('a map switch keeps it', () async {
      await store.writeHasBoard(hasBoard: true);
      await store.writeMapId(MapId.beach);
      await store.writeMapId(MapId.conference);

      expect(await store.readHasBoard(), isTrue);
    });
  });

  group('clear', () {
    test('forgets the identity, the settings and the session id', () async {
      // The session id goes too: this is the "not me any more" button, and
      // keeping the id would hand the next person the previous one's seat.
      final before = await store.sessionId();
      await store.writeIdentity(
        PlayerIdentity(
          sessionId: before,
          name: 'Ada',
          color: 1,
          cosmetic: PlayerCosmetic.cap,
        ),
      );
      await store.writeJoystickSide(JoystickSide.left);
      await store.writeHasBoard(hasBoard: true);

      await store.clear();

      expect(await store.readIdentity(), isNull);
      expect(await store.readJoystickSide(), JoystickSide.right);
      expect(await store.readHasBoard(), isFalse);
      expect(await store.sessionId(), isNot(equals(before)));
    });

    test('clearing an empty store is not an error', () async {
      await store.clear();

      expect(await store.readIdentity(), isNull);
    });
  });

  test('every key it owns is namespaced to this app', () async {
    // On the web these land in the origin's local storage, shared with
    // anything else served from the same host.
    await store.writeIdentity(
      PlayerIdentity(
        sessionId: await store.sessionId(),
        name: 'Ada',
        color: 1,
        cosmetic: PlayerCosmetic.cap,
      ),
    );
    await store.writeJoystickSide(JoystickSide.left);
    await store.writeHasBoard(hasBoard: true);

    expect(platform.values.keys, isNotEmpty);
    for (final key in platform.values.keys) {
      expect(key, startsWith(identityKeyPrefix), reason: key);
    }
  });
}

/// A `SharedPreferencesAsync` backend that lives in a map.
base class _InMemoryPreferences extends SharedPreferencesAsyncPlatform {
  /// Everything currently stored.
  final Map<String, Object> values = {};

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async =>
      values[key] as bool?;

  @override
  Future<double?> getDouble(
    String key,
    SharedPreferencesOptions options,
  ) async => values[key] as double?;

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async =>
      values[key] as int?;

  @override
  Future<String?> getString(
    String key,
    SharedPreferencesOptions options,
  ) async => values[key] as String?;

  @override
  Future<List<String>?> getStringList(
    String key,
    SharedPreferencesOptions options,
  ) async => (values[key] as List<String>?)?.toList();

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => _filter(parameters.filter).toSet();

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => {for (final key in _filter(parameters.filter)) key: values[key]!};

  @override
  Future<void> setBool(
    String key,
    bool value,
    SharedPreferencesOptions options,
  ) async => values[key] = value;

  @override
  Future<void> setDouble(
    String key,
    double value,
    SharedPreferencesOptions options,
  ) async => values[key] = value;

  @override
  Future<void> setInt(
    String key,
    int value,
    SharedPreferencesOptions options,
  ) async => values[key] = value;

  @override
  Future<void> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async => values[key] = value;

  @override
  Future<void> setStringList(
    String key,
    List<String> value,
    SharedPreferencesOptions options,
  ) async => values[key] = value;

  @override
  Future<void> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    _filter(parameters.filter).toList().forEach(values.remove);
  }

  Iterable<String> _filter(PreferencesFilters filter) {
    final allowList = filter.allowList;
    if (allowList == null) return values.keys.toList();
    return values.keys.where(allowList.contains).toList();
  }
}
