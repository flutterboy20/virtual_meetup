import 'package:protocol/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeName', () {
    test('trims and collapses whitespace', () {
      expect(normalizeName('  Ada   Lovelace  '), 'Ada Lovelace');
    });

    test('collapses tabs and newlines, not just spaces', () {
      expect(normalizeName('Ada\t\nLovelace'), 'Ada Lovelace');
    });

    test('leaves an already-clean name alone', () {
      expect(normalizeName('Ada Lovelace'), 'Ada Lovelace');
    });
  });

  group('length', () {
    test('rejects empty and whitespace-only names', () {
      expect(validateName(''), NameValidation.tooShort);
      expect(validateName('     '), NameValidation.tooShort);
    });

    test('rejects one character below the minimum', () {
      expect(validateName('A'), NameValidation.tooShort);
    });

    test('accepts exactly the minimum', () {
      expect(validateName('Jo'), NameValidation.valid);
    });

    test('accepts exactly the maximum', () {
      final name = 'a' * maxNameLength;
      expect(name.length, maxNameLength);
      expect(validateName(name), NameValidation.valid);
    });

    test('rejects one character above the maximum', () {
      expect(validateName('a' * (maxNameLength + 1)), NameValidation.tooLong);
    });

    test('measures the trimmed name, not the raw one', () {
      // Padding is not a way to smuggle a short name past the minimum...
      expect(validateName('   J   '), NameValidation.tooShort);
      // ...nor a way to fail a name that is really the right length.
      expect(validateName('        Ada        '), NameValidation.valid);
    });
  });

  group('character whitelist', () {
    test('accepts letters, digits, spaces and the safe punctuation', () {
      expect(validateName("O'Neil"), NameValidation.valid);
      expect(validateName('Ada-Lovelace'), NameValidation.valid);
      expect(validateName('dev_null'), NameValidation.valid);
      expect(validateName('Sam Jr.'), NameValidation.valid);
      expect(validateName('Player42'), NameValidation.valid);
    });

    test('rejects zalgo stacking', () {
      expect(validateName('t̶e̴s̶t'), NameValidation.badChars);
    });

    test('rejects zero-width and bidi control characters', () {
      // Built from code points rather than written as literals: a raw U+202E
      // in this file would reorder the source the same way it reorders a
      // nametag, which is the whole reason it is being rejected.
      String withCodePoint(int codePoint) =>
          'Ad${String.fromCharCode(codePoint)}min';

      // Zero-width joiner: invisible padding, so two names can look identical
      // and still compare unequal.
      expect(validateName(withCodePoint(0x200D)), NameValidation.badChars);
      // Zero-width space: the same trick, and `\s` does not match it, so the
      // whitespace collapse never sees it — the whitelist is the only thing
      // standing in its way.
      expect(validateName(withCodePoint(0x200B)), NameValidation.badChars);
      // Right-to-left override: reverses how the rest of the name renders.
      expect(validateName(withCodePoint(0x202E)), NameValidation.badChars);
    });

    test('folds a non-breaking space into an ordinary one', () {
      // Dart's `\s` is Unicode-aware, so U+00A0 is collapsed by
      // `normalizeName` before the whitelist ever runs. That is the outcome
      // we want: a name typed on a keyboard that emits NBSP is a normal name
      // rather than a rejected one, and what gets stored has a real space in
      // it — so it cannot render as one name while comparing as another.
      expect(normalizeName('Ada Lovelace'), 'Ada Lovelace');
      expect(validateName('Ada Lovelace'), NameValidation.valid);
    });

    test('rejects Cyrillic homoglyphs that imitate Latin letters', () {
      // The A is U+0410, not U+0041 — indistinguishable on screen.
      expect(validateName('Аdmin'), NameValidation.badChars);
    });

    test('rejects emoji', () {
      expect(validateName('Ada 🎉'), NameValidation.badChars);
    });

    test('rejects markup and other punctuation', () {
      expect(validateName('<b>Ada</b>'), NameValidation.badChars);
      expect(validateName(r'Ada$$$'), NameValidation.badChars);
    });

    test('runs the length rule before the charset rule', () {
      // A wall of emoji is reported as too long, which is the more useful
      // message of the two.
      expect(validateName('🎉' * 40), NameValidation.tooLong);
    });
  });

  group('blocked words', () {
    test('blocks a plain blocked word', () {
      expect(validateName('fuck'), NameValidation.blocked);
    });

    test('is case-insensitive', () {
      expect(validateName('FuCk'), NameValidation.blocked);
      expect(validateName('SHIT'), NameValidation.blocked);
    });

    test('sees through separator tricks', () {
      expect(validateName('f.u.c.k'), NameValidation.blocked);
      expect(validateName('f_u_c_k'), NameValidation.blocked);
      expect(validateName('f u c k'), NameValidation.blocked);
      expect(validateName('f-u-c-k'), NameValidation.blocked);
      expect(validateName("f'u'c'k"), NameValidation.blocked);
      expect(validateName('s h i t'), NameValidation.blocked);
    });

    test('sees through leetspeak digit substitution', () {
      expect(validateName('fu(k'), NameValidation.badChars);
      expect(validateName('5h1t'), NameValidation.blocked);
      expect(validateName('b1tch'), NameValidation.blocked);
      expect(validateName('n4z1'), NameValidation.blocked);
    });

    test('sees through both tricks combined', () {
      expect(validateName('5.h.1.t'), NameValidation.blocked);
      expect(validateName('B 1 T C H'), NameValidation.blocked);
    });

    test('blocks a fragment embedded in a longer name', () {
      expect(validateName('xxfuckxx'), NameValidation.blocked);
      expect(validateName('Bob the bitch'), NameValidation.blocked);
    });

    test('blocks a standalone word inside a multi-word name', () {
      expect(validateName('Big Dick Sam'), NameValidation.blocked);
      expect(validateName('Ada shit'), NameValidation.blocked);
    });
  });

  group('false positives — these are real names and must pass', () {
    const legitimate = [
      // The Scunthorpe problem, and the reason `cunt` is a whole-word rule.
      'Scunthorpe',
      // A real surname that contains `shit`.
      'Shitole',
      // Contains `sex`.
      'Sussex',
      'Middlesex',
      'Essex',
      // Contains `anal`.
      'Analytics',
      // Contains `rape`, twice over.
      'Grapes',
      'Drapers',
      // Contains `cock`.
      'Cockburn',
      'Hancock',
      // Contains `ass`, near-misses on the fragment list.
      'Cassandra',
      'Bassam',
      // Contains `piss` inside a longer word.
      'Mississippi',
      // Ordinary names, including the ones with punctuation.
      'Ada',
      "O'Brien",
      'Jean-Luc',
      'Dr. Who',
      'Priya S.',
      'dev_null',
      'L33t Coder',
      'Player 1',
      'Ram',
      'Xu',
    ];

    for (final name in legitimate) {
      test('"$name" is accepted', () {
        expect(validateName(name), NameValidation.valid, reason: name);
      });
    }
  });

  group('NameValidation', () {
    test('only valid reports isValid', () {
      for (final value in NameValidation.values) {
        expect(value.isValid, value == NameValidation.valid);
      }
    });

    test('round-trips through its wire name', () {
      for (final value in NameValidation.values) {
        expect(NameValidation.fromWireName(value.wireName), value);
      }
    });

    test('fails closed on a verdict it does not recognise', () {
      expect(
        NameValidation.fromWireName('somethingNew'), //
        NameValidation.blocked,
      );
      expect(NameValidation.fromWireName(null), NameValidation.blocked);
    });

    test('every failure carries a message and valid carries none', () {
      for (final value in NameValidation.values) {
        expect(value.message.isEmpty, value.isValid, reason: value.name);
      }
    });

    test('the blocked message spells out no blocked word', () {
      // Echoing what was blocked turns the rejection into a hint sheet for
      // the next attempt.
      final message = NameValidation.blocked.message.toLowerCase();
      for (final word in ['fuck', 'shit', 'nazi', 'porn']) {
        expect(message, isNot(contains(word)));
      }
    });
  });
}
