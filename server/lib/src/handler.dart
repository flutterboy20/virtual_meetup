import 'dart:async';
import 'dart:convert';

import 'package:protocol/protocol.dart';
import 'package:server/src/admin_hub.dart';
import 'package:server/src/map_relays.dart';
import 'package:server/src/ws_handler.dart';
import 'package:shelf/shelf.dart';

/// The path of the health route, without a leading slash.
///
/// `Request.url` is relative to the handler's mount point, so its `path` never
/// carries a leading slash.
const String healthPath = 'health';

/// The path clients open their WebSocket on, without a leading slash.
const String webSocketPath = 'ws';

/// The path the server's own load numbers are served on.
const String metricsPath = 'metrics';

/// The path the event's editable content is served on.
///
/// Public and unauthenticated, deliberately. It is the words on a lobby
/// screen and a count of decorative beans — the same things every attendee is
/// about to be shown anyway — and the welcome screen has to be able to read
/// them **before** it has a WebSocket, a session or a name.
///
/// Read-only. Changing it needs the admin socket and the token.
const String configPath = 'config';

/// The path a moderator opens their privileged WebSocket on.
///
/// A separate path, not a mode of [webSocketPath].
///
/// Deliberately not `/admin`. An unguessable-ish name means nobody idly pokes
/// it during the event, and the server log stays quiet enough that a *real*
/// probe is visible in it. That is the whole benefit, and it is worth having.
///
/// It is **not** a security boundary, and nothing here may ever be written as
/// though it were. The client bundle contains this string, so anybody willing
/// to read the shipped JavaScript can find it in a minute. The token is the
/// boundary; this is an address that happens to be quiet.
const String adminWebSocketPath = 'og-route';

/// Builds the server's root request handler.
///
/// `GET /ws` upgrades to a WebSocket and joins one of [relays] — that is the
/// whole game. Which one is decided by `?map=`; see [buildWebSocketHandler]. `GET /og-route` ([adminWebSocketPath]) upgrades to a privileged
/// socket handled by [admin],
/// which refuses everything until it is given the right token; when no
/// [admin] hub is supplied the route does not exist at all. `GET /health`
/// answers 200 with the shared [helloProtocol] banner, which doubles as a
/// check that the `protocol` package is linked in. `GET /metrics` answers
/// with the current load numbers as JSON, so a load test can read them
/// without scraping the log. Everything else is a 404.
Handler buildHandler({
  MapRelays? relays,
  AdminHub? admin,
  Set<String>? allowedOrigins = const {},
}) {
  final hub = relays ?? MapRelays();
  final webSocket = buildWebSocketHandler(hub, allowedOrigins: allowedOrigins);
  final adminSocket = admin == null
      ? null
      : buildAdminWebSocketHandler(admin, allowedOrigins: allowedOrigins);

  return (Request request) {
    if (request.url.path == webSocketPath) {
      // Not gated on the method: the upgrade handler answers 404 for a plain
      // GET and 400 for a malformed upgrade, which is more useful than a
      // blanket 404 from here.
      return _admitted(hub, () => webSocket(request));
    }
    if (request.url.path == adminWebSocketPath && adminSocket != null) {
      // **Deliberately not gated.** The moment the world is full is the exact
      // moment a moderator most needs to get in, and an admin socket that
      // could be crowded out by the thing it exists to stop would be a
      // defence that disarms itself under load. There is one moderator and
      // the path is unadvertised; the token is what guards it.
      return adminSocket(request);
    }
    if (request.url.path == configPath && request.method == 'GET') {
      return Response.ok(
        hub.config.document,
        headers: {
          'content-type': 'application/json',
          // Never cached. The whole point of this endpoint is that a
          // moderator's edit is live on the next reload, and a proxy holding
          // yesterday's tagline for an hour would undo the entire feature.
          'cache-control': 'no-store',
          ..._corsHeaders(request, allowedOrigins),
        },
      );
    }
    if (request.url.path == healthPath && request.method == 'GET') {
      return Response.ok(helloProtocol());
    }
    if (request.url.path == metricsPath && request.method == 'GET') {
      // Deliberately says nothing about moderation. `/metrics` is public —
      // the welcome screen reads it before anybody has logged into anything
      // — so the number of bans, or whether an admin is connected, does not
      // belong in it.
      return Response.ok(
        jsonEncode(hub.metricsJson()),
        headers: {
          'content-type': 'application/json',
          ..._corsHeaders(request, allowedOrigins),
        },
      );
    }
    return Response.notFound('Not found');
  };
}

