import 'package:client/app/app.dart';
import 'package:client/core/app_route.dart';
import 'package:client/services/identity_store.dart';
import 'package:flutter/material.dart';

void main() {
  // The store is built here, at the very edge of the app, and injected all
  // the way down. Nothing below this line reaches for `SharedPreferences` on
  // its own, which is what keeps every ViewModel testable without a platform
  // channel behind it.
  //
  // `Uri.base` is the page's own URL on the web, and is read exactly once,
  // here. Everything below takes the answer as a parameter, so no widget has
  // to know that a browser exists.
  runApp(
    VirtualConferenceApp(
      store: SharedPreferencesIdentityStore(),
      route: resolveRoute(Uri.base),
    ),
  );
}
