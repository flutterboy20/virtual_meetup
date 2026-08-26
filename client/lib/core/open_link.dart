import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in whatever the platform thinks should handle it.
///
/// Failures are swallowed on purpose. Every link that goes through here is a
/// nice-to-have — the maker's socials at the foot of the lobby, the repo
/// behind the QR in the corner of the world — and a device with no mail
/// client, a browser that blocked the popup or a link typed wrong is not
/// worth a red snackbar over somebody who is about to walk into the world.
///
/// In `core/` rather than in one feature because two screens now open links
/// and neither should have to import the other to do it.
Future<void> openLink(String url) async {
  try {
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } on Object {
    // Nothing to say and nobody to say it to.
  }
}
