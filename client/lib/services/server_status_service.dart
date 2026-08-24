import 'dart:async';
import 'dart:convert';

import 'package:client/core/server_endpoint.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;
import 'package:protocol/protocol.dart';

/// What the welcome screen managed to learn about the server.
///
/// A sealed result rather than a nullable int, because "nobody is online" and
/// "we could not ask" are different sentences on screen and the difference
/// matters: the first invites you in, the second warns you.
sealed class ServerStatus {
  const ServerStatus();
}

/// The server answered.
@immutable
class ServerOnline extends ServerStatus {
  /// Creates an online status.
  const ServerOnline(this.players, {this.byMap = const {}});

  /// How many people are in the event right now, on every map together.
  final int players;

  /// How many are on each map.
  ///
  /// The whole reason the front door has a picker rather than a coin toss:
  /// **people follow people**, and a map card without a head-count sends half
  /// the crowd to an empty beach. An empty map here means an older server that
  /// does not report the breakdown; the picker then shows the cards without
  /// counts rather than showing zeroes, because "nobody is there" and "we
  /// could not ask" are opposite facts.
  final Map<MapId, int> byMap;

  /// How many people are on [map], or `null` if that is not known.
  int? on(MapId map) => byMap[map];

  @override
  bool operator ==(Object other) {
    if (other is! ServerOnline) return false;
    if (other.players != players) return false;
    if (other.byMap.length != byMap.length) return false;
    for (final entry in byMap.entries) {
      if (other.byMap[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    players,
    Object.hashAll(byMap.entries.map((e) => Object.hash(e.key, e.value))),
  );

  @override
  String toString() => 'ServerOnline($players, $byMap)';
}

/// The server could not be reached, or did not answer usefully.
///
/// Carries no error object on purpose: nothing upstream is going to branch on
/// a `SocketException`, and putting one in a ViewModel is how a stack trace
/// ends up rendered in a lobby.
@immutable
class ServerUnreachable extends ServerStatus {
  /// Creates an unreachable status.
  const ServerUnreachable();

  @override
  bool operator ==(Object other) => other is ServerUnreachable;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'ServerUnreachable()';
}

/// Reads the server's public status over plain HTTP.
///
/// An interface so the welcome ViewModel can be unit-tested against a fake
/// with no network — see `client-architecture.md`: ViewModels depend on
/// abstractions, views never call either.
// A service seam, not a function in a coat: the fake in the tests records
// how many times it was asked, and the real one owns an HTTP client it has
// to close.
// ignore: one_member_abstracts
abstract class ServerStatusService {
  /// Asks the server how many people are online.
  ///
  /// Never throws: an unreachable server is an expected answer here, not an
  /// exception. The welcome screen has to render something either way.
  Future<ServerStatus> fetch();
}

/// A [ServerStatusService] that reads the relay's `/metrics` endpoint.
class HttpServerStatusService implements ServerStatusService {
  /// Creates a service pointed at [url], defaulting to the configured server.
  HttpServerStatusService({
    Uri? url,
    http.Client? client,
    this.timeout = _short,
  }) : url = url ?? resolveMetricsUri(),
       _client = client ?? http.Client();

  static const Duration _short = Duration(seconds: 4);

  /// The endpoint this service reads.
  final Uri url;

  /// How long to wait before giving up.
  ///
  /// Short on purpose: this number decorates a button, it does not gate one.
  /// A lobby that sits on a spinner for thirty seconds because the server is
  /// unreachable is worse than one that quietly says so in four.
  final Duration timeout;

  final http.Client _client;

  @override
  Future<ServerStatus> fetch() async {
    try {
      final response = await _client.get(url).timeout(timeout);
      if (response.statusCode != 200) return const ServerUnreachable();

      final body = jsonDecode(response.body);
      if (body is! Map<String, Object?>) return const ServerUnreachable();

      final players = body['players'];
      if (players is! int || players < 0) return const ServerUnreachable();

      return ServerOnline(players, byMap: _readByMap(body['byMap']));
    } on Object {
      // Every failure is the same failure as far as the lobby is concerned:
      // a refused connection, a DNS miss, a timeout, a CORS block, or a body
      // that is not the JSON we expected.
      return const ServerUnreachable();
    }
  }

  /// Reads the per-map breakdown, forgiving anything it does not recognise.
  ///
  /// A malformed or absent `byMap` costs the picker its counts and nothing
  /// else. Refusing the whole response over it would take down the head count
  /// on the front door because a future server added a map this build has
  /// never heard of.
  static Map<MapId, int> _readByMap(Object? value) {
    if (value is! Map) return const {};
    final counts = <MapId, int>{};
    for (final entry in value.entries) {
      final map = MapId.tryFromId(entry.key as String?);
      final count = entry.value;
      if (map != null && count is int && count >= 0) counts[map] = count;
    }
    return counts;
  }

  /// Releases the underlying HTTP client.
  void dispose() => _client.close();
}
