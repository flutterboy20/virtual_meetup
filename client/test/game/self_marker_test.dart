import 'package:client/game/bean_animation.dart';
import 'package:client/game/bean_component.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/game/nametag_layer.dart';
import 'package:client/game/remote_players.dart';
import 'package:client/game/self_marker_component.dart';
import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bean standing on dry land, with nothing else attached to it.
BeanComponent _bean() => BeanComponent(
  position: Vector2(400, 400),
  animation: BeanAnimation(maxSpeed: 140),
);

/// A marker over one of those beans.
SelfMarkerComponent _marker() => SelfMarkerComponent(bean: _bean());

void main() {
  // `ConferenceGame.onLoad` registers a frame-timings callback on the
  // scheduler, so a game built here needs a binding even though none of these
  // tests pump a widget.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SelfMarkerComponent', () {
    test('runs its pulse round and starts over', () {
      final marker = _marker();

      expect(marker.pulse, isZero);

      marker.update(SelfMarkerComponent.pulsePeriod / 2);
      expect(marker.pulse, closeTo(0.5, 0.001));

      marker.update(SelfMarkerComponent.pulsePeriod / 2);
      expect(marker.pulse, closeTo(0, 0.001));
    });

    test('a frame long enough to skip whole cycles still lands in range', () {
      // A browser tab coming back from the background delivers one enormous
      // dt. Subtracting a single period would leave the phase above 1 for
      // good, which is a pulse that renders at negative alpha and vanishes.
      final marker = _marker()..update(SelfMarkerComponent.pulsePeriod * 9.4);

      expect(marker.pulse, inInclusiveRange(0, 1));
      expect(marker.pulse, closeTo(0.4, 0.001));
    });

    testWithGame<ConferenceGame>(
      'sits under the local bean and nothing else',
      ConferenceGame.new,
      (game) async {
        await game.ready();

        final markers = game.world.children
            .whereType<SelfMarkerComponent>()
            .toList();

        expect(markers, hasLength(1));
        expect(identical(markers.single.bean, game.bean), isTrue);
        // Below every bean, so it is a ring on the floor rather than a hoop
        // the player is standing inside.
        expect(markers.single.priority, lessThan(game.bean.priority));
      },
    );
  });

  group('NametagLayer, the local tag', () {
    NametagLayer layer({String name = 'Ruhaan'}) => NametagLayer(
      remotePlayers: RemotePlayers(maxSpeed: 140),
      localPosition: Vector2.zero,
      localBean: _bean(),
      localName: name,
    );

    test('is always drawn, at full opacity', () {
      final tag = layer().localTag();

      expect(tag, isNotNull);
      expect(tag!.alpha, equals(1));
      expect(tag.name, equals('Ruhaan'));
    });

    test('is not one of the crowd, so it never spends a slot', () {
      // The cap and the fade exist to stop *other* people's names becoming
      // clutter. Counting your own against them would mean the one name you
      // always want is the first one a busy atrium drops.
      final crowd = layer();

      expect(crowd.visibleTags(), isEmpty);
      expect(crowd.localTag(), isNotNull);
    });

    test('a layer given no name draws none', () {
      expect(layer(name: '').localTag(), isNull);
    });

    testWithGame<ConferenceGame>(
      'the game hands it the name the player joined under',
      () => ConferenceGame(playerName: 'Ruhaan'),
      (game) async {
        await game.ready();

        final tags = game.world.children.whereType<NametagLayer>().single;

        expect(tags.localName, equals('Ruhaan'));
        expect(identical(tags.localBean, game.bean), isTrue);
      },
    );
  });
}
