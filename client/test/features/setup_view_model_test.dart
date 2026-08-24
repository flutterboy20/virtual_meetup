import 'package:client/core/player_identity.dart';
import 'package:client/features/setup/view_model/setup_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

import '../support/fake_identity_store.dart';

void main() {
  const sessionId = FakeIdentityStore.testSessionId;
  const saved = PlayerIdentity(
    sessionId: sessionId,
    name: 'Ada',
    color: 0xFFF2B33D,
    cosmetic: PlayerCosmetic.headphones,
  );

  ({SetupViewModel model, FakeIdentityStore store}) build({
    PlayerIdentity? identity,
  }) {
    final store = FakeIdentityStore(sessionId: sessionId);
    final model = SetupViewModel(
      store: store,
      sessionId: sessionId,
      identity: identity,
    );
    addTearDown(model.dispose);
    return (model: model, store: store);
  }

  group('starting state', () {
    test('a fresh setup starts empty, with the first colour', () {
      final (:model, store: _) = build();

      expect(model.name.value, isEmpty);
      expect(model.color.value, beanColors.first);
      expect(model.cosmetic.value, PlayerCosmetic.none);
      expect(model.canEnter.value, isFalse);
    });

    test('an edit is seeded with what the player already had', () {
      // Fixing a typo must not cost somebody their colour and their hat.
      final (:model, store: _) = build(identity: saved);

      expect(model.name.value, 'Ada');
      expect(model.color.value, 0xFFF2B33D);
      expect(model.cosmetic.value, PlayerCosmetic.headphones);
      expect(model.canEnter.value, isTrue);
    });
  });

  group('validation', () {
    test('tracks the verdict as the name changes', () {
      final (:model, store: _) = build();

      model.name.value = 'A';
      expect(model.validation.value, NameValidation.tooShort);

      model.name.value = 'Ada';
      expect(model.validation.value, NameValidation.valid);

      model.name.value = 'f.u.c.k';
      expect(model.validation.value, NameValidation.blocked);

      model.name.value = 'Ada 🎉';
      expect(model.validation.value, NameValidation.badChars);
    });

    test('canEnter follows the verdict', () {
      final (:model, store: _) = build();
      final seen = <bool>[];
      model.canEnter.addListener(() => seen.add(model.canEnter.value));

      model.name.value = 'Ada';
      model.name.value = 'A';

      expect(seen, [true, false]);
    });

    test('says nothing about an empty field', () {
      // Telling somebody their name is too short before they have typed a
      // character is nagging, not helping.
      final (:model, store: _) = build();

      expect(model.hint.value, isEmpty);

      model.name.value = '   ';
      expect(model.hint.value, isEmpty);
    });

    test('shows the shared message once there is something to judge', () {
      final (:model, store: _) = build();

      model.name.value = 'A';

      // The *same* string the server would send back, because both come from
      // the one enum in protocol/.
      expect(model.hint.value, NameValidation.tooShort.message);
    });

    test('the hint clears when the name becomes valid', () {
      final (:model, store: _) = build();

      model.name.value = 'A';
      expect(model.hint.value, isNotEmpty);

      model.name.value = 'Ada';
      expect(model.hint.value, isEmpty);
    });
  });

  group('the identity it produces', () {
    test('is null while the name is not valid', () {
      final (:model, store: _) = build();

      expect(model.pendingIdentity, isNull);

      model.name.value = 'x';
      expect(model.pendingIdentity, isNull);
    });

    test('carries the session id it was given', () {
      // The one field the player never sees and never picks, and the reason
      // a reconnect finds the same bean.
      final (:model, store: _) = build();
      model.name.value = 'Ada';

      expect(model.pendingIdentity?.sessionId, sessionId);
    });

    test('stores the normalised name, not the raw text', () {
      final (:model, store: _) = build();

      model.name.value = '  Ada   Lovelace  ';

      expect(model.pendingIdentity?.name, 'Ada Lovelace');
    });

    test('carries the chosen colour and cosmetic', () {
      final (:model, store: _) = build();
      model.name.value = 'Ada';
      model.color.value = beanColors.last;
      model.cosmetic.value = PlayerCosmetic.cap;

      final identity = model.pendingIdentity!;
      expect(identity.color, beanColors.last);
      expect(identity.cosmetic, PlayerCosmetic.cap);
    });
  });

  group('saving', () {
    test('writes the identity and hands it back', () async {
      final (:model, :store) = build();
      model.name.value = 'Ada';

      final saved = await model.save();

      expect(saved, isNotNull);
      expect(store.writes.single, equals(saved));
      expect(await store.readIdentity(), equals(saved));
    });

    test('refuses to save an invalid name', () async {
      final (:model, :store) = build();
      model.name.value = 'f.u.c.k';

      expect(await model.save(), isNull);
      expect(store.writes, isEmpty);
    });

    test('an edit keeps the same session id', () async {
      // Changing your name must not make you a different person to the
      // server, or every edit would cost you your place in the world.
      final (:model, :store) = build(identity: saved);
      model.name.value = 'Ada L';

      final updated = await model.save();

      expect(updated?.sessionId, equals(saved.sessionId));
      expect(updated?.name, 'Ada L');
    });
  });
}
