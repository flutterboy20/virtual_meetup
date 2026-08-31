/// The release number this bundle was built from.
///
/// Supplied as `--dart-define=APP_VERSION=1.0.0+2` by the deploy workflow,
/// which reads it straight out of `client/pubspec.yaml`. That file is the one
/// place a release number is written: the same value goes into the bundle's
/// `version.json`, which is what the workflow reads back off the live site to
/// refuse a deploy that would ship the number already serving.
///
/// A compile-time constant for the same reason `serverUrlOverride` is one —
/// Flutter web has no process environment, so the build is the only moment the
/// bundle can learn anything about itself.
const String appVersionOverride = String.fromEnvironment('APP_VERSION');

/// What a build with no release number calls itself.
///
/// A `flutter run` and a test run have no release, and printing a made-up one
/// would defeat the point of showing it: the line exists so somebody looking at
/// a phone can say which build they are on, and a local build saying `v1.0.0+2`
/// is that line lying.
const String devVersionLabel = 'dev build';

/// The line the drawer prints at the foot of the menu.
///
/// Returns [devVersionLabel] when nothing was defined at build time, and the
/// version prefixed with `v` otherwise. Whitespace-only is treated as absent —
/// a `--dart-define` that resolved to nothing is the same situation as no flag
/// at all, and a lone `v` on screen tells nobody anything.
String appVersionLabel({String override = appVersionOverride}) {
  final trimmed = override.trim();
  return trimmed.isEmpty ? devVersionLabel : 'v$trimmed';
}
