import 'package:client/core/player_identity.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/setup/view/bean_preview.dart';
import 'package:client/features/setup/view_model/setup_view_model.dart';
import 'package:client/services/identity_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocol/protocol.dart';

/// Pick a name, a colour and a hat, and see what you will look like.
///
/// The view is deliberately thin: every rule about what a name may be lives in
/// [SetupViewModel] (and, underneath it, in `protocol/`), so this file decides
/// nothing except where things sit on screen.
class SetupScreen extends StatefulWidget {
  /// Creates the setup screen.
  const SetupScreen({
    required this.store,
    required this.sessionId,
    super.key,
    this.identity,
    this.onDone,
  });

  /// Where the chosen identity is saved.
  final IdentityStore store;

  /// This device's session id, carried into the identity that is saved.
  final String sessionId;

  /// An existing identity to edit, or `null` for a first-time setup.
  final PlayerIdentity? identity;

  /// Called with the saved identity once the player enters the world.
  final ValueChanged<PlayerIdentity>? onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final SetupViewModel _model = SetupViewModel(
    store: widget.store,
    sessionId: widget.sessionId,
    identity: widget.identity,
  );

  late final TextEditingController _nameController = TextEditingController(
    text: _model.name.value,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    final identity = await _model.save();
    if (identity == null || !mounted) return;
    widget.onDone?.call(identity);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.identity != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(isEditing ? 'Change your bean' : 'Make your bean'),
      ),
      body: SafeArea(
        child: Center(
          // No scrollbar, for the same reason the welcome screen has none:
          // this is one card you fill in, and a track down the edge of the
          // window makes it read as a page of a form.
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Preview(model: _model),
                    const SizedBox(height: 24),
                    _NameField(model: _model, controller: _nameController),
                    const SizedBox(height: 24),
                    const _SectionLabel('Colour'),
                    const SizedBox(height: 8),
                    _ColorPicker(model: _model),
                    const SizedBox(height: 24),
                    const _SectionLabel('Extras'),
                    const SizedBox(height: 8),
                    _CosmeticPicker(model: _model),
                    const SizedBox(height: 32),
                    _EnterButton(model: _model, onPressed: _enter),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The live bean, rebuilt whenever the colour or the hat changes.
///
/// Two nested [ValueListenableBuilder]s rather than one `setState` on the
/// whole screen: picking a colour must not rebuild the text field and lose
/// the keyboard's place in it.
class _Preview extends StatelessWidget {
  const _Preview({required this.model});

  final SetupViewModel model;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: ValueListenableBuilder<int>(
          valueListenable: model.color,
          builder: (context, color, _) {
            return ValueListenableBuilder<PlayerCosmetic>(
              valueListenable: model.cosmetic,
              builder: (context, cosmetic, _) =>
                  BeanPreview(color: color, cosmetic: cosmetic),
            );
          },
        ),
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.model, required this.controller});

  final SetupViewModel model;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (value) => model.name.value = value,
          onSubmitted: (_) {
            if (model.canEnter.value) FocusScope.of(context).unfocus();
          },
          inputFormatters: [
            // A hard stop at the cap, so the field cannot be typed past the
            // point where the message would say "too long" forever. The
            // validator still runs — this is a courtesy, not the rule.
            LengthLimitingTextInputFormatter(maxNameLength),
          ],
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'What should we call you?',
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
              borderSide: BorderSide.none,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // A fixed-height slot, so the fields below do not jump up and down as
        // the message appears and disappears while somebody types.
        SizedBox(
          height: 34,
          child: ValueListenableBuilder<String>(
            valueListenable: model.hint,
            builder: (context, hint, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                hint,
                style: const TextStyle(color: AppTheme.warn, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.model});

  final SetupViewModel model;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: model.color,
      builder: (context, selected, _) {
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final color in beanColors)
              _Swatch(
                color: color,
                isSelected: color == selected,
                onTap: () => model.color.value = color,
              ),
          ],
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final int color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? AppTheme.ink : Colors.transparent,
              width: 3,
            ),
          ),
        ),
      ),
    );
  }
}

class _CosmeticPicker extends StatelessWidget {
  const _CosmeticPicker({required this.model});

  final SetupViewModel model;

  static const Map<PlayerCosmetic, String> _labels = {
    PlayerCosmetic.none: 'None',
    PlayerCosmetic.cap: 'Cap',
    PlayerCosmetic.headphones: 'Headphones',
    PlayerCosmetic.malingaHair: 'Spiky Hair',
    PlayerCosmetic.laserVisor: 'Laser Visor',
    PlayerCosmetic.propellerBeanie: 'Propeller Beanie',
  };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerCosmetic>(
      valueListenable: model.cosmetic,
      builder: (context, selected, _) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final cosmetic in PlayerCosmetic.values)
              ChoiceChip(
                label: Text(_labels[cosmetic] ?? cosmetic.wireName),
                selected: cosmetic == selected,
                onSelected: (_) => model.cosmetic.value = cosmetic,
              ),
          ],
        );
      },
    );
  }
}

class _EnterButton extends StatelessWidget {
  const _EnterButton({required this.model, required this.onPressed});

  final SetupViewModel model;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: model.canEnter,
      builder: (context, canEnter, _) {
        return FilledButton(
          // Inert rather than hidden: a button that vanishes leaves somebody
          // wondering what they did wrong, and the message under the field
          // already says.
          onPressed: canEnter ? onPressed : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Enter the world'),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppTheme.mutedInk,
        fontSize: 12,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
