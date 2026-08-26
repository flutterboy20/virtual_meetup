import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/services/sponsor_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';

void main() {
  group('parsing a colour', () {
    test('accepts the three forms somebody might paste in', () {
      // Hex text rather than an int, because whoever edits this file has the
      // brand guidelines open and `#3DDC84` is what is written in them.
      expect(
        Sponsor.parseColor('#3DDC84', 'x'),
        equals(const Color(0xFF3DDC84)),
      );
      expect(
        Sponsor.parseColor('3DDC84', 'x'),
        equals(const Color(0xFF3DDC84)),
      );
      expect(
        Sponsor.parseColor('0x803DDC84', 'x'),
        equals(const Color(0x803DDC84)),
      );
    });

    test('names the sponsor in the error', () {
      // On event morning the useful part of the failure is which entry it is.
      expect(
        () => Sponsor.parseColor('rebeccapurple', 'acme'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('acme'),
          ),
        ),
      );
    });
  });

  group('a booth', () {
    const sponsor = Sponsor(
      id: 'a',
      name: 'A',
      blurb: '',
      x: 1130,
      y: 478,
      color: Color(0xFF54C5F8),
    );

    test('knows which zone it is standing in', () {
      expect(sponsor.zone, equals(WorldZone.sponsorRow));
    });

    test('has a footprint centred on its position', () {
      expect(sponsor.footprint.centerX, equals(sponsor.x));
      expect(sponsor.footprint.centerY, equals(sponsor.y));
      expect(sponsor.footprint.width, equals(Sponsor.boothWidth));
    });

    test('opens closer than it closes', () {
      // The gap between the two radii is the whole anti-flicker mechanism:
      // with one boundary, a bean standing on it toggles the panel every
      // frame as its idle bob crosses back and forth.
      expect(Sponsor.leaveRadius, greaterThan(Sponsor.approachRadius));
    });
  });

  group('parsing the config file', () {
    test('reads a well-formed file', () {
      final sponsors = parseSponsors('''
        {"sponsors": [
          {"id": "a", "name": "A", "blurb": "hi", "tagline": "t",
           "x": 1130, "y": 478, "color": "#54C5F8"}
        ]}
      ''');

      expect(sponsors, hasLength(1));
      expect(sponsors.single.name, equals('A'));
      expect(sponsors.single.tagline, equals('t'));
    });

    test('an empty list is a world with no booths, not an error', () {
      expect(parseSponsors('{"sponsors": []}'), isEmpty);
    });

    test('rejects two booths sharing an id', () {
      // Proximity picks a booth by id, so the second one could never open.
      expect(
        () => parseSponsors('''
          {"sponsors": [
            {"id": "a", "name": "A", "x": 1, "y": 2, "color": "#000000"},
            {"id": "a", "name": "B", "x": 3, "y": 4, "color": "#000000"}
          ]}
        '''),
        throwsFormatException,
      );
    });

    test('rejects a booth with no id, name, position or colour', () {
      for (final bad in [
        '{"sponsors": [{"name": "A", "x": 1, "y": 2, "color": "#000000"}]}',
        '{"sponsors": [{"id": "a", "x": 1, "y": 2, "color": "#000000"}]}',
        '{"sponsors": [{"id": "a", "name": "A", "y": 2, "color": "#000000"}]}',
        '{"sponsors": [{"id": "a", "name": "A", "x": 1, "y": 2}]}',
      ]) {
        expect(() => parseSponsors(bad), throwsFormatException, reason: bad);
      }
    });

    test('rejects a file that is not the right shape at all', () {
      expect(() => parseSponsors('not json'), throwsFormatException);
      expect(() => parseSponsors('[]'), throwsFormatException);
      expect(() => parseSponsors('{"booths": []}'), throwsFormatException);
    });
  });

  group('the repository', () {
    /// A config holding one booth, written the way a moderator would.
    AppConfig configWith(String id) => parseAppConfig(
      '{"sponsors": [{"id": "$id", "name": "From config", "x": 1100, '
      '"y": 478, "color": "#54C5F8"}]}',
    );

    test('the config one prefers the booths a moderator pushed', () async {
      const bundled = Sponsor(
        id: 'bundled',
        name: 'Bundled',
        blurb: '',
        x: 1,
        y: 2,
        color: Color(0xFF000000),
      );

      final sponsors = await ConfigSponsorRepository(
        configWith('pushed'),
        fallback: const StaticSponsorRepository([bundled]),
      ).load();

      expect(sponsors.map((sponsor) => sponsor.id), equals(['pushed']));
      expect(sponsors.single.name, equals('From config'));
    });

    test(
      'the config one falls back whole when no booths were pushed',
      () async {
        // Every config until somebody writes a sponsor list. An empty east arm
        // on event morning is a much worse answer than a booth a build old.
        const bundled = Sponsor(
          id: 'bundled',
          name: 'Bundled',
          blurb: '',
          x: 1,
          y: 2,
          color: Color(0xFF000000),
        );

        final sponsors = await const ConfigSponsorRepository(
          AppConfig.defaults,
          fallback: StaticSponsorRepository([bundled]),
        ).load();

        expect(sponsors, equals([bundled]));
      },
    );

    test(
      'a booth typed wrong in the document fails as loudly as in the file',
      () {
        final config = parseAppConfig('{"sponsors": [{"name": "no id"}]}');

        expect(
          () => ConfigSponsorRepository(
            config,
            fallback: const StaticSponsorRepository([]),
          ).load(),
          throwsFormatException,
        );
      },
    );

    test('the static one answers with what it was given', () async {
      const sponsor = Sponsor(
        id: 'a',
        name: 'A',
        blurb: '',
        x: 1,
        y: 2,
        color: Color(0xFF000000),
      );

      expect(
        await const StaticSponsorRepository([sponsor]).load(),
        equals([sponsor]),
      );
    });
  });

  group('equality', () {
    const acme = Sponsor(
      id: 'acme',
      name: 'Acme',
      blurb: 'a booth',
      x: 1130,
      y: 478,
      color: Color(0xFF54C5F8),
    );

    test('two booths with every field the same are the same booth', () {
      expect(
        acme,
        equals(
          const Sponsor(
            id: 'acme',
            name: 'Acme',
            blurb: 'a booth',
            x: 1130,
            y: 478,
            color: Color(0xFF54C5F8),
          ),
        ),
      );
    });

    test('a rename is a different booth, not the same one', () {
      // It used to be equality by id alone, and this is the case that made
      // that wrong: everything downstream compares booth lists to decide
      // whether the room has to change, so under id-only equality a rename
      // reached the config and never reached the sign.
      expect(
        acme,
        isNot(
          equals(
            const Sponsor(
              id: 'acme',
              name: 'Acme Industries',
              blurb: 'a booth',
              x: 1130,
              y: 478,
              color: Color(0xFF54C5F8),
            ),
          ),
        ),
      );
    });

    test('so is a move, and so is a repaint', () {
      expect(
        acme,
        isNot(
          equals(
            const Sponsor(
              id: 'acme',
              name: 'Acme',
              blurb: 'a booth',
              x: 1330,
              y: 478,
              color: Color(0xFF54C5F8),
            ),
          ),
        ),
      );
      expect(
        acme,
        isNot(
          equals(
            const Sponsor(
              id: 'acme',
              name: 'Acme',
              blurb: 'a booth',
              x: 1130,
              y: 478,
              color: Color(0xFF7ED9B6),
            ),
          ),
        ),
      );
    });

    test('duplicate ids are still refused, by id', () {
      // The identity reading did not go away; it moved to the one place that
      // wants it, and it compares id strings rather than whole booths.
      expect(
        () => readSponsors(const [
          {'id': 'a', 'name': 'One', 'x': 1, 'y': 1, 'color': '#FFFFFF'},
          {'id': 'a', 'name': 'Two', 'x': 2, 'y': 2, 'color': '#FFFFFF'},
        ]),
        throwsFormatException,
      );
    });
  });
}
