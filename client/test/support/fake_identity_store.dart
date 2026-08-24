import 'package:client/core/player_identity.dart';
import 'package:client/game/joystick_side.dart';
import 'package:client/services/identity_store.dart';
import 'package:protocol/protocol.dart';

/// An [IdentityStore] that keeps everything in a field.
///
/// This is the payoff for making the store an interface: every ViewModel and
/// every screen that depends on persistence can be tested without
/// `SharedPreferences`, without a platform channel, and without
/// `TestWidgetsFlutterBinding` mock values.
class FakeIdentityStore implements IdentityStore {
  /// Creates a store, optionally already holding [identity].
  FakeIdentityStore({PlayerIdentity? identity, String? sessionId})
    : _identity = identity,
      _sessionId = sessionId ?? identity?.sessionId;

  /// A well-formed session id for tests that need to name one.
  static const String testSessionId = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

  PlayerIdentity? _identity;
  String? _sessionId;
  JoystickSide _side = JoystickSide.right;
  MapId _map = MapId.conference;
  bool _hasBoard = false;

  /// How many times [clear] has been called.
  int clearCount = 0;

  /// How many times [clearIdentity] has been called.
  int clearIdentityCount = 0;

  /// Everything ever written, in order, so a test can assert on the last one.
  final List<PlayerIdentity> writes = [];

  @override
  Future<String> sessionId() async => _sessionId ??= newSessionId();

  @override
  Future<PlayerIdentity?> readIdentity() async => _identity;

  @override
  Future<void> writeIdentity(PlayerIdentity identity) async {
    _identity = identity;
    _sessionId = identity.sessionId;
    writes.add(identity);
  }

  @override
  Future<MapId> readMapId() async => _map;

  @override
  Future<void> writeMapId(MapId map) async => _map = map;

  @override
  Future<bool> readHasBoard() async => _hasBoard;

  @override
  Future<void> writeHasBoard({required bool hasBoard}) async =>
      _hasBoard = hasBoard;

  @override
  Future<JoystickSide> readJoystickSide() async => _side;

  @override
  Future<void> writeJoystickSide(JoystickSide side) async => _side = side;

  @override
  Future<void> clearIdentity() async {
    clearIdentityCount++;
    _identity = null;
    _hasBoard = false;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    _identity = null;
    _sessionId = null;
    _side = JoystickSide.right;
    _map = MapId.conference;
    _hasBoard = false;
  }
}
