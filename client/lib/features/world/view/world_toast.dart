import 'dart:async';

import 'package:client/core/theme.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:client/game/world_hud.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// The one line the world says out loud, when it has something to say.
///
/// Sits on the widget side of the HUD boundary and reads a [ValueNotifier]
/// written a handful of times in a whole session, which is what makes it
/// allowed across at all — see [WorldHud].
///
/// One at a time, and the newest wins. A queue would mean a player who taps
/// the board three times fast watches fifteen seconds of backlog scroll past
/// after they have already got the board, which is the opposite of a
/// confirmation.
class WorldToastView extends StatefulWidget {
  /// Creates the toast view over [toasts].
  const WorldToastView({
    required this.toasts,
    super.key,
    this.hold = const Duration(seconds: 5),
    this.fade = const Duration(milliseconds: 220),
  });

  /// The channel the game raises toasts on.
  final ValueListenable<WorldToast?> toasts;

  /// How long a toast stays up once it has faded in.
  final Duration hold;

  /// How long the fade in and the fade out each take.
  final Duration fade;

  @override
  State<WorldToastView> createState() => _WorldToastViewState();
}

class _WorldToastViewState extends State<WorldToastView> {
  WorldToast? _showing;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.toasts.addListener(_onToast);
    _showing = widget.toasts.value;
    if (_showing != null) _restartTimer();
  }

  @override
  void dispose() {
    widget.toasts.removeListener(_onToast);
    _timer?.cancel();
    super.dispose();
  }

  void _onToast() {
    final toast = widget.toasts.value;
    if (toast == null) return;
    setState(() => _showing = toast);
    _restartTimer();
  }

  /// Restarts the hold, so a second toast replaces the first rather than
  /// inheriting the remains of its five seconds.
  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(widget.hold, () {
      if (mounted) setState(() => _showing = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final toast = _showing;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: toast == null ? 0 : 1,
        duration: widget.fade,
        curve: Curves.easeOut,
        child: HudChip(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Text(
            // The last message is kept while the widget fades out, so the
            // text does not vanish a fifth of a second before the pill does.
            toast?.message ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
