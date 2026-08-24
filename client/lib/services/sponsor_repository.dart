import 'dart:convert';

import 'package:client/core/sponsor.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Where the sponsor list comes from.
///
/// An interface, not just the concrete class, so a test can hand the world a
/// list of booths without touching the asset bundle — and so a later phase can
/// swap the bundled file for a fetched one without the world knowing.
// One method is the point: this is the seam that lets a test — and a later
// fetched implementation — stand in for the bundled file.
// ignore: one_member_abstracts
abstract class SponsorRepository {
  /// Returns every booth to place in the world.
  Future<List<Sponsor>> load();
}

/// Reads the sponsor list out of the app's asset bundle.
///
/// Bundled rather than fetched, for now, on purpose: this is the one screen
/// that must work when the conference wifi does not, and a booth that fails to
/// appear because a request timed out is worse than a booth whose logo is a
/// build old. The interface above is what keeps "fetch it instead" a one-class
/// change.
class AssetSponsorRepository implements SponsorRepository {
  /// Creates a repository reading from [bundle], defaulting to the app's own.
  // A named parameter cannot be private, so this cannot be an initializing
  // formal.
  // ignore: prefer_initializing_formals
  const AssetSponsorRepository({AssetBundle? bundle}) : _bundle = bundle;

  /// The path of the bundled config file.
  static const String assetPath = 'assets/sponsors.json';

  final AssetBundle? _bundle;

  @override
  Future<List<Sponsor>> load() async {
    final raw = await (_bundle ?? rootBundle).loadString(assetPath);
    return parseSponsors(raw);
  }
}

/// A repository that always answers with [sponsors]. For tests and previews.
class StaticSponsorRepository implements SponsorRepository {
  /// Creates a repository over a fixed list.
  const StaticSponsorRepository(this.sponsors);

  /// The booths this repository hands out.
  final List<Sponsor> sponsors;

  @override
  Future<List<Sponsor>> load() async => sponsors;
}

/// Parses the sponsor config file.
///
/// Kept as a free function so the parsing — the part with rules in it — is
/// unit-testable without an asset bundle or a widget test.
List<Sponsor> parseSponsors(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (error) {
    throw FormatException('sponsors.json is not valid JSON: ${error.message}');
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('sponsors.json must be a JSON object');
  }
  final entries = decoded['sponsors'];
  if (entries is! List) {
    throw const FormatException('sponsors.json needs a "sponsors" list');
  }

  final sponsors = <Sponsor>[];
  final seen = <String>{};
  for (final entry in entries) {
    if (entry is! Map<String, Object?>) {
      throw const FormatException('every sponsor entry must be an object');
    }
    final sponsor = Sponsor.fromJson(entry);
    // Duplicate ids would give two booths one identity, and the proximity
    // code picks a booth by id — so the second one could never be opened.
    if (!seen.add(sponsor.id)) {
      throw FormatException('two sponsors share the id "${sponsor.id}"');
    }
    sponsors.add(sponsor);
  }
  return sponsors;
}
