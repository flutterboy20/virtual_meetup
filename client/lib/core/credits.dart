import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:protocol/protocol.dart' show AppConfig;

/// Who built this, and where the source lives.
///
/// One place, because the credit shows up in the HUD, in the QR code and (in
/// a later phase) in the lobby, and three copies of a URL is three chances to
/// ship a dead link on a poster somebody scans.
abstract final class Credits {
  /// The line shown permanently in the corner of the world.
  static const String builtBy = 'Built by Ruhaan';

  /// The name on the lobby's maker credit.
  static const String author = 'Ruhaan';

  /// Where to send somebody who taps the name itself.
  static const String authorUrl = 'https://ruhaan-dev.netlify.app/';

  /// Where somebody a moderator removed is told to write.
  ///
  /// **A placeholder.** Deliberately not the maker addresses below: an appeal
  /// against a moderator decision is event business, and it wants an inbox
  /// the event team can all read rather than one person's personal mail. The
  /// real address goes here before the doors open — tracked in
  /// `.planning/open-questions.md`.
  static const String supportEmail = 'support@example.com';

  /// Every way to reach the author, in the order they are shown.
  ///
  /// A list rather than five fields so the row on screen is a `map` over
  /// this and adding a sixth link is one entry here — not an entry here, a
  /// widget there, and a gap somebody forgets to close.
  static const List<SocialLink> social = [
    SocialLink(
      label: 'LinkedIn',
      url: 'https://linkedin.com/in/ruhaan-shaikh',
      icon: Icons.work_outline,
    ),
    SocialLink(
      label: 'GitHub',
      url: 'https://github.com/flutterboy20',
      icon: Icons.code,
    ),
    SocialLink(
      label: 'Portfolio',
      url: authorUrl,
      icon: Icons.language,
    ),
    SocialLink(
      label: 'Instagram',
      url: 'https://www.instagram.com/flutter.boy_',
      icon: Icons.camera_alt_outlined,
    ),
    SocialLink(
      label: 'Email',
      // Fully qualified, like every other entry. The row does not special-case
      // one of these — it hands the string to the platform and that is all.
      url: 'mailto:mrruhaanshaikh@gmail.com',
      icon: Icons.alternate_email,
    ),
  ];

  /// The repository the QR code points at when the config does not say.
  ///
  /// The fallback, not the truth: the live value is `AppConfig.githubLink`,
  /// which a moderator edits, and this is the same string the protocol
  /// defaults to — read from there rather than typed again, because two
  /// copies of a URL is two chances to ship a dead link on a poster somebody
  /// scans.
  static const String repositoryUrl = AppConfig.defaultGithubLink;

  /// How [url] is printed under the QR, so scanning it is a choice and not a
  /// dare.
  ///
  /// The scheme and any trailing slash come off and nothing else does. A
  /// label that is a *shortening* of the link rather than a *rewrite* of it
  /// is one a person can check against the code above it; anything cleverer
  /// (a domain, a name, an ellipsis) is asking them to trust the label
  /// instead of the link.
  static String linkLabel(String url) {
    final trimmed = url.trim();
    for (final scheme in const ['https://', 'http://']) {
      if (trimmed.toLowerCase().startsWith(scheme)) {
        final rest = trimmed.substring(scheme.length);
        return rest.endsWith('/') ? rest.substring(0, rest.length - 1) : rest;
      }
    }
    return trimmed;
  }
}

/// One way to reach the person who made this.
@immutable
class SocialLink {
  /// Creates a link.
  const SocialLink({
    required this.label,
    required this.url,
    required this.icon,
    this.assetPath,
  });

  /// What it is called: the tooltip, and what a screen reader announces.
  final String label;

  /// Where it goes. Fully qualified, `mailto:` included.
  final String url;

  /// The stand-in glyph, drawn whenever [assetPath] is null.
  ///
  /// A Material icon is a placeholder, not a decision — none of them is the
  /// LinkedIn or Instagram mark, and neither is shipped with Flutter.
  final IconData icon;

  /// A brand logo to draw instead of [icon], once there is one.
  ///
  /// To swap a placeholder for the real mark: drop the image in
  /// `client/assets/social/`, add that folder under `flutter: assets:` in
  /// `client/pubspec.yaml`, and set this to the path (for example
  /// `assets/social/linkedin.png`). Nothing else changes — the row reads this
  /// field and draws whichever of the two it finds.
  final String? assetPath;

  @override
  bool operator ==(Object other) => other is SocialLink && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'SocialLink($label → $url)';
}
