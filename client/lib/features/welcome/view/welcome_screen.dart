import 'dart:async';
import 'dart:math' as math;

import 'package:client/core/app_fonts.dart';
import 'package:client/core/share_link.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/app_config/view_model/app_config_view_model.dart';
import 'package:client/features/welcome/view/bean_parade.dart';
import 'package:client/features/welcome/view/maker_credit.dart';
import 'package:client/features/welcome/view/map_picker.dart';
import 'package:client/features/welcome/view/welcome_backdrop.dart';
import 'package:client/features/welcome/view_model/welcome_view_model.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';
import 'package:provider/provider.dart';

/// The front door: what this is, who is already inside, and a way in.
///
/// Reads its ViewModel through Provider and renders it. No decisions here —
/// whether the Join button goes to setup or straight into the world is
/// [WelcomeViewModel.isReturning], answered by what is on the device.
///
/// Everything that moves on this screen — the drifting backdrop, the parade
/// of beans, the live dot, the button's glow — runs off the one repeating
/// controller below. Six widgets with a ticker each would be six times the
/// wake-ups on a phone that is still only showing a door.
class WelcomeScreen extends StatefulWidget {
  /// Creates the welcome screen.
  const WelcomeScreen({
    required this.onJoin,
    required this.onEditIdentity,
    super.key,
  });

  /// Called when the player asks to go in.
  final VoidCallback onJoin;

  /// Called when a returning player wants to change their name or bean.
  final VoidCallback onEditIdentity;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  /// The ambient loop. Twelve seconds is long enough that the drift reads as
  /// a room breathing rather than as a carousel.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  /// The one-shot arrival: things fade up and settle as the screen opens.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // "Reduce motion" is not a suggestion: an endlessly drifting background
    // is exactly the thing that setting exists to turn off. The screen keeps
    // its first frame, which is a perfectly good still life.
    if (MediaQuery.of(context).disableAnimations) {
      _entrance.value = 1;
    } else {
      _loop.repeat();
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<WelcomeViewModel>();
    final config = context.watch<AppConfigViewModel>().config;
    final size = MediaQuery.sizeOf(context);
    final isNarrow = size.width < 380;
    // Phase 10 added a map picker to a screen that already filled a small
    // phone. Rather than pushing the way in below the fold — where a
    // surprising number of people never find it — the screen gives ground
    // when it is short: the parade shrinks, the gaps tighten, and the stack
    // credit goes. The parade and that credit are the right things to
    // sacrifice, because they are decoration; the picker and the button are
    // the screen.
    final isShort = size.height < 720;
    final gap = isShort ? 10.0 : 16.0;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _loop,
            builder: (context, _) => WelcomeBackdrop(phase: _loop.value),
          ),
          SafeArea(
            child: Center(
              // No scrollbar. This is a front door, and the track down the
              // right edge of it is a browser artefact — it only exists
              // because the column gives ground on a short window, and it
              // reads as a document rather than a place.
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrow ? 20 : 24,
                    vertical: isShort ? 10 : 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Rise(
                          animation: _entrance,
                          order: 0,
                          child: _Title(
                            config: config,
                            compact: isNarrow || isShort,
                          ),
                        ),
                        SizedBox(height: gap + 4),
                        _Rise(
                          animation: _entrance,
                          order: 1,
                          child: _Stage(
                            loop: _loop,
                            height: isShort ? 92 : 156,
                          ),
                        ),
                        SizedBox(height: gap),
                        _Rise(
                          animation: _entrance,
                          order: 2,
                          child: _OnlineCount(model: model, loop: _loop),
                        ),
                        SizedBox(height: gap),
                        _Rise(
                          animation: _entrance,
                          order: 3,
                          // Above the button, not below it: this is a choice
                          // you make *before* you go in, and a picker under the
                          // way in is a picker most people never see.
                          child: MapPicker(
                            selected: model.selectedMap,
                            onSelected: model.selectMap,
                            countOf: model.playersOn,
                          ),
                        ),
                        SizedBox(height: gap),
                        _Rise(
                          animation: _entrance,
                          order: 4,
                          child: _JoinButton(
                            loop: _loop,
                            // Deliberately still one word. The card right
                            // above it is already lit up with the destination,
                            // and a button that repeats the thing you just
                            // tapped is a button that reads as a second choice.
                            label: model.isReturning
                                ? 'Continue as ${model.savedName}'
                                : 'Join',
                            onPressed: widget.onJoin,
                          ),
                        ),
                        if (model.isReturning) ...[
                          const SizedBox(height: 4),
                          _Rise(
                            animation: _entrance,
                            order: 5,
                            child: TextButton(
                              // Without this, a typo in a name is permanent for
                              // as long as the browser keeps its local storage.
                              onPressed: widget.onEditIdentity,
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.mutedInk,
                              ),
                              child: const Text('Change name or bean'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        _Rise(
                          animation: _entrance,
                          order: 5,
                          child: _ShareButton(worldName: config.worldName),
                        ),
                        SizedBox(height: gap + 4),
                        // The stack credit is the first thing to go on a short
                        // screen: it is the only line here that is neither a
                        // way in nor an attribution to a person, and the maker
                        // credit under it already says this is open source.
                        if (!isShort) ...[
                          _Rise(
                            animation: _entrance,
                            order: 5,
                            child: const _Credit(),
                          ),
                          SizedBox(height: gap - 2),
                        ],
                        _Rise(
                          animation: _entrance,
                          order: 6,
                          child: const MakerCredit(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The way to hand this place to somebody standing next to you.
///
/// Under the way in rather than beside it: the front door has exactly one
/// primary action, and a second button of equal weight next to Join is a
/// choice nobody came here to make. Quiet, but on the first screen — because
/// the moment people share a thing like this is before they have walked in,
/// while they are still deciding who else should be here.
class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.worldName});

  /// What the shared message calls this place.
  final String worldName;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: TextButton.icon(
        onPressed: () => unawaited(shareApp(context, worldName: worldName)),
        icon: const Icon(Icons.ios_share, size: 16),
        label: const Text('Share this world'),
        style: TextButton.styleFrom(foregroundColor: AppTheme.mutedInk),
      ),
    );
  }
}

/// Fades and lifts its child into place, [order] steps behind the one before.
///
/// A stagger rather than one block fade: the eye is led down the screen to
/// the button instead of being handed the whole page at once.
class _Rise extends StatelessWidget {
  const _Rise({
    required this.animation,
    required this.order,
    required this.child,
  });

  final Animation<double> animation;
  final int order;
  final Widget child;

  /// How far apart the steps start, as a fraction of the entrance.
  static const double _stagger = 0.12;

  @override
  Widget build(BuildContext context) {
    final begin = math.min(order * _stagger, 0.6);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(begin, math.min(begin + 0.4, 1), curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, inner) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - curved.value)),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.config, required this.compact});

