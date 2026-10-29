import 'dart:math' as math;

import 'package:client/core/app_fonts.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/welcome/view/bean_preview.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';

/// How far the badge leans either way at the top of its swing, in radians.
///
/// About one degree. Enough to read as "hanging from something" out of the
/// corner of an eye; more than that and a card you are about to type into is
/// a card that will not hold still.
const double badgeSwingMax = 0.02;

/// The badge's lean at [phase] of the front door's ambient loop.
///
/// Two swings per loop: the loop is twelve seconds, and a six-second sway is
/// the pace of something hanging in still air rather than something blown.
/// Starts upright, so a loop that never runs — "reduce motion" — leaves the
/// badge straight rather than frozen mid-lean.
double badgeSwingAngle(double phase) =>
    math.sin(phase * 2 * math.pi * 2) * badgeSwingMax;

/// The front door's centrepiece: a conference badge on a lanyard.
///
/// Display only. It shows who you will be in the world — the name, the
/// bean — under the event's own header, so the first thing on the door is
/// *you*, already registered. Everything it shows is handed in: the header
/// is config, the name and bean are identity, and the swing is the screen's
/// ambient loop. It owns no ticker, for the same reason nothing else on the
/// front door does.
class BadgeCard extends StatelessWidget {
  /// Creates a badge.
  const BadgeCard({
    required this.eyebrow,
    required this.worldName,
    required this.name,
    required this.color,
    required this.cosmetic,
    super.key,
    this.swing,
    this.nameField,
    this.editor,
    this.editorFooter,
    this.notice,
    this.compact = false,
  });

  /// The small line over the header's title; the event, in config.
  final String eyebrow;

  /// The header's title; the world's name, in config.
  final String worldName;

  /// The name printed on the badge. Empty before one is chosen.
  final String name;

  /// The bean's body colour, as a 32-bit ARGB value.
  final int color;

  /// The cosmetic the bean wears.
  final PlayerCosmetic cosmetic;

  /// The ambient loop that sways the badge, or `null` for a still one.
  final Animation<double>? swing;

  /// What stands where the printed name goes, when the name is editable.
  ///
  /// A slot rather than a flag: the badge draws a badge, and whoever owns
  /// the name's state (the front door, through `SetupViewModel`) owns the
  /// field that edits it. `null` prints [name].
  final Widget? nameField;

  /// The pickers, laid beside the bean when the badge is editable.
  final Widget? editor;

  /// A full-width row under the bean, when the badge is editable.
  final Widget? editorFooter;

  /// Something the player must read before going in — the server's reason
  /// for sending them back, say — printed across the badge under its header.
  final String? notice;

  /// Whether to give ground on a short phone: a shorter strap, a shorter
  /// header and a smaller bean box. About seventy pixels, which on a 667px
  /// phone is the difference between the way in being on screen or not.
  final bool compact;

  /// What the badge says before a name is chosen.
  static const String namePlaceholder = 'Your name';

  /// The style the name is printed, and typed, in.
  static const TextStyle nameStyle = TextStyle(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w800,
    fontSize: 32,
    height: 1.1,
    letterSpacing: -0.5,
    color: LanyardColors.ink,
  );

  /// The key on the transform that sways the card, for tests.
  static const Key swingKey = ValueKey('badge-swing');

