import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show IconData, Icons;

/// Who built this, and where the source lives.
///
/// One place, because the credit shows up in the HUD, in the QR code and (in
/// a later phase) in the lobby, and three copies of a URL is three chances to
/// ship a dead link on a poster somebody scans.
abstract final class Credits {
  /// The line shown permanently in the corner of the world.
  static const String builtBy = 'Built by Ruhaan · Flutter Boy';

  /// The name on the lobby's maker credit.
  static const String author = 'Ruhaan';

  /// Where to send somebody who taps the name itself.
  static const String authorUrl = 'https://ruhaan-dev.netlify.app/';

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

  /// The repository the QR code points at.
  ///
  /// The single line to edit if the repo moves. It is the whole payload of
  /// the QR: no shortener, no tracker, no redirect — a URL somebody can read
  /// off the screen and type by hand is a URL they can trust enough to scan.
  static const String repositoryUrl =
      'https://github.com/flutterboy20/virtual_conference';

  /// What the QR is labelled as, so scanning it is a choice and not a dare.
  static const String repositoryLabel = 'github.com/flutterboy20';
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