  /// The copy around the wordmark, which is editable without a rebuild.
  final AppConfig config;

  /// Whether we are on a small phone and the wordmark needs to give ground.
  final bool compact;

  static const LinearGradient _ink = LinearGradient(
    colors: [Color(0xFFEAF6FB), Color(0xFF8FD3E8), Color(0xFFB78BE8)],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Eyebrow(text: config.eyebrow),
        const SizedBox(height: 14),
        // A gradient on the wordmark rather than on a box behind it: the
        // colour lands on the thing people are actually looking at.
        ShaderMask(
          shaderCallback: (bounds) => _ink.createShader(bounds),
          child: Text(
            config.worldName,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: compact ? 32 : 38,
              height: 1.05,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          config.tagline,
          style: const TextStyle(
            color: AppTheme.mutedInk,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// The small capsule over the wordmark that says what kind of thing this is.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text});

  /// What it says. Upper-cased here rather than in the config, so whoever
  /// edits the copy writes a sentence and gets the styling for free.
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.ink.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.ink.withValues(alpha: 0.1)),
        ),
        child: Text(
          text.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.mutedInk,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

/// The glass panel the parade walks across.
class _Stage extends StatelessWidget {
  const _Stage({required this.loop, this.height = 156});

  final Animation<double> loop;

  /// How tall the panel is. Shorter on a screen with no room to spare.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppTheme.surface.withValues(alpha: 0.55),
        border: Border.all(color: AppTheme.ink.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AnimatedBuilder(
          animation: loop,
          builder: (context, _) => BeanParade(phase: loop.value),
        ),
      ),
    );
  }
}

/// How many people are in the world, or an honest "cannot tell".
class _OnlineCount extends StatelessWidget {
  const _OnlineCount({required this.model, required this.loop});

  final WelcomeViewModel model;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    final count = model.onlineCount;

    final (Color dot, String label) = switch (model) {
      _ when model.isLoading => (AppTheme.mutedInk, 'Checking…'),
      // A number the server actually gave us. Zero is a real answer and says
      // so plainly — "be the first" is friendlier than a bare 0.
      _ when count == 0 => (AppTheme.good, 'Nobody here yet — be the first'),
      _ when count != null => (
        AppTheme.good,
        '$count ${count == 1 ? 'person' : 'people'} walking around',
      ),
      // Not an error screen: the world still works, we just could not count
      // it. Phase 4's rule is that the network never blocks the door.
      _ => (AppTheme.warn, 'Explore!!!'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.ink.withValues(alpha: 0.07)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LiveDot(color: dot, loop: loop),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.ink,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dot with a halo that breathes, the way a "live" light should.
class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color, required this.loop});

  final Color color;
  final Animation<double> loop;

  /// Breaths per loop. Whole, so the pulse does not jump when the loop wraps.
  static const int _pulses = 12;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final wave = 0.5 + 0.5 * math.sin(2 * math.pi * loop.value * _pulses);
          return Center(
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15 + 0.35 * wave),
                    blurRadius: 4 + 6 * wave,
                    spreadRadius: 1 + 3 * wave,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The way in: one big target, lit from underneath.
///
/// Thumb-sized on purpose — this is the only thing on the screen most people
/// will ever touch, and they will touch it one-handed, standing up.
class _JoinButton extends StatelessWidget {
  const _JoinButton({
    required this.loop,
    required this.label,
    required this.onPressed,
  });

  final Animation<double> loop;
  final String label;
  final VoidCallback onPressed;

  static const Color _accent = Color(0xFF54C5F8);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, child) {
        final wave = 0.5 + 0.5 * math.sin(2 * math.pi * loop.value * 2);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.18 + 0.16 * wave),
                blurRadius: 24 + 12 * wave,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        );
      },
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: const Color(0xFF07202B),
          padding: const EdgeInsets.symmetric(vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Built with Flutter, Flame and Dart · open source',
      style: TextStyle(color: AppTheme.mutedInk, fontSize: 12),
      textAlign: TextAlign.center,
    );
  }
}
