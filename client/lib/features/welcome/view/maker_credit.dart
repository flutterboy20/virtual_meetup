import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:client/core/credits.dart';
import 'package:client/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The maker's line at the foot of the lobby: a name, and five ways to reach
/// the person behind it.
///
/// Every link comes from [Credits.social], so this widget decides layout and
/// nothing else — adding a sixth link is one entry in `core/credits.dart`.
class MakerCredit extends StatelessWidget {
  /// Creates the credit.
  const MakerCredit({super.key});

  @override
  Widget build(BuildContext context) {
    // The one animation on this screen that is not driven by the welcome
    // screen's loop — `animated_text_kit` owns its own controller — so the
    // "reduce motion" check has to be made again here rather than inherited.
    final still = MediaQuery.of(context).disableAnimations;

    return Column(
      children: [
        InkWell(
          onTap: () => openLink(Credits.authorUrl),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Made by',
                  style: TextStyle(
                    color: AppTheme.mutedInk,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
                _ScrambledName(name: Credits.author, still: still),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Wrap, not Row: five buttons fit one line on every phone worth
        // supporting, and the sixth link somebody adds later wraps instead of
        // overflowing.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final link in Credits.social) _SocialButton(link: link),
          ],
        ),
      ],
    );
  }
}

/// Opens [url] in whatever the platform thinks should handle it.
///
/// Failures are swallowed on purpose. Every one of these is a nice-to-have at
/// the bottom of a lobby — a device with no mail client, a browser that
/// blocked the popup, a link typed wrong — and none of them is worth a red
/// snackbar over somebody about to walk into the world.
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

/// The name, resolving out of noise.
///
/// `ScrambleAnimatedText` from `animated_text_kit`: characters arrive one at a
/// time, each cycling through junk for a moment before it settles on the real
/// letter. Chosen over the liquid fill because that effect works by covering
/// the box with an opaque colour and cutting the glyphs out of it, which needs
/// a flat background to sit on — and this screen does not have one.
///
/// The box is fixed so the column does not jump: the text grows a character at
/// a time, and centring it inside a set width lets it grow outwards from the
/// middle instead of shoving the layout around.
///
/// It owns its own controller and a timer per character, which is why [still]
/// is passed in — the package cannot know the OS asked for less motion.
class _ScrambledName extends StatelessWidget {
  const _ScrambledName({required this.name, required this.still});

  final String name;

  /// Whether to render the plain name and stop, for "reduce motion".
  final bool still;

  /// Big enough to be the last thing you read on the page.
  static const TextStyle _style = TextStyle(
    color: AppTheme.ink,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.5,
  );

  static const double _boxWidth = 240;
  static const double _boxHeight = 46;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _boxWidth,
      height: _boxHeight,
      child: Center(
        child: still
            ? Text(name, style: _style)
            : AnimatedTextKit(
                repeatForever: true,
                animatedTexts: [
                  ScrambleAnimatedText(
                    name,
                    textStyle: _style,
                    textAlign: TextAlign.center,
                    speed: const Duration(milliseconds: 260),
                  ),
                ],
              ),
      ),
    );
  }
}

/// One round button in the row.
///
/// Draws [SocialLink.assetPath] when there is one and [SocialLink.icon] when
/// there is not, which is what makes swapping a placeholder for a real brand
/// mark a one-line edit in `core/credits.dart`.
class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.link});

  final SocialLink link;

  static const double _size = 38;

  @override
  Widget build(BuildContext context) {
    final asset = link.assetPath;

    return Tooltip(
      message: link.label,
      child: Semantics(
        button: true,
        label: link.label,
        child: InkWell(
          onTap: () => openLink(link.url),
          customBorder: const CircleBorder(),
          child: Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surface.withValues(alpha: 0.62),
              border: Border.all(color: AppTheme.ink.withValues(alpha: 0.09)),
            ),
            child: asset == null
                ? Icon(link.icon, size: 17, color: AppTheme.mutedInk)
                : Padding(
                    padding: const EdgeInsets.all(9),
                    child: Image.asset(asset),
                  ),
          ),
        ),
      ),
    );
  }
}
