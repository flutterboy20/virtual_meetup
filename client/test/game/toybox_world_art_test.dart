import 'dart:ui';

import 'package:client/core/theme.dart';
import 'package:client/game/bean_animation.dart';
import 'package:client/game/bean_component.dart';
import 'package:client/game/joystick_art.dart';
import 'package:client/game/nametag_layer.dart';
import 'package:client/game/remote_players.dart';
import 'package:client/game/self_marker_component.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

/// A canvas that writes down what it was asked to fill, and in what colour.
///
/// Colours are kept as 32-bit ARGB: a [Paint] stores its colour in 8 bits a
/// channel, so a float alpha read back is never exactly the one written.
class _RecordingCanvas implements Canvas {
  final List<(String, int)> calls = [];

  @override
  void drawRRect(RRect rrect, Paint paint) =>
      calls.add(('rrect-${paint.style.name}', paint.color.toARGB32()));

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      calls.add(('circle', paint.color.toARGB32()));

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) =>
      calls.add(('text', 0));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the copies of the toybox colours in the render loop', () {
    // The game files repeat these rather than import `core/theme.dart`,
    // which would pull `material.dart` into the render loop. This is what
    // keeps the copies honest.
    test('nametags', () {
      expect(NametagLayer.ink, equals(ToyboxColors.ink));
      expect(NametagLayer.card, equals(ToyboxColors.card));
      expect(NametagLayer.cream, equals(ToyboxColors.cream));
    });

    test('the self marker', () {
      expect(SelfMarkerComponent.ringColor, equals(ToyboxColors.skyEdge));
    });
  });

  group('your own nametag', () {
    test('is the dark pill, outlined, with no colour dot', () {
      final layer = NametagLayer(
        remotePlayers: RemotePlayers(maxSpeed: 140),
        localPosition: Vector2.zero,
        localBean: BeanComponent(
          position: Vector2(400, 400),
          animation: BeanAnimation(maxSpeed: 140),
        ),
        localName: 'Ruhaan',
      );
      final canvas = _RecordingCanvas();

      layer.render(canvas);

      expect(canvas.calls, [
        ('rrect-fill', NametagLayer.ink.toARGB32()),
        ('rrect-stroke', NametagLayer.ink.toARGB32()),
        ('text', 0),
      ]);
    });
  });

  group('the joystick knob', () {
    test('sits on a hard ink shadow, drawn first', () {
      final knob = JoystickKnob(radius: 24, fade: JoystickFade());
      final canvas = _RecordingCanvas();

      knob.render(canvas);

      final circles = canvas.calls.where((c) => c.$1 == 'circle').toList();
      // Colour only: the alpha is the fade's business, and a float alpha
      // rounds a step either way on its way through a Paint.
      int rgb(int argb) => argb & 0x00FFFFFF;
      expect(rgb(circles.first.$2), equals(rgb(ToyboxColors.ink.toARGB32())));
      expect(rgb(circles[1].$2), equals(rgb(ToyboxColors.sky.toARGB32())));
    });
  });
}