/// The `Access-Control-Allow-Origin` header for [request], or nothing.
///
/// Echoes the request's own `Origin` when it is in [allowed], and omits the
/// header entirely otherwise. A `null` [allowed] is the wildcard and echoes
/// whatever asked; the unset case is an *empty set*, which matches nothing
/// and so sends no header — see `resolveAllowedOrigins`.
///
/// Echoing rather than sending `*` because `*` is a different promise: it
/// says *any* page may read this, forever, and it cannot be narrowed later
/// without breaking whoever came to rely on it.
///
/// **Why this matters even though deploying is out of scope.** With the
/// client on one origin and the server on another, the failure without this
/// header is silent and misleading: `HttpAppConfigRepository` answers every
/// failure — a refused connection, a timeout, a CORS block — with
/// `AppConfig.defaults`, by design. So the front door quietly shows the
/// built-in copy, a moderator's live edits never arrive, and the online count
/// reads zero, while everything *looks* like it works.
///
/// **No `OPTIONS` branch, deliberately.** Both routes are plain `GET` with no
/// custom request headers, which makes them CORS-*simple*: the browser never
/// preflights them. A preflight handler here would be dead code answering a
/// request that is never sent.
Map<String, String> _corsHeaders(Request request, Set<String>? allowed) {
  final origin = request.headers['origin'];
  if (origin == null) return const {};
  // `null` is the wildcard — every origin — and it is now only reachable by
  // setting `ALLOWED_ORIGINS=*` on purpose. An empty set is the unset case
  // and matches nothing, so a server nobody configured still sends no header
  // at all, exactly as it did before.
  if (allowed != null && !allowed.contains(origin.toLowerCase())) {
    return const {};
  }
  return {
    'access-control-allow-origin': origin,
    // Two different answers can come back for the same URL depending on this
    // header, so any cache in between has to key on it or it will serve one
    // origin's response to another.
    'vary': 'Origin',
  };
}

/// Runs [upgrade] behind the hard socket cap, refusing with 503 when full.
///
/// The refusal happens **before** `webSocketHandler` runs, which is the whole
/// point: no socket is allocated, no session object exists, and the cost of
/// saying no is one integer comparison. That is the only refusal cheap enough
/// to survive the flood it is there for.
///
/// The slot is claimed before the upgrade is attempted and given back unless
/// the request was actually hijacked. A hijack is how shelf says "this is a
/// socket now" — it throws [HijackException] and never returns a response —
/// so anything that *does* return, including the 404 a plain `GET /ws` gets,
/// took no socket and must not hold a slot. Without this the health-check
/// script that curls `/ws` once a minute would exhaust the cap by lunchtime.
///
/// The matching decrement for a hijacked request lives in
/// `RelaySession.close`, which is the relay's single teardown funnel.
///
/// 503 rather than 429: this is the server saying it is at capacity, not the
/// caller being told they personally asked too often. A `Retry-After` goes
/// with it because a client that reconnects immediately is the thundering
/// herd that keeps the server full.
FutureOr<Response> _admitted(
  MapRelays hub,
  FutureOr<Response> Function() upgrade,
) {
  if (!hub.gate.tryAdmit()) {
    return Response(
      503,
      body: 'The event is at capacity. Please try again shortly.',
      headers: const {
        'content-type': 'text/plain',
        'retry-after': '5',
      },
    );
  }

  // Set once the slot has become somebody else's responsibility. Anything
  // that leaves this function without setting it took no socket, so its slot
  // goes straight back.
  var keepSlot = false;
  try {
    final response = upgrade();
    if (response is Future<Response>) {
      // `webSocketHandler` answers synchronously, so this branch is not the
      // upgrade path — it exists because `Handler` is declared to return a
      // `FutureOr` and a slot held by a future nobody waits on would be a
      // slot leaked. Released when it settles, however it settles.
      keepSlot = true;
      return response.whenComplete(hub.gate.release);
    }
    return response;
  } on HijackException {
    keepSlot = true;
    rethrow;
  } finally {
    if (!keepSlot) hub.gate.release();
  }
}
