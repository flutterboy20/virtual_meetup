import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:loadtest/loadtest.dart';
import 'package:protocol/protocol.dart';

/// Opens N websocket clients that wander the world, and reports what it cost.
///
/// Run the server, run this, and read the server's own metrics line beside
/// this one. The pair is the evidence that interest management works — or
/// the evidence that it does not, which is the more useful outcome.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('bots', abbr: 'n', defaultsTo: '50', help: 'How many bots.')
    ..addOption(
      'url',
      abbr: 'u',
      defaultsTo: 'ws://localhost:8080/ws',
      help: 'The relay to connect to.',
    )
    ..addOption(
      'scenario',
      defaultsTo: LoadScenario.spread.name,
      allowed: LoadScenario.values.map((s) => s.name),
      help: 'The shape of the crowd to simulate.',
      allowedHelp: {
        for (final scenario in LoadScenario.values)
          scenario.name: scenario.description,
      },
    )
    ..addMultiOption(
      'map',
      abbr: 'm',
      allowed: MapId.values.map((map) => map.id),
      help:
          'Which world to load. Repeat it to split the swarm evenly across '
          'more than one, which is the only way to measure both relays at '
          'once. Defaults to the conference.',
      allowedHelp: {
        for (final map in MapId.values)
          map.id:
              '${map.label}: '
              '${MapSpec.of(map).width.toInt()}x'
              '${MapSpec.of(map).height.toInt()} units, '
              '${MapSpec.of(map).zones.length} zones',
      },
    )
    ..addOption(
      'seconds',
      abbr: 's',
      defaultsTo: '30',
      help: 'How long to run for, after everybody is connected.',
    )
    ..addOption(
      'report',
      abbr: 'r',
      defaultsTo: '5',
      help: 'Seconds between report lines.',
    )
    ..addOption(
      'ramp',
      defaultsTo: '10',
      help:
          'Seconds to spread the connections over, so the swarm arrives like '
          'a conference filling up instead of like a connect storm.',
    )
    ..addOption(
      'seed',
      defaultsTo: '1',
      help: 'Random seed, so a run can be repeated.',
    )
    ..addOption(
      'cluster',
      abbr: 'c',
      help:
          'Override the scenario: keep every bot within this many world units '
          'of the atrium spawn point.',
    )
    ..addOption(
      'churn',
      help:
          'Override the scenario: the fraction of the swarm that leaves and '
          'rejoins every minute, e.g. 0.2 for a fifth.',
    )
    ..addOption(
      'surfers',
      help:
          'Percentage of bots that unlock a surfboard after joining and '
          'toggle it every 30-90s, jittered. The board is an event, not a '
          'per-tick field, so bytes/sec per client must not move.',
    )
    ..addOption(
      'surf-toggle',
      help:
          'Force every surfer to flip its board this often, in seconds, '
          'instead of the jittered 30-90s. Only useful for proving the '
          "server's board limiter holds under a flood.",
    )
    ..addOption(
      'csv',
      help:
          'Append one row per report line to this file, for charting a long '
          'run afterwards.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(parser.usage);
    exitCode = 64;
    return;
  }

  if (options.flag('help')) {
    stdout
      ..writeln('Bot load-tester for the walk-around world relay.\n')
      ..writeln(parser.usage);
    return;
  }

  final bots = int.tryParse(options.option('bots') ?? '');
  final seconds = int.tryParse(options.option('seconds') ?? '');
  final report = int.tryParse(options.option('report') ?? '');
  final ramp = int.tryParse(options.option('ramp') ?? '');
  final seed = int.tryParse(options.option('seed') ?? '');
  final scenario = LoadScenario.parse(options.option('scenario') ?? '');
  final clusterOption = options.option('cluster');
  final cluster = clusterOption == null ? null : double.tryParse(clusterOption);
  final churnOption = options.option('churn');
  final churn = churnOption == null ? null : double.tryParse(churnOption);
  final surfersOption = options.option('surfers');
  final surfers = surfersOption == null ? null : double.tryParse(surfersOption);
  final toggleOption = options.option('surf-toggle');
  final surfToggle = toggleOption == null
      ? null
      : double.tryParse(toggleOption);
  final csvPath = options.option('csv');
  final url = Uri.tryParse(options.option('url') ?? '');
  // `allowed` above has already refused anything that is not a map id, so
  // this cannot produce a null. Defaulted rather than required: a run that
  // says nothing about maps means the conference, exactly as it did before
  // there was a second one.
  final mapOption = options.multiOption('map');
  final maps = mapOption.isEmpty
      ? const [MapId.conference]
      : mapOption.map(MapId.fromId).toSet().toList(growable: false);

  if (bots == null || bots < 1) {
    stderr.writeln('--bots must be a positive integer');
    exitCode = 64;
    return;
  }
  if (seconds == null || seconds < 1 || report == null || report < 1) {
    stderr.writeln('--seconds and --report must be positive integers');
    exitCode = 64;
    return;
  }
  if (ramp == null || ramp < 0) {
    stderr.writeln('--ramp must be a whole number of seconds >= 0');
    exitCode = 64;
    return;
  }
  if (seed == null) {
    stderr.writeln('--seed must be an integer');
    exitCode = 64;
    return;
  }
  if (scenario == null) {
    stderr.writeln('--scenario must be one of: ${LoadScenario.names}');
    exitCode = 64;
    return;
  }
  if (url == null || !(url.isScheme('ws') || url.isScheme('wss'))) {
    stderr.writeln('--url must be a ws:// or wss:// address');
    exitCode = 64;
    return;
  }
  if (clusterOption != null && (cluster == null || cluster <= 0)) {
    stderr.writeln('--cluster must be a positive number of world units');
    exitCode = 64;
    return;
  }
  if (churnOption != null && (churn == null || churn < 0)) {
    stderr.writeln('--churn must be a fraction of the swarm per minute >= 0');
    exitCode = 64;
    return;
  }

  if (surfersOption != null &&
      (surfers == null || surfers < 0 || surfers > 100)) {
    stderr.writeln('--surfers must be a percentage between 0 and 100');
    exitCode = 64;
    return;
  }

  if (toggleOption != null && (surfToggle == null || surfToggle <= 0)) {
    stderr.writeln('--surf-toggle must be a positive number of seconds');
    exitCode = 64;
    return;
  }

  final swarm = Swarm(
    url: url,
    count: bots,
    scenario: scenario,
    random: Random(seed),
    maps: maps,
    clusterRadius: cluster,
    churnFraction: churn,
    surferShare: (surfers ?? 0) / 100,
    surfToggleSeconds: surfToggle,
  );
  stdout.writeln(
    'connecting $bots bots to $url '
    '[${maps.map((map) => map.id).join(' + ')}] — ${scenario.name}: '
    '${scenario.description}'
    '${swarm.clusterRadius == null ? '' : ' (r=${swarm.clusterRadius})'}'
    '${swarm.churnFraction <= 0 ? '' : ' (${swarm.churnFraction} of the '
              'swarm per minute)'}'
    '${swarm.surferShare <= 0 ? '' : ' (${(swarm.surferShare * 100).round()}% '
              'surfing)'} '
    'over ${ramp}s …',
  );

  await swarm.connect(
    ramp: rampGap(
      count: bots,
      over: Duration(seconds: ramp),
    ),
    onProgress: (connected) {
      if (connected % 25 == 0 || connected == bots) {
        stdout.writeln('  $connected/$bots');
      }
    },
  );
  stdout.writeln(
    'connected=${swarm.stats.connected} failed=${swarm.stats.failed}; '
    'walking for ${seconds}s',
  );

  // Opened before the run so a run that dies halfway still leaves a chart.
  // The header is written only for a file that is new or empty: appending
  // beats truncating, because a rerun that erased the previous run's numbers
  // would be a lost afternoon.
  final IOSink? csv;
  if (csvPath == null) {
    csv = null;
  } else {
    final file = File(csvPath);
    final fresh = !file.existsSync() || file.lengthSync() == 0;
    csv = file.openWrite(mode: FileMode.append);
    if (fresh) {
      csv.writeln(
        'elapsedSeconds,connected,failed,movesSent,received,receivedBytes,'
        'snapshots,averagePlayersPerSnapshot,left,reseated,arrived',
      );
    }
  }

  final started = DateTime.now();
  swarm.start();

  final reporter = Timer.periodic(Duration(seconds: report), (_) {
    final elapsed = DateTime.now().difference(started);
    stdout.writeln(swarm.stats.summary(elapsed));
    csv?.writeln(_csvRow(swarm.stats, elapsed));
  });

  await Future<void>.delayed(Duration(seconds: seconds));
  reporter.cancel();

  final elapsed = DateTime.now().difference(started);
  // Summarised before the sockets are closed: `connected` is a gauge now, so
  // reading it after the teardown would report every run as zero bots.
  final summary = swarm.stats.summary(elapsed);
  final row = _csvRow(swarm.stats, elapsed);
  await swarm.stop();
  csv?.writeln(row);
  await csv?.flush();
  await csv?.close();

  stdout
    ..writeln('--- run finished (${elapsed.inSeconds}s) ---')
    ..writeln(summary)
    ..writeln(
      'Read the server side of this from its log line, or GET /metrics.',
    );
}

String _csvRow(SwarmStats stats, Duration elapsed) => [
  (elapsed.inMilliseconds / 1000).toStringAsFixed(1),
  stats.connected,
  stats.failed,
  stats.movesSent,
  stats.received,
  stats.receivedBytes,
  stats.snapshots,
  stats.averagePlayersPerSnapshot.toStringAsFixed(2),
  stats.left,
  stats.reseated,
  stats.arrived,
].join(',');
