import 'dart:async';

import 'package:client/core/event_clock.dart';
import 'package:client/core/theme.dart';
import 'package:flutter/material.dart';

/// What everybody sees while the event is closed.
///
/// The only screen in the app that is shown to a person who did nothing. Every
/// other dead end here — a ban, a kick, a refused name — is about them; this
/// one is about the event, so it says so plainly, names the moment the doors
/// reopen, and offers the way back in the second that moment arrives.
///
/// **The client never decides that maintenance is over.** The countdown
/// reaching zero enables a button; it does not walk anybody back into the
/// world. Tapping the button re-reads the config from the server, and if the
/// window has been extended the screen simply says so again. That is the same
/// rule the kick screen follows, and for the same reason: a client that let
/// itself back in would let itself back in during the restart the window
/// exists for.
///
/// The other half of that rule is that the screen **asks anyway**, on a quiet
/// timer, without anybody tapping anything. A closed-out client has no socket
/// left, so the push that tells everybody else the event reopened cannot
/// reach it; left to itself it would sit out a window a moderator ended ten
/// minutes ago. See [recheckEvery].
class MaintenanceScreen extends StatefulWidget {
  /// Creates the screen.
  const MaintenanceScreen({
    required this.onRetry,
    super.key,
    this.until,
    this.now = DateTime.now,
    this.recheckEvery = const Duration(seconds: 15),
  });

  /// When the event reopens, or `null` if this build was not told.
  ///
  /// Nullable because the screen has to work without it: a client refused by
  /// an older server, or one whose config fetch failed, still needs to be
  /// told the event is closed. It just cannot say for how long.
  final DateTime? until;

  /// Called when the person asks to come back.
  final Future<void> Function() onRetry;

  /// What time it is.
  ///
  /// Injectable for the same reason the server's `ModerationState` and
  /// `AuditLog` take one: a countdown is the one widget whose whole behaviour
  /// is a function of the clock, and `tester.pump` advances Flutter's clock
  /// without moving `DateTime.now` an inch. A test that could not move time
  /// could only assert that the screen renders, which is the least
  /// interesting thing about it.
  final DateTime Function() now;

  /// How often the screen asks the server whether the doors are open again.
  ///
  /// The countdown is a **prediction**, not a fact. A moderator who reopens
  /// the event early leaves every closed-out client holding a timestamp that
  /// has become fiction — and those clients were disconnected by the closure,
  /// so the config push that tells the rest of the app cannot reach them.
  /// Asking on a timer is what closes that gap: the answer either shortens
  /// the countdown, lengthens it, or ends the screen.
  ///
  /// Fifteen seconds is one small HTTP GET per waiting client per quarter
  /// minute — cheap for a few hundred people staring at a paused event, and
  /// short enough that "we are back" reaches the room before anybody thinks
  /// to reload. The ask runs only while there is a window left to wait out,
  /// for the same reason the tick does. Set it to [Duration.zero] to turn it
  /// off, which is what a test that wants to drive the clock by hand does.
  final Duration recheckEvery;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  Timer? _tick;
  bool _retrying = false;
  bool _rechecking = false;
  int _sinceRecheck = 0;

  @override
  void initState() {
    super.initState();
    _startTicking();
  }

  @override
  void didUpdateWidget(MaintenanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.until != widget.until) _startTicking();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Runs a one-second timer, and only while there is something to count.
  ///
  /// Stopped the moment the window closes rather than left running, because
  /// a timer that goes on rebuilding a screen showing a fixed sentence is
  /// exactly the kind of thing that is invisible in a test and expensive on a
  /// phone somebody leaves this tab open on.
  void _startTicking() {
    _tick?.cancel();
    _sinceRecheck = 0;
    if (_left() == null) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      // Rebuilds this screen only. Nothing above it is listening, so a tick
      // costs one `Text`, not the app.
      setState(() {});
      if (_left() == null) {
        timer.cancel();
        return;
      }
      // Counted in ticks rather than given a timer of its own: one clock is
      // easier to reason about than two, and this one already stops and
      // restarts at exactly the moments the recheck should.
      final every = widget.recheckEvery.inSeconds;
      if (every <= 0) return;
      _sinceRecheck++;
      if (_sinceRecheck >= every) {
        _sinceRecheck = 0;
        unawaited(_recheck());
      }
    });
  }

  /// Asks the server, without anybody having asked for it.
  ///
  /// Silent on purpose — no spinner, no error. Nobody pressed anything, so a
  /// failed poll is not news; the screen keeps counting down and tries again
  /// on the next interval, and the button is still there for whoever is
  /// impatient. If the event *has* reopened, [MaintenanceScreen.onRetry] is
  /// what takes this screen off the display, and this widget is disposed
  /// mid-call — which is why nothing after the await touches state.
  Future<void> _recheck() async {
    if (_rechecking || _retrying) return;
    _rechecking = true;
    try {
      await widget.onRetry();
    } on Object {
      // Swallowed deliberately: see above.
    } finally {
      _rechecking = false;
    }
  }

  /// How long is left, or `null` when there is nothing to wait for.
  Duration? _left() {
    final until = widget.until;
    if (until == null) return null;
    final left = until.difference(widget.now());
    return left <= Duration.zero ? null : left;
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      // The screen is often gone by now — the retry is what replaces it — so
      // this is guarded rather than assumed.
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = _left();
    final until = widget.until;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.construction,
                  size: 40,
                  color: AppTheme.warn,
                ),
                const SizedBox(height: 16),
                Text(
                  'The event is paused',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  until == null
                      ? 'Somebody is working on it. Please try again shortly.'
                      : 'Somebody is working on it. The doors open again at '
                            '${formatLocalMoment(until)}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.ink, fontSize: 15),
                ),
                if (left != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'about ${formatCountdown(left)} to go',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.mutedInk,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  // Disabled until the moment arrives, so nobody spends the
                  // window tapping a button that cannot work yet — and so the
                  // countdown above it is the answer to "when", rather than
                  // decoration next to a button that lies.
                  onPressed: left != null || _retrying ? null : _retry,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 14,
                    ),
                  ),
                  child: Text(_retrying ? 'Checking…' : 'Try again'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your name and your bean are safe on this device. You will '
                  'come back as yourself.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.mutedInk, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
