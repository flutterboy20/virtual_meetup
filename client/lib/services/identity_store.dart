import 'package:client/core/player_identity.dart';
import 'package:client/game/joystick_side.dart';
import 'package:protocol/protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything this app keeps on the device between visits.
///
/// An interface, not a class, for one reason: every ViewModel that reads or
/// writes identity can then be unit-tested against a fake with no platform
/// channel, no `WidgetsFlutterBinding`, and no widget test. That is the whole
/// point of the abstraction — it is not speculative future-proofing for a
/// second storage backend nobody has asked for.
///
/// What is stored is deliberately boring: a random id this app generated, a
/// display name, a colour, a hat, and which side the joystick sits on.
/// Nothing personal, nothing a leak of the browser's local storage would
/// matter for.
abstract class IdentityStore {
  /// This device's session id, generated on first use and kept thereafter.
  ///
  /// Generating it lazily here — rather than at setup time — means a returning
  /// player keeps theirs, and a brand-new one gets theirs before the setup
  /// screen has anything to save.
  Future<String> sessionId();

  /// The saved identity, or `null` if this device has never been set up.
  Future<PlayerIdentity?> readIdentity();

  /// Saves [identity] as this device's identity.
  Future<void> writeIdentity(PlayerIdentity identity);

  /// The map this device was last in, or [MapId.conference] if none is saved.
  ///
  /// Persisted next to the identity so a reload puts somebody back where they
  /// were. A refresh mid-session is invisible only if it is invisible *all*
  /// the way — coming back to the conference after ten minutes on the beach
  /// is the same bounce a lost session would be.
  Future<MapId> readMapId();

  /// Saves [map] as the place this device is in.
  Future<void> writeMapId(MapId map);

  /// Whether this device has found the surfboard.
  ///
  /// Per device, on purpose. A refresh keeps it and a logout drops it: the
  /// alternative — re-hunting the board every session — turns a secret into a
  /// chore on the second day.
  Future<bool> readHasBoard();

  /// Saves whether this device has the board.
  Future<void> writeHasBoard({required bool hasBoard});

  /// The saved joystick side, or [JoystickSide.right] if none is saved.
  Future<JoystickSide> readJoystickSide();

  /// Saves [side] as the preferred joystick side.
  Future<void> writeJoystickSide(JoystickSide side);

  /// Forgets everything, session id included.
  ///
  /// The session id goes too, on purpose: this is the "not me any more"
  /// button, and keeping the id would let the server hand the next person
  /// the previous one's seat. Merely *editing* a name does not come through
  /// here — that keeps the id, so the player keeps their place in the world.
  Future<void> clear();

  /// Forgets the name, colour and bean, but keeps the session id.
  ///
  /// The moderation case, and the reason it is not [clear]: a kicked player
  /// has to go back through setup and choose a new name, but the id is what
  /// the server's cooldown, its name block and any ban are keyed on. Dropping
  /// it here would hand the person a way out of all three by being kicked.
  Future<void> clearIdentity();
}

/// The keys this app owns in the device's preference store.
///
/// Prefixed because on the web these become entries in the origin's local
/// storage, shared with anything else served from the same origin.
const String identityKeyPrefix = 'virtualMeetup.';

/// An [IdentityStore] backed by `shared_preferences`.
///
/// Uses [SharedPreferencesAsync] rather than the older cached
/// `SharedPreferences.getInstance()`: everything here is awaited at a screen
/// boundary anyway, so there is nothing to gain from a synchronous mirror of
/// the store, and one less cache is one less thing to be stale.
class SharedPreferencesIdentityStore implements IdentityStore {
  /// Creates a store over [preferences], defaulting to the platform's.
  SharedPreferencesIdentityStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _sessionIdKey = '${identityKeyPrefix}sessionId';
  static const String _nameKey = '${identityKeyPrefix}name';
  static const String _colorKey = '${identityKeyPrefix}color';
  static const String _cosmeticKey = '${identityKeyPrefix}cosmetic';
  static const String _joystickSideKey = '${identityKeyPrefix}joystickSide';
  static const String _mapKey = '${identityKeyPrefix}map';
  static const String _hasBoardKey = '${identityKeyPrefix}hasBoard';

  final SharedPreferencesAsync _preferences;

  @override
  Future<String> sessionId() async {
    final stored = await _preferences.getString(_sessionIdKey);
    // A stored value that is not a well-formed id is treated as absent: it
    // came from a hand-edited local storage entry or an older build, and the
    // server would reject the join it produced.
    if (stored != null && isValidSessionId(stored)) return stored;

    final fresh = newSessionId();
    await _preferences.setString(_sessionIdKey, fresh);
    return fresh;
  }

  @override
  Future<PlayerIdentity?> readIdentity() async {
    final name = await _preferences.getString(_nameKey);
    final color = await _preferences.getInt(_colorKey);
    // No saved name means the player has never finished setup. Everything
    // else has a sensible default; a name does not, and inventing one would
    // silently skip the screen where they choose it.
    if (name == null || color == null) return null;

    return PlayerIdentity(
      sessionId: await sessionId(),
      name: name,
      color: color,
      cosmetic: PlayerCosmetic.fromWireName(
        await _preferences.getString(_cosmeticKey),
      ),
    );
  }

  @override
  Future<void> writeIdentity(PlayerIdentity identity) async {
    await _preferences.setString(_sessionIdKey, identity.sessionId);
    await _preferences.setString(_nameKey, identity.name);
    await _preferences.setInt(_colorKey, identity.color);
    await _preferences.setString(_cosmeticKey, identity.cosmetic.wireName);
  }

  @override
  Future<MapId> readMapId() async =>
      // An unknown stored value reads as the conference rather than as an
      // error, exactly as `?map=` does on the server. A hand-edited local
      // storage entry should open the front door, not a broken world.
      MapId.fromId(await _preferences.getString(_mapKey));

  @override
  Future<void> writeMapId(MapId map) => _preferences.setString(_mapKey, map.id);

  @override
  Future<bool> readHasBoard() async =>
      // A missing key is "no board", which is also what a hand-edited or
      // corrupted entry reads as. Nothing here can hand somebody a board they
      // did not find.
      await _preferences.getBool(_hasBoardKey) ?? false;

  @override
  Future<void> writeHasBoard({required bool hasBoard}) =>
      _preferences.setBool(_hasBoardKey, hasBoard);

  @override
  Future<JoystickSide> readJoystickSide() async {
    final stored = await _preferences.getString(_joystickSideKey);
    return JoystickSide.values
            .where((side) => side.name == stored)
            .firstOrNull ??
        JoystickSide.right;
  }

  @override
  Future<void> writeJoystickSide(JoystickSide side) =>
      _preferences.setString(_joystickSideKey, side.name);

  @override
  Future<void> clearIdentity() async {
    // The board goes with the identity, not with the device: logging out is
    // "I am not this person any more", and the next person to pick this phone
    // up has not found anything.
    for (final key in [_nameKey, _colorKey, _cosmeticKey, _hasBoardKey]) {
      await _preferences.remove(key);
    }
  }

  @override
  Future<void> clear() async {
    for (final key in [
      _sessionIdKey,
      _nameKey,
      _colorKey,
      _cosmeticKey,
      _joystickSideKey,
      _mapKey,
      _hasBoardKey,
    ]) {
      await _preferences.remove(key);
    }
  }
}
