import 'package:client/core/event_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatLocalMoment', () {
    test('reads as a date and a 24-hour clock', () {
      // Built from a local moment so the assertion does not depend on where
      // the machine running it happens to be.
      final moment = DateTime(2026, 8, 22, 18, 30);

      expect(formatLocalMoment(moment), equals('22 Aug 2026, 18:30'));
    });

    test('pads the clock, never the date', () {
      expect(
        formatLocalMoment(DateTime(2026, 1, 5, 9, 5)),
        equals('5 Jan 2026, 09:05'),
      );
    });

    test('a UTC instant is shown on the reader own clock', () {
      // The whole reason the wire carries UTC: one function decides what to
      // call it, and it calls it whatever the reader calls it.
      final utc = DateTime(2026, 8, 22, 18, 30).toUtc();

      expect(formatLocalMoment(utc), equals('22 Aug 2026, 18:30'));
    });
  });

  group('formatCountdown', () {
    test('drops the unit below the largest one', () {
      expect(
        formatCountdown(const Duration(days: 3, hours: 2, minutes: 4)),
        equals('3d 02h'),
      );
      expect(
        formatCountdown(const Duration(hours: 2, minutes: 4, seconds: 9)),
        equals('2h 04m'),
      );
      expect(
        formatCountdown(const Duration(minutes: 4, seconds: 9)),
        equals('4m 09s'),
      );
      expect(formatCountdown(const Duration(seconds: 9)), equals('9s'));
    });

    test('anything at or below zero is now', () {
      // So no caller has to special-case the moment it lands on.
      expect(formatCountdown(Duration.zero), equals('now'));
      expect(formatCountdown(const Duration(seconds: -5)), equals('now'));
    });
  });
}
