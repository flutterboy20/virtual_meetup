import 'dart:async';
import 'dart:math' as math;

import 'package:client/core/app_fonts.dart';
import 'package:client/core/credits.dart';
import 'package:client/core/open_link.dart';
import 'package:client/core/player_identity.dart';
import 'package:client/core/share_link.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/app_config/view_model/app_config_view_model.dart';
import 'package:client/features/setup/view_model/setup_view_model.dart';
import 'package:client/features/welcome/view/badge_editor.dart';
import 'package:client/features/welcome/view/maker_credit.dart';
import 'package:client/features/welcome/view/map_picker.dart';
import 'package:client/features/welcome/view_model/welcome_view_model.dart';
import 'package:client/services/identity_store.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The front door: your badge, the two halls, and a way in.
///
/// Phase 15 folded the old setup screen into this one. There used to be a
/// door, then a form, then the world; now the form *is* the door — a
/// conference badge you write your name on — so a first-timer is one screen
/// from walking in, and a returning player finds their badge already filled
/// in and taps straight through.
///
/// Two view models, one per job, and neither knows about the other:
/// [WelcomeViewModel] (from Provider) answers "who is inside, and where am I
/// going", and a [SetupViewModel] owned here answers "who am I". This view
/// decides nothing either of them decides.
///
/// Everything that moves — the badge's sway, the live dot — runs off the one
/// repeating controller below, for the same reason as before: one ticker
/// waking a phone that is only showing a door, not five.
class WelcomeScreen extends StatefulWidget {
  /// Creates the front door.
  const WelcomeScreen({
    required this.store,
    required this.sessionId,
    required this.onJoin,
    super.key,
    this.identity,
    this.notice,
  });

  /// Where the badge is saved when the player goes in.
  final IdentityStore store;

  /// This device's session id, carried into the identity that is saved.
  final String sessionId;

  /// What is already on the device, which the badge starts filled in with.
  final PlayerIdentity? identity;

  /// The server's reason for sending the player back here, if it did.
  final String? notice;

  /// Called with the saved identity once the player goes in.
  final ValueChanged<PlayerIdentity> onJoin;

