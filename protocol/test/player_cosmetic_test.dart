import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PlayerCosmetic', () {
    test('every value round-trips through its wire name', () {
      for (final cosmetic in PlayerCosmetic.values) {
        expect(
          PlayerCosmetic.fromWireName(cosmetic.wireName),
          equals(cosmetic),
          reason: '${cosmetic.name} does not survive the wire',
        );
      }
    });

    test('the three Phase 12 hats are on the wire by name', () {
      expect(PlayerCosmetic.malingaHair.wireName, equals('malingaHair'));
      expect(PlayerCosmetic.laserVisor.wireName, equals('laserVisor'));
      expect(
        PlayerCosmetic.propellerBeanie.wireName,
        equals('propellerBeanie'),
      );
    });

    test('no two cosmetics share a wire name', () {
      final names = PlayerCosmetic.values.map((c) => c.wireName).toSet();
      expect(names, hasLength(PlayerCosmetic.values.length));
    });

    test('the shades a device saved come back as a laser visor', () {
      // The one legacy wire name in the protocol. Dropping it would silently
      // strip the hat off every returning player who had picked shades, which
      // reads as a bug in the app rather than as a cosmetic being renamed.
      expect(
        PlayerCosmetic.fromWireName('shades'),
        equals(PlayerCosmetic.laserVisor),
      );
    });

    test('a hat this build has never heard of is a bare head', () {
      // The whole of forwards compatibility: an old client meeting a newer
      // one draws a bean it can draw rather than throwing on a string.
      expect(PlayerCosmetic.fromWireName('sombrero'), PlayerCosmetic.none);
      expect(PlayerCosmetic.fromWireName(null), PlayerCosmetic.none);
      expect(PlayerCosmetic.fromWireName(''), PlayerCosmetic.none);
    });

    test('a player wearing a new hat survives being moved', () {
      const before = PlayerState(
        id: 'p1',
        name: 'Lasith',
        color: 0xFF54C5F8,
        cosmetic: PlayerCosmetic.malingaHair,
        x: 10,
        y: 20,
      );

      final after = before.movedTo(30, 40);

      expect(after.cosmetic, equals(PlayerCosmetic.malingaHair));
      expect(after.x, equals(30));
      expect(after.y, equals(40));
    });

    test('a player wearing a new hat survives JSON', () {
      for (final cosmetic in PlayerCosmetic.values) {
        final before = PlayerState(
          id: 'p1',
          name: 'Bean',
          color: 0xFF54C5F8,
          cosmetic: cosmetic,
          x: 1,
          y: 2,
        );

        expect(PlayerState.fromJson(before.toJson()), equals(before));
      }
    });
  });
}
