import 'package:client/core/server_endpoint.dart';
import 'package:http/http.dart' as http;
import 'package:protocol/protocol.dart';

/// Where the front door's copy comes from.
///
/// An interface, because there are now two answers and a test wants a third:
/// [HttpAppConfigRepository] reads the relay's `/config` endpoint, and
/// [StaticAppConfigRepository] serves the document baked into the build. The
/// seam was put in while there was one implementation, which is why adding
/// the second one changed nothing above this line.
// One method is the point: this is the seam a fetched implementation and a
// test both stand in at.
// ignore: one_member_abstracts
abstract class AppConfigRepository {
  /// Returns the app's configuration.
  ///
  /// Implementations must not throw. A front door with no words on it is a
  /// worse outcome than a front door with last week's words, so a failure to
  /// load is answered with [AppConfig.defaults], not an exception.
  Future<AppConfig> load();
}

/// Serves the config from a JSON document held in the app.
///
/// It parses raw JSON rather than returning a hand-built [AppConfig] on
/// purpose: this is the exact string shape the future endpoint will answer
/// with, so swapping the source swaps one line and leaves the parsing — the
/// part that can actually be wrong — already written and already tested.
class StaticAppConfigRepository implements AppConfigRepository {
  /// Creates a repository over [document], defaulting to the bundled copy.
  const StaticAppConfigRepository([this.document = defaultDocument]);

  /// The config document the app ships with.
  ///
  /// Written out as JSON, not as Dart, so that "change the tagline" is a copy
  /// edit somebody can make and see, and so the shape stays honest about what
  /// the endpoint will have to return.
  ///
  /// Phase 12 added `boardMessage` (the Code Lab's projector) and `stageLines`
  /// (the hall's screen). They are spelled out here rather than left to fall
  /// back, because a key that is never written down is a key nobody discovers
  /// — and discovering them is the entire point of putting them in config.
  static const String defaultDocument = '''
{
  "worldName": "Virtual Meetup",
  "eyebrow": "A LITTLE WORLD FOR PEOPLE WHO SHOW UP",
  "tagline": "Pick a bean · walk around · say hi",
  "boardMessage": "setState is best state-management in flutter",
  "stageLines": [
    "NEXT UP: Rebuilding Everything, Twice",
    "A talk about setState, by someone who lost the argument",
    "Live demo. What could go wrong.",
    "Widget tree considered harmful (it is not)",
    "Please silence your hot reloads",
    "Q&A: yes, it also runs on the web",
    "Coffee is one room west"
  ]
}
''';

  /// The raw JSON this repository parses.
  final String document;

  @override
  Future<AppConfig> load() async => parseAppConfig(document);
}

/// Reads the event's config from the relay's `/config` endpoint.
///
/// The default in the shipped app, and the front half of "a moderator's edit
/// shows up without a rebuild": this is what the **welcome screen** reads,
/// before there is a socket, a session or a name. Once somebody is in the
/// world the socket takes over and pushes changes as they happen — see
/// `ConfigMessage`.
///
/// Never throws and never blocks the door. Every failure — a refused
/// connection, a timeout, a CORS block, a body that is not JSON — is answered
/// with [AppConfig.defaults], for the same reason the status service
/// answers `ServerUnreachable`: this is copy on a lobby screen, and last
/// week's tagline beats a blank page.
class HttpAppConfigRepository implements AppConfigRepository {
  /// Creates a repository pointed at [url], defaulting to the relay's.
  HttpAppConfigRepository({
    Uri? url,
    http.Client? client,
    this.timeout = _short,
  }) : url = url ?? resolveConfigUri(),
       _client = client ?? http.Client();

  static const Duration _short = Duration(seconds: 4);

  /// The endpoint this repository reads.
  final Uri url;

  /// How long to wait before falling back to the built-in copy.
  ///
  /// Short on purpose, and for the same reason the status service's is: this
  /// decorates the front door rather than gating it.
  final Duration timeout;

  final http.Client _client;

  @override
  Future<AppConfig> load() async {
    try {
      final response = await _client.get(url).timeout(timeout);
      if (response.statusCode != 200) return AppConfig.defaults;
      return parseAppConfig(response.body);
    } on Object {
      return AppConfig.defaults;
    }
  }

  /// Releases the underlying HTTP client.
  void dispose() => _client.close();
}
