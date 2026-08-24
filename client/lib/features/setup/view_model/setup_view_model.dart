import 'package:client/core/player_identity.dart';
import 'package:client/services/identity_store.dart';
import 'package:flutter/foundation.dart';
import 'package:protocol/protocol.dart';

/// The body colours a player can pick from.
///
/// A fixed palette, not a colour wheel. Two reasons, both about other people:
/// every colour here is legible against the floor and distinct from its
/// neighbours at a glance, which is the entire job a bean colour has in a
/// crowd, and a free picker guarantees somebody arrives as a black bean on a
/// dark floor and wonders why nobody can see them.
///
/// Plain `int`s in ARGB, not `Color`s, because that is what goes on the wire
/// and what this ViewModel is allowed to know about.
const List<int> beanColors = [
  0xFF54C5F8, // Flutter sky
  0xFF7ED9B6, // mint
  0xFFF2B33D, // amber
  0xFFEF6F6C, // coral
  0xFFB78BE8, // lilac
  0xFF6BA8FF, // cornflower
  0xFFF58FC7, // rose
  0xFF9BD35A, // lime
];

/// State and commands for the setup screen.
///
/// Field state lives in [ValueNotifier]s rather than in one big
/// `notifyListeners()` because the pieces are independent: typing a character
/// should not repaint the colour swatches, and picking a colour should not
/// re-run anything about the name. Per `client-architecture.md`, that is the
/// case a `ValueNotifier` exists for.
///
/// Like every ViewModel here, it imports no `material.dart` — the colour is an
/// `int` and the validation verdict is a `protocol/` enum, so all of this is
/// testable without pumping a widget.
class SetupViewModel {
  /// Creates the view model, optionally seeded from an existing [identity].
  ///
  /// Seeding is what makes "change my name" an edit rather than a fresh
  /// start: somebody fixing a typo should not have to re-pick their colour.
  SetupViewModel({
    required IdentityStore store,
    required String sessionId,
    PlayerIdentity? identity,
  }) : // Named parameters cannot be private, so neither of these can be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _store = store,
       // A named parameter cannot be private.
       // ignore: prefer_initializing_formals
       _sessionId = sessionId,
       name = ValueNotifier(identity?.name ?? ''),
       color = ValueNotifier(identity?.color ?? beanColors.first),
       cosmetic = ValueNotifier(identity?.cosmetic ?? PlayerCosmetic.none);

  final IdentityStore _store;
  final String _sessionId;

  /// What the player has typed so far, raw and untrimmed.
  final ValueNotifier<String> name;

  /// The chosen body colour, as a 32-bit ARGB value.
  final ValueNotifier<int> color;

  /// The chosen cosmetic.
  final ValueNotifier<PlayerCosmetic> cosmetic;

  /// The verdict on what has been typed, updating as it is typed.
  ///
  /// The client runs the same [validateName] the server does, so what the
  /// player is told while typing is exactly what will be enforced at the
  /// door. It is *not* a security boundary — the server re-runs it, because
  /// this copy is running on a machine we do not control.
  ///
  /// Built once and held, not returned fresh from a getter: a getter would
  /// hand every `build` its own listener on [name], and none of them would
  /// ever be removed.
  ValueListenable<NameValidation> get validation => _validation;

  /// Whether the Enter button should do anything.
  ValueListenable<bool> get canEnter => _canEnter;

  /// The message to show under the field, empty while the name is fine.
  ///
  /// Nothing is shown for an *empty* field: telling somebody their name is
  /// too short before they have typed a character is nagging, not helping.
  ValueListenable<String> get hint => _hint;

  late final _MappedListenable<String, NameValidation> _validation =
      _MappedListenable(name, validateName);

  late final _MappedListenable<String, bool> _canEnter = _MappedListenable(
    name,
    (raw) => validateName(raw).isValid,
  );

  late final _MappedListenable<String, String> _hint = _MappedListenable(
    name,
    (raw) => raw.trim().isEmpty ? '' : validateName(raw).message,
  );

  /// The identity these choices describe, or `null` if the name is not valid.
  PlayerIdentity? get pendingIdentity {
    if (!validateName(name.value).isValid) return null;
    return PlayerIdentity(
      sessionId: _sessionId,
      // Stored normalised, so what is saved is exactly what was validated —
      // never the raw text with its stray spaces still on it.
      name: normalizeName(name.value),
      color: color.value,
      cosmetic: cosmetic.value,
    );
  }

  /// Saves the chosen identity and returns it, or `null` if it is not valid.
  Future<PlayerIdentity?> save() async {
    final identity = pendingIdentity;
    if (identity == null) return null;
    await _store.writeIdentity(identity);
    return identity;
  }

  /// Releases the notifiers this view model owns.
  void dispose() {
    // The derived ones first: each holds a listener on [name].
    _validation.dispose();
    _canEnter.dispose();
    _hint.dispose();
    name.dispose();
    color.dispose();
    cosmetic.dispose();
  }
}

/// A [ValueListenable] that maps another one through a pure function.
///
/// Lets the view bind straight to "is the name valid" without the ViewModel
/// having to keep a second, derived field in step with the first — a derived
/// field is a cache, and a cache of something this cheap is only a chance to
/// be wrong.
class _MappedListenable<T, R> extends ValueNotifier<R> {
  _MappedListenable(this._source, this._map) : super(_map(_source.value)) {
    _source.addListener(_update);
  }

  final ValueListenable<T> _source;
  final R Function(T) _map;

  void _update() => value = _map(_source.value);

  @override
  void dispose() {
    _source.removeListener(_update);
    super.dispose();
  }
}
