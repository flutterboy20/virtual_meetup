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
}
