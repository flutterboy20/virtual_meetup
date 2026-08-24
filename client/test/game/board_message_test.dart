import 'dart:ui';

import 'package:client/game/beach_map.dart';
import 'package:client/game/furniture_component.dart';
import 'package:client/game/world_layout.dart';
import 'package:client/game/zone_props.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

/// The projector screen, as a drawable rectangle.
final Rect _screen = ZoneProps.rect(WorldLayout.labScreen);

void main() {
  group('the projector line, as config', () {
    test('a document with no boardMessage reads the built-in one', () {
      expect(
        parseAppConfig('{"tagline": "walk around"}').boardMessage,
        equals(AppConfig.defaultBoardMessage),
      );
      expect(
        AppConfig.defaultBoardMessage,
        equals('setState is best state-management in flutter'),
      );
    });

    test('an empty or non-string one reads the built-in one too', () {
      // Same forgiving `text()` helper the other three fields use: this is a
      // sentence on a wall, and the only sane response to a broken one is the
      // sentence we already had.
      for (final raw in [
        '{"boardMessage": ""}',
        '{"boardMessage": "   "}',
        '{"boardMessage": 42}',
        '{"boardMessage": null}',
        '{"boardMessage": ["a", "b"]}',
        'not json at all',
      ]) {
        expect(
          parseAppConfig(raw).boardMessage,
          equals(AppConfig.defaultBoardMessage),
          reason: '$raw should have fallen back',
        );
      }
    });

    test('a document with one carries it through', () {
      expect(
        parseAppConfig('{"boardMessage": "  hot reload is a lifestyle  "}')
            .boardMessage,
        equals('hot reload is a lifestyle'),
      );
    });
  });

  group('the map it is painted onto', () {
    test('carries the line from config to the furniture', () {
      final map = gameMapFor(
        MapId.conference,
        boardMessage: 'ship it on friday',
      );

      expect((map as ConferenceMap).boardMessage, equals('ship it on friday'));
    });

    test('the beach drops it — there is no Code Lab on a beach', () {
      expect(
        gameMapFor(MapId.beach, boardMessage: 'ship it on friday'),
        isA<BeachMap>(),
      );
    });

    test('ConferenceMap.empty still builds, with the default line', () {
      expect(
        ConferenceMap.empty.boardMessage,
        equals(AppConfig.defaultBoardMessage),
      );
      expect(WorldLayout.of(const []).boardMessage, isNotEmpty);
    });

    test('the furniture records with a line on it', () async {
      final furniture = FurnitureComponent(
        layout: ConferenceMap(const [], 'ship it on friday'),
      );
      await furniture.onLoad();

      final recorder = PictureRecorder();
      furniture.render(Canvas(recorder));
      recorder.endRecording().dispose();

      furniture.onRemove();
    });
  });

  group('the line as it is laid out', () {
    test('a very long one is ellipsized rather than overflowing', () {
      // The failure this prevents is a pasted paragraph painted across the
      // desks behind the screen.
      final width = _screen.width - 32;
      final paragraph = ZoneProps.boardParagraph('word ' * 400, width);

      expect(paragraph.width, lessThanOrEqualTo(width));
      // The whole claim: however much text arrives, it stays inside the
      // 232x52 screen. `didExceedMaxLines` being true is the ellipsis doing
      // its job, not the line escaping.
      expect(paragraph.height, lessThanOrEqualTo(_screen.height));
      expect(paragraph.didExceedMaxLines, isTrue);

      final short = ZoneProps.boardParagraph('one line', width);
      expect(short.didExceedMaxLines, isFalse);
    });

    test('a single word longer than the screen does not throw', () {
      expect(
        () => ZoneProps.boardParagraph('a' * 500, _screen.width - 32),
        returnsNormally,
      );
    });

    test('it is laid out once and cached', () {
      // A `Paragraph` per frame would be a text layout sixty times a second
      // for a sentence that changes when somebody edits a file.
      final width = _screen.width - 32;
      final first = ZoneProps.boardParagraph('same words', width);
      final second = ZoneProps.boardParagraph('same words', width);
      final other = ZoneProps.boardParagraph('other words', width);

      expect(identical(first, second), isTrue);
      expect(identical(first, other), isFalse);
    });

    test('the projector is the wider of the two boards', () {
      // Why the line goes here and not on the whiteboard, which keeps its
      // doodles: 232 units against 138 is the difference between a sentence
      // and a smudge.
      expect(
        WorldLayout.labScreen.width,
        greaterThan(WorldLayout.whiteboard.width),
      );
    });
  });
}
