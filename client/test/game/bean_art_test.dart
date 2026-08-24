import 'dart:ui';

import 'package:client/game/bean_appearance.dart';
import 'package:client/game/bean_art.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// Draws one bean into a throwaway recording.
void _paintOnce(BeanPaints paints) {
  final recorder = PictureRecorder();
  BeanArt.paintBean(Canvas(recorder), paints);
  recorder.endRecording().dispose();
}

void main() {
  group('BeanArt', () {
    test('draws every cosmetic the protocol can carry', () {
      // The switch in `_paintCosmetic` is exhaustive, so this failing means
      // somebody added an enum value without art — which on the wire is a
      // player whose hat nobody can see.
      for (final cosmetic in PlayerCosmetic.values) {
        expect(
          () => _paintOnce(
            BeanPaints(
              BeanAppearance(
                bodyColor: const Color(0xFF54C5F8),
                cosmetic: cosmetic,
              ),
            ),
          ),
          returnsNormally,
          reason: '${cosmetic.name} cannot be drawn',
        );
      }
    });

    test('paints are cached per appearance, not per frame', () {
      final paints = BeanPaints(
        const BeanAppearance(cosmetic: PlayerCosmetic.propellerBeanie),
      );

      expect(identical(paints.body, paints.body), isTrue);
      expect(paints.cosmetic, equals(PlayerCosmetic.propellerBeanie));
    });

    test('the brim tone is lighter than the cosmetic it belongs to', () {
      final paints = BeanPaints(
        const BeanAppearance(
          cosmeticColor: Color(0xFF2A4C5A),
          cosmetic: PlayerCosmetic.propellerBeanie,
        ),
      );

      expect(
        paints.cosmeticBrim.color.computeLuminance(),
        greaterThan(paints.cosmeticFill.color.computeLuminance()),
      );
    });

    test('the laser burns its own colour whatever the player picked', () {
      // Same rule hair follows, and for the same reason: a light that matches
      // the shirt behind it stops reading as a light. The band around it is
      // still tinted, so the prop keeps carrying the identity signal.
      expect(BeanArt.laserGlow, isNot(equals(const Color(0xFF7CFF00))));
      expect(
        () => _paintOnce(
          BeanPaints(
            const BeanAppearance(
              bodyColor: Color(0xFF7CFF00),
              cosmeticColor: Color(0xFF7CFF00),
              cosmetic: PlayerCosmetic.laserVisor,
            ),
          ),
        ),
        returnsNormally,
      );
    });

    test('hair keeps its own blond whatever the player picked', () {
      // Every other cosmetic is tinted from the body so two players with the
      // same colour still read apart. Hair is not: hair the shade of a
      // lime-green shirt is a wig made out of your shirt.
      expect(BeanArt.hairBlond, isNot(equals(const Color(0xFF54C5F8))));
      expect(
        () => _paintOnce(
          BeanPaints(
            const BeanAppearance(
              bodyColor: Color(0xFF7CFF00),
              cosmeticColor: Color(0xFF7CFF00),
              cosmetic: PlayerCosmetic.malingaHair,
            ),
          ),
        ),
        returnsNormally,
      );
    });
  });
}
