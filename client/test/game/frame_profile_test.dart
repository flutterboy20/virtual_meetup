import 'package:client/game/frame_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Records [count] frames that each took [millis] in total.
  void frames(FrameProfile profile, int count, double millis) {
    for (var i = 0; i < count; i++) {
      profile.record(
        buildMicros: millis * 1000 ~/ 2,
        rasterMicros: millis * 1000 ~/ 2,
      );
    }
  }

  group('FrameProfile', () {
    test('says nothing rather than dividing by no frames', () {
      final profile = FrameProfile();

      expect(profile.averageMillis, isZero);
      expect(profile.p95Millis, isZero);
      expect(profile.jankRate, isZero);
      expect(profile.impliedFps, isZero);
    });

    test('counts a frame over budget as jank', () {
      final profile = FrameProfile();

      frames(profile, 90, 8);
      frames(profile, 10, 40);

      expect(profile.frames, equals(100));
      expect(profile.jankedFrames, equals(10));
      expect(profile.jankRate, closeTo(0.1, 0.001));
    });

    test('a frame exactly on budget is not jank', () {
      // 16.667ms is the slot, not a miss of it. Counting the boundary as a
      // failure would report a perfect 60fps device as janking constantly.
      final profile = FrameProfile()
        ..record(buildMicros: FrameProfile.defaultBudget, rasterMicros: 0);

      expect(profile.jankedFrames, isZero);
    });

    test('the p95 shows the stutter the average hides', () {
      final profile = FrameProfile();

      frames(profile, 90, 8);
      frames(profile, 10, 60);

      expect(profile.averageMillis, lessThan(14));
      expect(profile.p95Millis, greaterThan(50));
    });

    test('the worst frame survives being evicted from the window', () {
      // The freeze that made you look up is still the answer to "what is the
      // worst this gets", long after it has scrolled out of the window.
      final profile = FrameProfile(capacity: 10);

      frames(profile, 1, 500);
      frames(profile, 50, 8);

      expect(profile.worstMillis, equals(500));
      expect(profile.averageMillis, closeTo(8, 0.1));
    });

    test('keeps only the most recent frames', () {
      final profile = FrameProfile(capacity: 10);

      frames(profile, 100, 8);

      expect(profile.frames, equals(100));
      expect(profile.averageMillis, closeTo(8, 0.1));
    });

    test('walking somewhere else can start a fresh measurement', () {
      final profile = FrameProfile();
      frames(profile, 100, 50);

      profile.reset();
      frames(profile, 10, 8);

      expect(profile.frames, equals(10));
      expect(profile.jankedFrames, isZero);
      expect(profile.worstMillis, closeTo(8, 0.1));
    });

    test('the summary carries the four numbers a phone run is judged on', () {
      final profile = FrameProfile();
      frames(profile, 100, 10);

      expect(profile.summary, contains('fps'));
      expect(profile.summary, contains('p95'));
      expect(profile.summary, contains('jank'));
      expect(profile.summary, contains('worst'));
    });
  });
}