  @override
  Widget build(BuildContext context) {
    // The screen already leaves its loop stopped under "reduce motion", but
    // the badge does not rely on being handed a stopped loop: a card that
    // sways for somebody who asked for stillness is a bug wherever it starts.
    final still = MediaQuery.of(context).disableAnimations;
    final loop = still ? null : swing;

    final card = _Card(
      eyebrow: eyebrow,
      worldName: worldName,
      name: name,
      color: color,
      cosmetic: cosmetic,
      nameField: nameField,
      editor: editor,
      editorFooter: editorFooter,
      notice: notice,
      compact: compact,
    );
    final lanyard = _Lanyard(height: compact ? 26 : 60);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          lanyard,
          if (loop == null)
            Transform.rotate(key: swingKey, angle: 0, child: card)
          else
            AnimatedBuilder(
              animation: loop,
              child: card,
              builder: (context, child) => Transform.rotate(
                key: swingKey,
                angle: badgeSwingAngle(loop.value),
                // Pivot at the clip above the card, not the card's own
                // centre: a badge swings from where it hangs.
                alignment: Alignment.topCenter,
                origin: Offset(0, -lanyard.height),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}

/// The strap and the clip the badge hangs from.
class _Lanyard extends StatelessWidget {
  const _Lanyard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: 46,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Container(
              width: 46,
              height: height - 10,
              color: LanyardColors.blue,
            ),
            Positioned(
              bottom: 0,
              child: Container(
                width: 30,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFFB9BEC6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF7C838D), width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card itself: header, name and bean, and the role stripe.
class _Card extends StatelessWidget {
  const _Card({
    required this.eyebrow,
    required this.worldName,
    required this.name,
    required this.color,
    required this.cosmetic,
    required this.nameField,
    required this.editor,
    required this.editorFooter,
    required this.notice,
    required this.compact,
  });

  final String eyebrow;
  final String worldName;
  final String name;
  final int color;
  final PlayerCosmetic cosmetic;
  final Widget? nameField;
  final Widget? editor;
  final Widget? editorFooter;
  final String? notice;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final message = notice;
    final hasName = name.trim().isNotEmpty;
    final bean = Container(
      width: 88,
      height: compact ? 86 : 104,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: LanyardColors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: BeanPreview(color: color, cosmetic: cosmetic, scale: 2.4),
    );
    final printedName =
        nameField ??
        Text(
          hasName ? name : BadgeCard.namePlaceholder,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: BadgeCard.nameStyle.copyWith(
            color: hasName ? LanyardColors.ink : LanyardColors.mutedInk,
          ),
        );
    final pickers = editor;
    final footer = editorFooter;

    // Two layouts. Printed, the name sits beside the bean like a real badge.
    // Editable, the name gets the full width — it is a field somebody is
    // typing into, and half a badge is a cramped place to type — and the
    // pickers take the space beside the bean instead.
    final body = pickers == null
        ? Row(
            children: [
              bean,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HELLO, MY NAME IS', style: LanyardText.eyebrow),
                    const SizedBox(height: 4),
                    printedName,
                  ],
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('HELLO, MY NAME IS', style: LanyardText.eyebrow),
              const SizedBox(height: 2),
              printedName,
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bean,
                  const SizedBox(width: 14),
                  Expanded(child: pickers),
                ],
              ),
              if (footer != null) ...[const SizedBox(height: 10), footer],
            ],
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: LanyardColors.badge,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: LanyardColors.ink.withValues(alpha: 0.16),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(eyebrow: eyebrow, worldName: worldName, compact: compact),
            if (message != null && message.isNotEmpty) _Notice(message),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: body,
            ),
          ],
        ),
      ),
    );
  }
}

/// The server's words, across the top of the badge.
///
/// On the badge rather than in a toast: a name refused at the door is fixed
/// on the badge, so the reason belongs right above the field it is about,
/// and it stays until the player goes in again.
class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LanyardColors.alert.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              size: 18,
              color: LanyardColors.alert,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: LanyardColors.alert,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The badge's blue header, with the slot the clip goes through.
class _Header extends StatelessWidget {
  const _Header({
    required this.eyebrow,
    required this.worldName,
    required this.compact,
  });

  final String eyebrow;
  final String worldName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LanyardColors.blue,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ExcludeSemantics(
              child: Container(
                width: 54,
                height: 9,
                margin: const EdgeInsets.only(top: 9),
                decoration: BoxDecoration(
                  color: LanyardColors.paper,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              compact ? 22 : 26,
              20,
              compact ? 10 : 14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  // Two lines: it is config, and the default line is longer
                  // than one row of a phone-width badge.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LanyardText.eyebrow.copyWith(
                    color: LanyardColors.badge.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  worldName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                    height: 1.05,
                    letterSpacing: -0.5,
                    color: LanyardColors.badge,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