  /// What the way in says.
  static const String scanInLabel = 'Scan in';

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  /// The ambient loop. Twelve seconds: the badge sways twice in it, which is
  /// the pace of something hanging in still air.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  /// The one-shot arrival: things fade up and settle as the screen opens.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final SetupViewModel _badge = SetupViewModel(
    store: widget.store,
    sessionId: widget.sessionId,
    identity: widget.identity,
  );

  bool _started = false;
  bool _entering = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // "Reduce motion" is not a suggestion. The screen keeps its first frame:
    // a badge hanging straight and a dot that does not pulse.
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
    _badge.dispose();
    super.dispose();
  }

  Future<void> _scanIn() async {
    if (_entering) return;
    _entering = true;
    final identity = await _badge.save();
    _entering = false;
    if (identity == null || !mounted) return;
    widget.onJoin(identity);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<WelcomeViewModel>();
    final config = context.watch<AppConfigViewModel>().config;
    final size = MediaQuery.sizeOf(context);
    final isNarrow = size.width < 380;
    // On a short phone the screen gives ground rather than pushing the way
    // in under the fold: the gaps tighten, the strap shortens, the signs
    // slim down and the stack credit goes. Decoration gives way first; the
    // badge, the signs and the button are the screen.
    final isShort = size.height < 720;
    final gap = isShort ? 10.0 : 16.0;

    return Theme(
      data: AppTheme.lanyard,
      child: Scaffold(
        backgroundColor: LanyardColors.paper,
        body: SafeArea(
          child: Center(
            // No scrollbar: this is a front door, and the track down the
            // edge of it is a browser artefact that reads as a document.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  isNarrow ? 16 : 24,
                  0,
                  isNarrow ? 16 : 24,
                  isShort ? 12 : 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The badge hangs from the top edge, so it has no gap
                      // above it: the strap runs off the screen.
                      _Rise(
                        animation: _entrance,
                        order: 0,
                        child: Center(
                          child: BadgeEditor(
                            model: _badge,
                            eyebrow: config.eyebrow,
                            worldName: config.worldName,
                            swing: _loop,
                            notice: widget.notice,
                            compact: isShort,
                            onSubmitted: () => unawaited(_scanIn()),
                          ),
                        ),
                      ),
                      SizedBox(height: gap + 4),
                      _Rise(
                        animation: _entrance,
                        order: 1,
                        child: _HallHeading(model: model, loop: _loop),
                      ),
                      const SizedBox(height: 8),
                      _Rise(
                        animation: _entrance,
                        order: 2,
                        // Above the button, not below it: this is a choice
                        // made *before* going in, and a picker under the way
                        // in is a picker most people never see.
                        child: MapPicker(
                          selected: model.selectedMap,
                          onSelected: model.selectMap,
                          countOf: model.playersOn,
                          compact: isShort,
                        ),
                      ),
                      SizedBox(height: gap),
                      _Rise(
                        animation: _entrance,
                        order: 3,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _badge.canEnter,
                          builder: (context, canEnter, _) => _ScanInButton(
                            // Inert rather than hidden until the badge has a
                            // name: a button that vanishes leaves somebody
                            // wondering what they did wrong, and the badge
                            // already says.
                            onPressed: canEnter
                                ? () => unawaited(_scanIn())
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _Rise(
                        animation: _entrance,
                        order: 4,
                        child: _ShareButton(worldName: config.worldName),
                      ),
                      SizedBox(height: gap),
                      // The stack credit goes first on a short screen: it is
                      // neither a way in nor an attribution to a person, and
                      // the maker credit under it already says open source.
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
                        order: 5,
                        child: const MakerCredit(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "CHOOSE YOUR HALL", with how many people are inside altogether beside it.
class _HallHeading extends StatelessWidget {
  const _HallHeading({required this.model, required this.loop});

  final WelcomeViewModel model;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        const Text('CHOOSE YOUR HALL', style: LanyardText.eyebrow),
        _OnlineCount(model: model, loop: loop),
      ],
    );
  }
}

/// How many people are in the world, or an honest "cannot tell".
class _OnlineCount extends StatelessWidget {
  const _OnlineCount({required this.model, required this.loop});

  final WelcomeViewModel model;
  final Animation<double> loop;

  /// The "live" green, darkened to read as a light on paper rather than a
  /// glow on glass.
  static const Color _live = Color(0xFF2FB37E);

  @override
  Widget build(BuildContext context) {
    final count = model.onlineCount;

    final (Color dot, String label) = switch (model) {
      _ when model.isLoading => (LanyardColors.mutedInk, 'Checking…'),
      // A number the server actually gave us. Zero is a real answer and says
      // so plainly — "be the first" is friendlier than a bare 0.
      _ when count == 0 => (_live, 'Nobody here yet — be the first'),
      _ when count != null => (
        _live,
        '$count ${count == 1 ? 'person' : 'people'} walking around',
      ),
      // Not an error: the world still works, we just could not count it.
      // Phase 4's rule is that the network never blocks the door.
      _ => (LanyardColors.signal, 'Explore!!!'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LiveDot(color: dot, loop: loop),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: LanyardColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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
      width: 16,
      height: 16,
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final wave = 0.5 + 0.5 * math.sin(2 * math.pi * loop.value * _pulses);
          return Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.12 + 0.25 * wave),
                    blurRadius: 2 + 4 * wave,
                    spreadRadius: 1 + 2 * wave,
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

/// The way in: one big blue target.
///
/// Thumb-sized on purpose — this is the one thing on the screen everybody
/// touches, and they touch it one-handed, standing up.
class _ScanInButton extends StatelessWidget {
  const _ScanInButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: LanyardColors.blue,
        foregroundColor: LanyardColors.badge,
        disabledBackgroundColor: LanyardColors.ink.withValues(alpha: 0.12),
        disabledForegroundColor: LanyardColors.mutedInk,
        minimumSize: const Size.fromHeight(58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w800,
          fontSize: 20,
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(WelcomeScreen.scanInLabel),
          SizedBox(width: 10),
          Icon(Icons.qr_code_scanner_rounded, size: 22),
        ],
      ),
    );
  }
}

/// The way to hand this place to somebody standing next to you, and the way
/// to find out what it is.
///
/// Under the way in rather than beside it: the front door has exactly one
/// primary action. Quiet, but on the first screen — people share a thing
/// like this before they walk in, while deciding who else should be here.
class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.worldName});

  /// What the shared message calls this place.
  final String worldName;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(foregroundColor: LanyardColors.mutedInk);

    // Wrap rather than Row so a narrow screen drops About to a second line
    // instead of overflowing.
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        TextButton.icon(
          onPressed: () => unawaited(shareApp(context, worldName: worldName)),
          icon: const Icon(Icons.ios_share, size: 16),
          label: const Text('Share this world'),
          style: style,
        ),
        TextButton.icon(
          onPressed: () => unawaited(openLink(Credits.aboutPath)),
          icon: const Icon(Icons.info_outline, size: 16),
          label: const Text('About'),
          style: style,
        ),
      ],
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

class _Credit extends StatelessWidget {
  const _Credit();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Built with Flutter, Flame and Dart · open source',
      style: TextStyle(color: LanyardColors.mutedInk, fontSize: 12),
      textAlign: TextAlign.center,
    );
  }
}
