import 'package:client/core/theme.dart';
import 'package:client/features/setup/view_model/setup_view_model.dart';
import 'package:client/features/welcome/view/badge_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocol/protocol.dart';

/// What each cosmetic is called on its chip.
///
/// Every value of [PlayerCosmetic] must be here: a hat added to the protocol
/// without a label would ship a chip reading its wire name. A test walks the
/// enum to catch exactly that.
const Map<PlayerCosmetic, String> cosmeticLabels = {
  PlayerCosmetic.none: 'None',
  PlayerCosmetic.cap: 'Cap',
  PlayerCosmetic.headphones: 'Headphones',
  PlayerCosmetic.malingaHair: 'Spiky Hair',
  PlayerCosmetic.laserVisor: 'Laser Visor',
  PlayerCosmetic.propellerBeanie: 'Propeller Beanie',
};

/// The badge, editable: type your name on it, pick your colour and hat.
///
/// A view over [SetupViewModel] and nothing else. Every rule about what a
/// name may be — the trimming, the length cap, the filter — lives there and
/// in `protocol/`; this file only decides where the pieces sit on the card.
///
/// Each piece listens to its own notifier, so typing a letter repaints the
/// name and its hint and leaves the swatches alone, and picking a colour
/// never rebuilds the text field out from under the keyboard.
class BadgeEditor extends StatefulWidget {
  /// Creates an editable badge over [model].
  const BadgeEditor({
    required this.model,
    required this.eyebrow,
    required this.worldName,
    super.key,
    this.swing,
    this.onSubmitted,
    this.notice,
    this.compact = false,
  });

  /// The choices being edited.
  final SetupViewModel model;

  /// The small line over the header's title.
  final String eyebrow;

  /// The header's title.
  final String worldName;

  /// The ambient loop that sways the badge.
  final Animation<double>? swing;

  /// Called when the keyboard's done key is pressed on a valid name.
  final VoidCallback? onSubmitted;

  /// The server's reason for sending the player back, if it did.
  final String? notice;

  /// Whether to give ground on a short phone. See [BadgeCard.compact].
  final bool compact;

  /// The key on the name field, for tests.
  static const Key nameFieldKey = ValueKey('badge-name');

  @override
  State<BadgeEditor> createState() => _BadgeEditorState();
}

class _BadgeEditorState extends State<BadgeEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.model.name.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;

    return ValueListenableBuilder<int>(
      valueListenable: model.color,
      builder: (context, color, _) => ValueListenableBuilder<PlayerCosmetic>(
        valueListenable: model.cosmetic,
        builder: (context, cosmetic, _) => BadgeCard(
          eyebrow: widget.eyebrow,
          worldName: widget.worldName,
          // The field shows the name; the card never prints it as well.
          name: '',
          color: color,
          cosmetic: cosmetic,
          swing: widget.swing,
          notice: widget.notice,
          compact: widget.compact,
          nameField: _NameField(
            model: model,
            controller: _controller,
            onSubmitted: widget.onSubmitted,
          ),
          editor: _Swatches(model: model),
          editorFooter: _HatChips(model: model),
        ),
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({
    required this.model,
    required this.controller,
    required this.onSubmitted,
  });

  final SetupViewModel model;
  final TextEditingController controller;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: BadgeEditor.nameFieldKey,
          controller: controller,
          // No autofocus. This field sits on the front door now, not on a
          // screen of its own, and a keyboard that leaps up on arrival hides
          // the hall signs and the way in on every phone.
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => model.name.value = value,
          onSubmitted: (_) {
            if (!model.canEnter.value) return;
            FocusScope.of(context).unfocus();
            onSubmitted?.call();
          },
          inputFormatters: [
            // A hard stop at the cap, so the field cannot be typed past the
            // point where the message would say "too long" forever. The
            // validator still runs — this is a courtesy, not the rule.
            LengthLimitingTextInputFormatter(maxNameLength),
          ],
          style: BadgeCard.nameStyle,
          cursorColor: LanyardColors.blue,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.only(top: 2, bottom: 6),
            hintText: BadgeCard.namePlaceholder,
            hintStyle: BadgeCard.nameStyle.copyWith(
              color: LanyardColors.mutedInk.withValues(alpha: 0.55),
            ),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: LanyardColors.ink, width: 3),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: LanyardColors.blue, width: 3),
            ),
          ),
        ),
        // A fixed-height slot, so the card does not grow and shrink as the
        // message comes and goes under somebody's thumb.
        SizedBox(
          height: 22,
          child: ValueListenableBuilder<String>(
            valueListenable: model.hint,
            builder: (context, hint, _) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: LanyardColors.alert,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The eight colours, two rows of four beside the bean.
class _Swatches extends StatelessWidget {
  const _Swatches({required this.model});

  final SetupViewModel model;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: model.color,
      builder: (context, selected, _) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (i, color) in beanColors.indexed)
            _Swatch(
              color: color,
              label: 'Colour ${i + 1}',
              isSelected: color == selected,
              onTap: () => model.color.value = color,
            ),
        ],
      ),
    );
  }
}

/// The hats, every one on screen at once: two rows of three.
///
/// A fixed grid rather than a row that scrolls sideways — a hat you have to
/// scroll to find is a hat nobody picks — and rather than a free wrap, whose
/// row count depends on how wide the words come out. Three equal columns are
/// two rows on every phone, in every font, so the badge's height is known and
/// the way in stays on screen. The room came from the attendee stripe the
/// badge no longer has.
class _HatChips extends StatelessWidget {
  const _HatChips({required this.model});

  final SetupViewModel model;

  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerCosmetic>(
      valueListenable: model.cosmetic,
      builder: (context, selected, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 2 * _gap) / 3;
          return Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [
              for (final cosmetic in PlayerCosmetic.values)
                SizedBox(
                  width: width,
                  child: _HatChip(
                    label: cosmeticLabels[cosmetic] ?? cosmetic.wireName,
                    isSelected: cosmetic == selected,
                    onSelected: () => model.cosmetic.value = cosmetic,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final int color;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // A 44px target around a 32px dot: four of these fit beside the bean
        // on a 360px phone, and a thumb still finds each one.
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(color),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? LanyardColors.ink : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HatChip extends StatelessWidget {
  const _HatChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      // Centred in its cell, and shrunk rather than cut when a long name
      // ("Propeller Beanie") is wider than a third of the badge.
      label: Align(
        heightFactor: 1,
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      // Sized to what is drawn, not padded out to 48: invisible padding on
      // two rows is what pushed the way in off a phone's screen. Each chip
      // is still a third of the badge wide and a thumb's height tall.
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      backgroundColor: LanyardColors.badge,
      selectedColor: LanyardColors.ink,
      side: BorderSide(
        color: isSelected ? LanyardColors.ink : const Color(0xFFC9CDD3),
        width: 1.5,
      ),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: isSelected ? LanyardColors.badge : LanyardColors.ink,
      ),
    );
  }
}
