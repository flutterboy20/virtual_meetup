import 'dart:async';

import 'package:client/core/theme.dart';
import 'package:client/features/maintenance/view/maintenance_screen.dart';
import 'package:flutter/material.dart';

/// What somebody sees when every seat in the world is taken.
///
/// The second screen in this app shown to a person who did nothing — a ban, a
/// kick and a refused name are all about *them*, and this and the maintenance
/// screen are about the event. So it says so plainly and offers the way back
/// in.
///
/// **The countdown is deliberately absent**, and that is the whole difference
/// from [MaintenanceScreen], which this otherwise copies. Maintenance ends at
/// a stated moment: the server sends the moment, so the screen can count down
/// to it honestly. "Full" ends when somebody leaves, which nobody knows in
/// advance and the server never sends. A timer here would be the client
/// inventing a number, and a countdown that hit zero to reveal a still-full
/// world would be worse than no countdown at all.
///
/// What replaces it is the same quiet poll the maintenance screen already
/// runs, and here it is doing more work rather than less: a closed-out client
/// has no socket, so nothing can push it the news that a seat freed. See
/// [recheckEvery].
class FullScreen extends StatefulWidget {
  /// Creates the screen.
  const FullScreen({
    required this.onRetry,
    super.key,
    this.message,
    this.recheckEvery = const Duration(seconds: 10),
  });

  /// The server's own words, if it sent any.
  ///
  /// Nullable because the screen has to work without them: a client refused
  /// by a server that said nothing useful still needs to be told what
  /// happened.
  final String? message;

  /// Called when the person asks to come back, or the timer asks for them.
  ///
  /// The same callback for both, on purpose: there is exactly one way back
  /// into the world and it is the server being asked. A tap and a tick must
  /// not be able to take two different routes.
  final Future<void> Function() onRetry;

  /// How often the screen asks the server whether a seat has freed.
  ///
  /// Ten seconds rather than the maintenance screen's fifteen, because the
  /// thing being waited for here is much more likely to have happened: a
  /// maintenance window is minutes long by design, and a seat frees every
  /// time anybody anywhere closes a tab.
  ///
  /// It is one small HTTP GET per waiting client per ten seconds. A few
  /// hundred people in this state is a handful of requests a second, which is
  /// nothing next to the socket traffic the server is already refusing them.
  ///
  /// Set it to [Duration.zero] to turn the poll off, which is what a test
  /// that wants to drive the retry by hand does.
  final Duration recheckEvery;

  @override
  State<FullScreen> createState() => _FullScreenState();
}

class _FullScreenState extends State<FullScreen> {
  Timer? _poll;
  bool _retrying = false;
  bool _rechecking = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Asks the server on a timer, without anybody having asked for it.
  ///
  /// A plain periodic timer rather than the maintenance screen's tick-counter,
  /// because there is no countdown here for it to hang off. That screen
  /// counts recheck intervals in seconds of a clock it is already running for
  /// the display; this one has nothing to display, so it has no reason to
  /// wake up once a second.
  void _startPolling() {
    _poll?.cancel();
    if (widget.recheckEvery <= Duration.zero) return;
    _poll = Timer.periodic(widget.recheckEvery, (_) {
      if (mounted) unawaited(_recheck());
    });
  }

  /// The quiet ask. Silent on purpose — no spinner, no error.
  ///
  /// Nobody pressed anything, so a failed poll is not news; it tries again on
  /// the next interval, and the button is still there for whoever is
  /// impatient. If a seat *has* freed, [FullScreen.onRetry] is what takes
  /// this screen off the display and this widget is disposed mid-call — which
  /// is why nothing after the await touches state.
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
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.groups, size: 40, color: AppTheme.warn),
                const SizedBox(height: 16),
                Text(
                  'The event is full',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.message ??
                      'Every seat is taken right now. We will let you in as '
                          'soon as somebody leaves.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.ink, fontSize: 15),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Checking for a free spot…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.mutedInk, fontSize: 13),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  // Always enabled, unlike the maintenance screen's button.
                  // There the countdown is the honest answer to "when", so a
                  // button that worked early would be a lie. Here nobody
                  // knows when, so refusing to let somebody ask would be the
                  // lie instead.
                  onPressed: _retrying ? null : _retry,
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
