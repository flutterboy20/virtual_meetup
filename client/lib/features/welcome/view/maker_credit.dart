import 'package:client/core/app_fonts.dart';
import 'package:client/core/credits.dart';
import 'package:client/core/open_link.dart';
import 'package:client/core/theme.dart';
import 'package:flutter/material.dart';

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
    return Column(
      children: [
        InkWell(
          onTap: () => openLink(Credits.authorUrl),
          borderRadius: BorderRadius.circular(10),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Made by',
                  style: TextStyle(
                    color: AppTheme.mutedInk,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
                _MakerName(name: Credits.author),
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

/// The maker's name, plainly.
///
/// Was a scrambling animation from `animated_text_kit`. The package went, and
/// with it the only third-party dependency on this screen, a controller and a
/// timer per character running forever behind a static lobby, and a
/// "reduce motion" branch that had to be checked here because the package
/// could not know the OS had asked. A name at the foot of a page does not
/// need any of that to be read.
///
/// The box stays fixed: the column around it was laid out to a set height,
/// and letting the name decide it again would move everything above it.
class _MakerName extends StatelessWidget {
  const _MakerName({required this.name});

  final String name;

  /// Big enough to be the last thing you read on the page.
  static const TextStyle _style = TextStyle(
    // The display face, on the one line here that is a name rather than a
    // label. It is the last thing you read on the front door.
    fontFamily: AppFonts.display,
    color: AppTheme.ink,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
  );

  static const double _boxHeight = 46;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _boxHeight,
      child: Center(
        child: Text(name, style: _style, textAlign: TextAlign.center),
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
