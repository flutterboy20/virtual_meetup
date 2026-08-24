/// Which of the app's two entirely separate faces to show.
///
/// Not a `Navigator` route. The player flow and the moderation screen never
/// navigate to one another — there is no link, no button and no back stack
/// between them — so what this really names is *which app this tab is*,
/// decided once at startup from the URL and never changed again.
enum AppRoute {
  /// The conference: welcome, setup, world. What everybody gets.
  world,

  /// The moderation dashboard. Reached only by typing the address.
  admin,
}

/// The URL fragment that opens the moderation screen.
///
/// A fragment rather than a path because it works everywhere the app is
/// served — `flutter run -d chrome`, a static host, a subdirectory deploy —
/// without any server-side rewrite rule. A path that needs a rewrite is a
/// path that 404s on the one host you deploy to at 8am on the day.
///
/// Not `admin`: an attendee who tries `#admin` out of curiosity finds nothing,
/// and the handful of people who need this are told the real one. That buys
/// quiet, not safety — the string is in the shipped bundle, and the token is
/// what actually stops anybody.
const String adminRouteFragment = 'og-route';

/// Reads which face of the app [url] asks for.
///
/// Deliberately dumb and deliberately public: this hides the admin screen
/// from *discovery*, not from access. Anybody who reads this source, or the
/// shipped bundle, can open it — and that is fine, because opening it grants
/// nothing at all. Every action behind it is refused by the server until a
/// token it has never seen arrives. Obscurity is the reason no attendee
/// stumbles into it; the token is the reason it is safe that they could.
AppRoute resolveRoute(Uri url) {
  if (url.fragment == adminRouteFragment) return AppRoute.admin;
  // Also honours a real path segment, so a deployment that would rather put
  // this behind its own auth at a real URL can, without a code change.
  if (url.pathSegments.isNotEmpty &&
      url.pathSegments.last == adminRouteFragment) {
    return AppRoute.admin;
  }
  return AppRoute.world;
}
