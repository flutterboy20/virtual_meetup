import 'package:protocol/protocol.dart';

/// Where the client looks for the relay server when nothing overrides it.
///
/// Local development only. Production is `wss://…` on a real host, which is
/// why this is a fallback and not a hardcoded constant at the call site.
const String defaultServerUrl = 'ws://localhost:8080/ws';

/// The build-time override, supplied as
/// `--dart-define=SERVER_URL=wss://example.org/ws`.
///
/// A compile-time constant rather than a runtime env read: Flutter web has no
/// process environment, and this way the deployed bundle carries its own
/// endpoint.
const String serverUrlOverride = String.fromEnvironment('SERVER_URL');

/// Resolves the WebSocket endpoint to connect to.
///
/// Falls back to [defaultServerUrl] when [override] is blank or is not a
/// `ws://` / `wss://` URL — a typo in a deploy flag should not leave the app
/// trying to open a socket to nowhere without saying so.
Uri resolveServerUri({String override = serverUrlOverride}) {
  final trimmed = override.trim();
  if (trimmed.isNotEmpty) {
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && (parsed.isScheme('ws') || parsed.isScheme('wss'))) {
      return parsed;
    }
  }
  return Uri.parse(defaultServerUrl);
}

/// The query parameter the server routes a socket by: `/ws?map=beach`.
///
/// The same string the server's `mapQueryParameter` uses. Deliberately not
/// imported from `server/` — the client must not depend on the server package
/// — and deliberately not in `protocol/` either: a URL is not a wire message.
/// **If one of the two is changed, the other must change with it**, or every
/// client silently lands on the conference.
const String mapQueryParameter = 'map';

/// Resolves the WebSocket endpoint for [map].
///
/// The map is chosen **once, at socket-open, from the URL**, because that is
/// the only moment the server can act on it: its relay opens a session the
/// instant the socket upgrades, before any frame has arrived.
///
/// Any query the deploy flag already carried is kept, so a `SERVER_URL` with
/// a token or a room hint in it is not quietly thrown away by the picker.
Uri resolveServerUriFor(MapId map, {String override = serverUrlOverride}) {
  final base = resolveServerUri(override: override);
  return base.replace(
    queryParameters: {
      ...base.queryParameters,
      mapQueryParameter: map.id,
    },
  );
}

/// The path the server serves its load numbers on.
///
/// The same string the server's `metricsPath` uses. It is not imported from
/// `server/` on purpose — the client must not depend on the server package,
/// and a route name is not a wire message, so it does not belong in
/// `protocol/` either.
const String metricsPath = 'metrics';

/// Resolves the HTTP endpoint the welcome screen reads the online count from.
///
/// Derived from the WebSocket URL rather than configured separately: they are
/// the same server, and two knobs that have to agree is one knob too many.
/// `ws` becomes `http` and `wss` becomes `https`, so a deployment behind TLS
/// does not silently make a plaintext request that a browser would block.
Uri resolveMetricsUri({String override = serverUrlOverride}) {
  final socket = resolveServerUri(override: override);
  return socket.replace(
    scheme: socket.isScheme('wss') ? 'https' : 'http',
    path: '/$metricsPath',
  );
}

/// The path the server serves the event's editable content on.
///
/// The same string the server's `configPath` uses, and not imported from
/// `server/` for the same reason [metricsPath] is not. **If one of the two is
/// changed, the other must change with it**, or every front door falls back
/// to the built-in copy and nobody notices until the event.
const String configPath = 'config';

/// Resolves the HTTP endpoint the app reads the event's config from.
///
/// Derived from the WebSocket URL exactly as [resolveMetricsUri] is: it is the
/// same server, and two knobs that have to agree is one knob too many.
Uri resolveConfigUri({String override = serverUrlOverride}) {
  final socket = resolveServerUri(override: override);
  return socket.replace(
    scheme: socket.isScheme('wss') ? 'https' : 'http',
    path: '/$configPath',
  );
}

/// The path the server serves its privileged moderation socket on.
///
/// The same string the server's `adminWebSocketPath` uses, and — like
/// [metricsPath] — deliberately not imported from `server/`: the client must
/// not depend on the server package, and a route name is not a wire message,
/// so it does not belong in `protocol/` either. **If one of the two is
/// changed, the other must change with it** or the moderation screen connects
/// to a 404.
///
/// Not `/admin`, so nobody pokes it idly and a real probe stands out in the
/// log. It is not a secret: this string is compiled into the client bundle
/// and can be read out of the shipped JavaScript. The token is the boundary.
const String adminSocketPath = 'og-route';

/// Resolves the WebSocket endpoint the admin screen connects to.
///
/// Derived from the player endpoint rather than configured separately: it is
/// the same server, and a second knob that has to agree with the first is one
/// knob too many.
Uri resolveAdminSocketUri({String override = serverUrlOverride}) =>
    resolveServerUri(override: override).replace(path: '/$adminSocketPath');
