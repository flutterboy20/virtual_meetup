import 'dart:io';

import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  ServerMetrics metricsAt(DateTime start) {
    var clock = start;
    final metrics = ServerMetrics(
      now: () => clock,
      readResidentBytes: () => 123456789,
    );
    clock = start.add(const Duration(seconds: 5));
    metrics.recordTick(
      duration: const Duration(milliseconds: 4),
      players: 200,
      snapshots: 200,
      playersInSnapshots: 1600,
      busiestCell: 55,
    );
    return metrics;
  }

  group('MetricsCsv', () {
    test('the row has one value per header column', () {
      final metrics = metricsAt(DateTime.utc(2026, 11, 21, 9, 30));

      final row = MetricsCsv.row(metrics, at: DateTime.utc(2026, 11, 21));

      expect(
        row.split(',').length,
        equals(MetricsCsv.header.split(',').length),
      );
    });

    test('carries the numbers a soak run is judged on', () {
      final metrics = metricsAt(DateTime.utc(2026, 11, 21, 9, 30));

      final row = MetricsCsv.row(metrics, at: DateTime.utc(2026, 11, 21));
      final columns = MetricsCsv.header.split(',');
      String valueOf(String column) => row.split(',')[columns.indexOf(column)];

      expect(valueOf('players'), equals('200'));
      expect(valueOf('averagePlayersPerSnapshot'), equals('8.00'));
      expect(valueOf('tickOverruns'), equals('0'));
      // The one that only a long run answers: the memory line.
      expect(valueOf('residentBytes'), equals('123456789'));
    });

    test('timestamps in UTC, so two machines can be compared', () {
      final metrics = metricsAt(DateTime.utc(2026, 11, 21, 9, 30));

      final row = MetricsCsv.row(metrics, at: DateTime.utc(2026, 11, 21, 4));

      expect(row, startsWith('2026-11-21T04:00:00.000Z'));
    });
  });

  group('MetricsRecorder', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('metrics-csv'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('is off, and harmless, when no path is configured', () async {
      final recorder = MetricsRecorder(path: null, log: (_) {});

      await recorder.start();
      recorder.record(metricsAt(DateTime.utc(2026)));
      await recorder.stop();

      expect(recorder.isRecording, isFalse);
    });

    test('writes a header and then one row per window', () async {
      final path = '${dir.path}${Platform.pathSeparator}run.csv';
      final recorder = MetricsRecorder(path: path, log: (_) {});
      await recorder.start();

      recorder
        ..record(metricsAt(DateTime.utc(2026)))
        ..record(metricsAt(DateTime.utc(2026)));
      await recorder.stop();

      final lines = File(path).readAsLinesSync();
      expect(lines.first, equals(MetricsCsv.header));
      expect(lines, hasLength(3));
    });

    test('appends to an existing file without a second header', () async {
      // Two runs against one file is a nuisance; a run that erased the last
      // one is a lost afternoon.
      final path = '${dir.path}${Platform.pathSeparator}run.csv';
      final first = MetricsRecorder(path: path, log: (_) {});
      await first.start();
      first.record(metricsAt(DateTime.utc(2026)));
      await first.stop();

      final second = MetricsRecorder(path: path, log: (_) {});
      await second.start();
      second.record(metricsAt(DateTime.utc(2026)));
      await second.stop();

      final lines = File(path).readAsLinesSync();
      expect(lines.where((line) => line == MetricsCsv.header), hasLength(1));
      expect(lines, hasLength(3));
    });

    test('a file it cannot open is a complaint, not a crash', () async {
      final logged = <String>[];
      // A directory is not a file, so opening it for writing must fail.
      final recorder = MetricsRecorder(path: dir.path, log: logged.add);

      await recorder.start();
      recorder.record(metricsAt(DateTime.utc(2026)));
      await recorder.stop();

      expect(recorder.isRecording, isFalse);
      expect(logged.single, contains('metrics csv unavailable'));
    });
  });
}
