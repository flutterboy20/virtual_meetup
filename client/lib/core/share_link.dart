import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// The link to hand somebody, worked out from the page this tab is on.
///
/// Stripped back to the front door on purpose: the URL a player is looking at
/// may carry `?map=beach` or the admin fragment, and neither belongs in a
/// message sent to a friend who has not been here yet. Scheme, host, port and
/// path — nothing else.
///
/// Takes the base URL rather than reading `Uri.base` itself so a test can
/// check the stripping without a browser.
String shareLinkFor(Uri base) {
  final path = base.path.isEmpty ? '/' : base.path;

  return Uri(
    scheme: base.scheme,
    host: base.host,
    // `hasPort` is false for the scheme's default port, which is the common
    // case and the one where a `:443` in a shared link would look wrong.
    port: base.hasPort ? base.port : null,
    path: path,
  ).toString();
}

/// Opens the platform's share sheet on the given text.
///
/// A function-shaped seam rather than a call straight into `share_plus`, so a
/// widget test can watch a button do its job without a platform channel
/// underneath it. Production never reassigns it.
@visibleForTesting
Future<void> Function(String text) shareSheet = _systemShareSheet;

/// Offers the app's link through whatever sheet the device has.
///
/// On a phone browser that is the native sheet — WhatsApp, Telegram, Messages,
/// AirDrop — because `share_plus` on web goes through the Web Share API, which
/// is exactly that sheet. On a desktop browser there usually is no such API,
/// and rather than falling back to a `mailto:` (which opens a mail client
/// nobody asked for) the link goes to the clipboard and the screen says so.
///
/// Never throws. Sharing a link is a nice-to-have, and the loudest this is
/// allowed to get is one snackbar.
Future<void> shareApp(
  BuildContext context, {
  required String worldName,
  Uri? base,
}) async {
  // Read at the tap rather than at build: the page's URL is not something the
  // widget tree needs to know, and a share is an action, not state.
  final link = shareLinkFor(base ?? Uri.base);
  final messenger = ScaffoldMessenger.maybeOf(context);

  try {
    await shareSheet('Walk around $worldName with me: $link');
  } on Object {
    await _copyInstead(messenger, link);
  }
}

/// The real sheet.
///
/// Text rather than `uri:`, because the web implementation refuses both at
/// once and a bare URL gives the person on the other end no idea what they
/// have been sent. Both fallbacks are off: a failure here is handled above,
/// where there is a screen to say so on.
Future<void> _systemShareSheet(String text) async {
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      downloadFallbackEnabled: false,
      mailToFallbackEnabled: false,
    ),
  );
}

/// The desktop path: the link on the clipboard, and a line saying it is there.
Future<void> _copyInstead(
  ScaffoldMessengerState? messenger,
  String link,
) async {
  try {
    await Clipboard.setData(ClipboardData(text: link));
  } on Object {
    // A browser that has neither a share sheet nor a clipboard. Nothing left
    // to try, and still not worth an error in front of somebody.
    return;
  }

  messenger?.showSnackBar(
    const SnackBar(
      content: Text('Link copied. Paste it to a friend.'),
      duration: Duration(seconds: 3),
    ),
  );
}
