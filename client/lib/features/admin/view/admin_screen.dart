import 'dart:async';
import 'dart:convert';

import 'package:client/core/event_clock.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/admin/view_model/admin_view_model.dart';
import 'package:client/game/beach_map.dart';
import 'package:client/game/world_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:protocol/protocol.dart';
import 'package:provider/provider.dart';

/// The moderation dashboard.
///
/// Reached only by typing the address — nothing in the player-facing app
/// links here, mentions it, or hints that it exists.
///
/// Built for a phone held at an event, not a desk: big targets, a search box
/// because a 200-row list is otherwise unusable with a thumb, and a
/// confirmation on every action because the cost of a mis-tap here is
/// disconnecting a stranger.
class AdminScreen extends StatelessWidget {
  /// Creates the screen.
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AdminViewModel>();

    return Scaffold(
      body: SafeArea(
        child: _Feedback(
          model: model,
          child: model.isUnlocked ? const _Unlocked() : const _TokenGate(),
        ),
      ),
    );
  }
}

/// Shows the ViewModel's one-line messages as a snack bar, then clears them.
class _Feedback extends StatefulWidget {
  const _Feedback({required this.model, required this.child});

  final AdminViewModel model;
  final Widget child;

  @override
  State<_Feedback> createState() => _FeedbackState();
}

class _FeedbackState extends State<_Feedback> {
  @override
  void didUpdateWidget(_Feedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    final feedback = widget.model.feedback;
    if (feedback == null) return;

    // After the frame: showing a snack bar during a build is a framework
    // error, and this is called from one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        // Removed rather than cleared: `clearSnackBars` plays the exit
        // animation, so a moderator taking three actions in five seconds
        // would watch the *first* message sit there while the newest one
        // waited behind it. The latest thing that happened is the only one
        // worth reading.
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(feedback.message),
            backgroundColor: feedback.isError ? AppTheme.bad : AppTheme.good,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      widget.model.clearFeedback();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The token field. Everything the screen can do is behind it.
class _TokenGate extends StatefulWidget {
  const _TokenGate();

  @override
  State<_TokenGate> createState() => _TokenGateState();
}

class _TokenGateState extends State<_TokenGate> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    // The token does not outlive the field it was typed into.
    _controller
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _submit() {
    final token = _controller.text;
    _controller.clear();
    unawaitedSubmit(context.read<AdminViewModel>(), token);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AdminViewModel>();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 40,
                color: AppTheme.mutedInk,
              ),
              const SizedBox(height: 16),
              Text(
                'Moderation',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Moderation token',
                  filled: true,
                  fillColor: AppTheme.surface,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: model.isAuthenticating ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  model.isAuthenticating ? 'Checking…' : 'Unlock',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'The token is kept in memory only. Reloading this page asks '
                'for it again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mutedInk, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fires the ViewModel command without making the caller `async`.
///
/// Named rather than inlined so the "we deliberately do not await this"
/// decision is visible: the screen re-renders from `notifyListeners`, so
/// there is nothing for the button's callback to wait for.
void unawaitedSubmit(AdminViewModel model, String token) {
  model.submitToken(token).ignore();
}

/// What a moderator sees once the token is accepted.
///
/// Two tabs, because the two jobs have nothing to do with each other and
/// stacking them on one scroll would put a JSON editor under a two-hundred
/// row list. **People** is the incident tool and stays first; **Event** is the
/// thing you set up once in the morning.
class _Unlocked extends StatelessWidget {
  const _Unlocked();

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'PEOPLE'),
              Tab(text: 'EVENT'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_PlayerList(), _EventPanel()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The live list: search and map filters on top, one row per player.
class _PlayerList extends StatelessWidget {
  const _PlayerList();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AdminViewModel>();
    final rows = model.visiblePlayers;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: model.setSearch,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search by name or id',
                    prefixIcon: Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Lock',
                onPressed: model.lock,
                icon: const Icon(Icons.lock_outline, size: 18),
              ),
            ],
          ),
        ),
        const _MapFilters(),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    model.players.isEmpty
                        ? 'Nobody is in the world.'
                        : 'Nobody matches that.',
                    style: const TextStyle(color: AppTheme.mutedInk),
                  ),
                )
              : ListView.builder(
                  // Builder, not a Column: at 300 attendees this list is
                  // long, and building every row for a screen that shows
                  // eight of them is the difference between a usable phone
                  // and a slideshow.
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final player = rows[index];
                    // With **All** selected the list groups by map, so one
                    // scroll reads as a master list and as two per-map lists
                    // at the same time. A heading is drawn where the map
                    // changes rather than by building sections, so the list
                    // stays a flat builder and stays cheap.
                    final isFirstOfMap =
                        model.isGroupedByMap &&
                        (index == 0 || rows[index - 1].map != player.map);
                    if (!isFirstOfMap) return _PlayerRow(player: player);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MapHeading(map: player.map),
                        _PlayerRow(player: player),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The filter chips: `All 42 · Conference 30 · Beach 12`.
///
/// The counts are the reason this is chips and not a dropdown. A moderator
/// acting on a report needs to know **where** before they can act, and a
/// control that hides the numbers behind a tap makes them ask the room.
///
/// They compose with the search box above rather than replacing it: the two
/// answer different questions, and a report usually arrives with both halves
/// of the answer in it.
class _MapFilters extends StatelessWidget {
  const _MapFilters();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AdminViewModel>();

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final map in <MapId?>[null, ...MapId.values]) ...[
            _FilterChip(
              label: map?.label ?? 'All',
              count: model.countFor(map),
              isSelected: model.mapFilter == map,
              onTap: () => model.setMapFilter(map),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// One filter chip: a name and how many people are behind it.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.ink.withValues(alpha: 0.12)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected
                  ? AppTheme.ink.withValues(alpha: 0.4)
                  : AppTheme.ink.withValues(alpha: 0.1),
            ),
          ),
          child: Text(
            '$label $count',
            style: TextStyle(
              color: isSelected ? AppTheme.ink : AppTheme.mutedInk,
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// The line that says which map the rows under it are on.
class _MapHeading extends StatelessWidget {
  const _MapHeading({required this.map});

  final MapId map;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Text(
            map.label.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.mutedInk,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(color: AppTheme.ink.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }
}

/// One player, and the three things that can be done to them.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player});

  final AdminPlayerSummary player;

  @override
  Widget build(BuildContext context) {
    final model = context.read<AdminViewModel>();

    return ListTile(
      title: Row(
        children: [
          Flexible(
            child: Text(
              player.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                // Struck through when muted: the row still shows what they
                // chose, because a list of identical Guests is a list nobody
                // can moderate.
                decoration: player.isNameMuted
                    ? TextDecoration.lineThrough
                    : null,
                color: player.isNameMuted ? AppTheme.mutedInk : AppTheme.ink,
              ),
            ),
          ),
          if (player.isNameMuted) ...[
            const SizedBox(width: 8),
            const Text(
              mutedDisplayName,
              style: TextStyle(color: AppTheme.warn, fontSize: 12),
            ),
          ],
        ],
      ),
      subtitle: Text(
        // The map is on every row, not only in the grouping. The coordinates
        // beside it are meaningless without it — the two maps are separate
        // coordinate spaces, so "600, 310" is the middle of the beach's sand
        // and also a spot in the conference's food court.
        '${player.map.label}  ·  ${player.id}  ·  '
        '${player.x.toInt()}, ${player.y.toInt()}',
        style: const TextStyle(color: AppTheme.mutedInk, fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionButton(
            icon: player.isNameMuted
                ? Icons.record_voice_over_outlined
                : Icons.voice_over_off_outlined,
            tooltip: player.isNameMuted ? 'Restore name' : 'Mute name',
            color: AppTheme.warn,
            onPressed: () => _confirm(
              context,
              title: player.isNameMuted ? 'Restore name?' : 'Mute name?',
              body: player.isNameMuted
                  ? '${player.name} will be shown under their own name '
                        'again.'
                  : '${player.name} will be shown to everybody as '
                        '$mutedDisplayName. They stay in the world.',
              confirmLabel: player.isNameMuted ? 'Restore' : 'Mute',
              onConfirm: () => model.setNameMuted(
                player.id,
                muted: !player.isNameMuted,
              ),
            ),
          ),
          _ActionButton(
            icon: Icons.logout,
            tooltip: 'Kick',
            color: AppTheme.ink,
            onPressed: () => _confirm(
              context,
              title: 'Kick ${player.name}?',
              body: 'They are disconnected immediately and can rejoin.',
              confirmLabel: 'Kick',
              onConfirm: () => model.kick(player.id),
            ),
          ),
          _ActionButton(
            icon: Icons.block,
            tooltip: 'Ban',
            color: AppTheme.bad,
            onPressed: () => _confirm(
              context,
              title: 'Ban ${player.name}?',
              body:
                  'They are disconnected and blocked for the rest of the '
                  'event. This is not undoable from here.',
              confirmLabel: 'Ban',
              isDestructive: true,
              onConfirm: () => model.ban(player.id),
            ),
          ),
        ],
      ),
    );
  }

  /// Puts one question in front of the moderator before anything happens.
  ///
  /// Every action gets one, including the mild ones. The rows reorder as
  /// people are muted and as the list refreshes, so the realistic mistake is
  /// not "meant to kick, tapped ban" — it is "tapped the right button on the
  /// wrong row". A dialog naming the person is what catches that.
  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required VoidCallback onConfirm,
    bool isDestructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: isDestructive ? AppTheme.bad : null,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed ?? false) onConfirm();
  }
}

/// One icon button, sized for a thumb.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 20, color: color),
  );
}

/// Everything about the event that is not a person: the crowd dials and the
/// config document itself.
class _EventPanel extends StatefulWidget {
  const _EventPanel();

  @override
  State<_EventPanel> createState() => _EventPanelState();
}

class _EventPanelState extends State<_EventPanel> {
  final TextEditingController _editor = TextEditingController();

  /// The field the confirmation dialog types the token into.
  ///
  /// Owned by the panel rather than built per dialog so it can be disposed at
  /// a moment when nothing is using it — see [_askToken]. It holds a
  /// credential for as long as one dialog is open and is cleared the instant
  /// that dialog closes.
  final TextEditingController _tokenField = TextEditingController();

  AdminViewModel? _model;

  /// The server's document as it was when the editor was last filled from it.
  ///
  /// Kept so the screen can tell "the moderator has typed something" apart
  /// from "the server has moved on", which are the two ways the box and the
  /// server come to disagree and want opposite handling.
  String _loaded = '';

  /// Which [AdminViewModel.configRevision] this editor has already taken in.
  int _seenRevision = 0;

  /// Whether a push has gone up and not yet been answered.
  ///
  /// The editor follows the server's copy while it is clean, and stops
  /// following it the moment somebody types. This is the exception: a
  /// document *this* moderator pushed is one they asked to be adopted, so the
  /// answer to it overwrites their text even though it is dirty. Without it
  /// the box keeps the version they typed, the server keeps the version it
  /// normalised, and the two never agree again.
  bool _pendingPush = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final model = context.read<AdminViewModel>();
    if (identical(model, _model)) return;
    _model?.removeListener(_onModelChanged);
    _model = model..addListener(_onModelChanged);
    _seenRevision = model.configRevision;
    _adopt(model.configDocument);
  }

  @override
  void dispose() {
    _model?.removeListener(_onModelChanged);
    _editor.dispose();
    // The token does not outlive the panel it was typed into.
    _tokenField
      ..clear()
      ..dispose();
    super.dispose();
  }

  /// Whether the box holds something the server has not been given.
  bool get _isDirty => _editor.text != _loaded;

  /// Whether the server's copy moved on while the moderator was typing.
  bool get _isStale => (_model?.configDocument ?? _loaded) != _loaded;

  /// Takes the server's copy into the editor.
  ///
  /// **Only assigns when the text actually differs.** Setting
  /// `TextEditingController.text` collapses the selection, so an assignment
  /// of the string that is already there is not a no-op at all: it drops the
  /// caret to the end and wipes whatever the moderator had selected. The
  /// player list arrives once a second, so doing that unconditionally made
  /// the box impossible to edit or copy out of.
  void _adopt(String document) {
    _loaded = document;
    if (_editor.text == document) return;
    _editor.text = document;
  }

  /// Reacts to the server, rather than to a rebuild.
  ///
  /// A listener and not `build`, because the two happen at completely
  /// different rates: the panel rebuilds every time anything on the socket
  /// notifies — once a second, for the player list — and the config changes
  /// when a human edits it. Touching the controller on the former is what
  /// made typing here impossible.
  void _onModelChanged() {
    final model = _model;
    if (model == null) return;

    // A refused push is still an answer. Clearing this here is what stops a
    // rejected document being silently overwritten by somebody else's edit
    // half an hour later.
    if (model.feedback?.isError ?? false) _pendingPush = false;

    if (model.configRevision == _seenRevision) return;
    _seenRevision = model.configRevision;

    final adopt = _pendingPush || !_isDirty;
    _pendingPush = false;
    setState(() {
      if (adopt) _adopt(model.configDocument);
    });
  }

  /// Fills the editor from the server's copy, throwing away local edits.
  void _revert(AdminViewModel model) {
    _pendingPush = false;
    setState(() => _adopt(model.configDocument));
  }

  /// Sends what is in the box, and remembers that it is waiting on an answer.
  void _push(AdminViewModel model) {
    _pendingPush = true;
    // Notifies synchronously when it refuses to send, which is why the flag
    // is set first: the listener above is what clears it again.
    model.pushConfig(_editor.text);
  }

  /// Puts the document on the clipboard.
  ///
  /// Its own button because selecting sixteen lines of JSON with a thumb, in
  /// a box that scrolls, is not a thing anybody manages twice.
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _editor.text));
    if (!mounted) return;
    _say('Copied the document.', isError: false);
  }

  /// Re-indents the box as JSON, without changing what it says.
  ///
  /// Deliberately a raw re-print rather than a round trip through
  /// [AppConfig]: this is a tidy-up, and one that quietly deleted a key the
  /// moderator had just added would be a much worse button than none.
  void _format() {
    final Object? decoded;
    try {
      decoded = jsonDecode(_editor.text);
    } on FormatException catch (error) {
      _say('That is not JSON yet: ${error.message}', isError: true);
      return;
    }
    setState(() {
      _editor.text = const JsonEncoder.withIndent('  ').convert(decoded);
    });
  }

  void _say(String message, {required bool isError}) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppTheme.bad : AppTheme.good,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final model = _model!;
    final isDirty = _isDirty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const _SectionTitle('How busy each map looks'),
        const SizedBox(height: 4),
        const Text(
          'The beans standing around who are not people. Nobody is '
          'disconnected by this — it is scenery.',
          style: TextStyle(color: AppTheme.mutedInk, fontSize: 12),
        ),
        const SizedBox(height: 12),
        for (final map in MapId.values) _BotDial(map: map, model: model),
        const SizedBox(height: 28),
        const _SectionTitle('The event document'),
        const SizedBox(height: 4),
        const Text(
          'Pushed to everybody who is connected, straight away, and kept '
          'across a restart.',
          style: TextStyle(color: AppTheme.mutedInk, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () => unawaited(_copy()),
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              label: const Text('Copy'),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _format,
              icon: const Icon(Icons.format_align_left, size: 16),
              label: const Text('Tidy'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _editor,
          maxLines: 16,
          minLines: 8,
          keyboardType: TextInputType.multiline,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.4,
          ),
          decoration: const InputDecoration(
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isDirty ? () => _push(model) : null,
                icon: const Icon(Icons.publish, size: 18),
                label: const Text('Push to everybody'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: isDirty || _isStale ? () => _revert(model) : null,
              child: const Text('Revert'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          switch ((isDirty, _isStale)) {
            // Somebody else pushed while this box was being typed in. Said
            // out loud, because reverting here throws work away and a
            // moderator about to tap it deserves to know which of the two
            // copies they are losing.
            (true, true) =>
              'Not pushed yet — and somebody else changed the document while '
                  'you were typing. Revert to see theirs.',
            (true, false) =>
              'Not pushed yet. The world is still showing the old copy.',
            (false, _) => 'This is what the server is serving.',
          },
          style: TextStyle(
            color: isDirty ? AppTheme.warn : AppTheme.mutedInk,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 28),
        _MaintenanceCard(
          model: model,
          onClose: () => unawaited(_closeEvent(model)),
          onReopen: () => unawaited(_reopenEvent(model)),
        ),
      ],
    );
  }

  /// Picks a moment, confirms it twice, and closes the event.
  ///
  /// Four decisions for one action, which is deliberate. This is the only
  /// control in the app that removes *everybody*, and each of the things it
  /// asks for — a day, a time, a confirmation, the token again — is another
  /// chance to notice that you are about to do it.
  Future<void> _closeEvent(AdminViewModel model) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      // No practical ceiling. A month was a guard against a mis-scrolled
      // year, but it also refused the legitimate answers — "shut until the
      // next edition", "shut until we say otherwise" — and there is already
      // a confirmation, a token and a one-tap reopen standing between a
      // thumb and this. A century is "no limit" spelt in a way a date picker
      // can render.
      lastDate: DateTime(now.year + 100, now.month, now.day),
      helpText: 'Closed until which day?',
    );
    if (!mounted || date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      helpText: 'Closed until what time?',
    );
    if (!mounted || time == null) return;

    final until = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!until.isAfter(DateTime.now())) {
      // Caught here as well as on the server: "today" plus a time that has
      // already gone is the easy slip, and a round trip to be told so is a
      // round trip nobody needed.
      _say('That time has already passed.', isError: true);
      return;
    }

    if (!await _confirmClosure(until, online: model.online)) return;
    if (!mounted) return;

    final token = await _askToken(
      title: 'Close the event',
      detail: 'Type the moderation token to confirm.',
    );
    if (!mounted || token == null) return;

    model.setMaintenance(token: token, until: until);
  }

  /// Reopens the event, once the token has been typed again.
  ///
  /// No confirmation step in front of the token here: reopening is the safe
  /// direction, and a dialog in front of a fix is a dialog somebody has to
  /// read while a room waits.
  Future<void> _reopenEvent(AdminViewModel model) async {
    final token = await _askToken(
      title: 'Reopen the event',
      detail: 'Type the moderation token to let everybody back in.',
    );
    if (!mounted || token == null) return;

    model.setMaintenance(token: token);
  }

  Future<bool> _confirmClosure(DateTime until, {required int online}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Close the event?'),
        content: Text(
          'Everybody in the world right now — $online of them — will be '
          'disconnected, and nobody can join until '
          '${formatLocalMoment(until)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Asks for the token again, and hands back what was typed.
  ///
  /// Deliberately does **not** reach for the token the ViewModel is already
  /// holding to check the answer here. A dialog that validated locally would
  /// have the shape of a security question and none of the substance; what is
  /// typed goes to the server, which is the only thing that can say no. The
  /// controller is cleared and disposed with the dialog, so this screen never
  /// holds a second copy of the credential.
  Future<String?> _askToken({
    required String title,
    required String detail,
  }) async {
    final controller = _tokenField..clear();
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                detail,
                style: const TextStyle(
                  color: AppTheme.mutedInk,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                onSubmitted: (value) => Navigator.of(context).pop(value),
                decoration: const InputDecoration(
                  labelText: 'Moderation token',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    } finally {
      // Cleared, not disposed. The dialog's route is still animating out at
      // this point and its field is still holding this controller, so
      // disposing here tears the controller out from under a live widget.
      // The credential is gone either way; the object outlives the dialog
      // and dies with the panel, exactly as the token gate's does.
      controller.clear();
    }
  }
}

/// The one control that takes the whole event down, and puts it back up.
///
/// At the bottom of the panel, under the document, on purpose: it is the
/// thing you reach for once a day and the last thing a thumb should land on
/// by accident.
class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({
    required this.model,
    required this.onClose,
    required this.onReopen,
  });

  /// Where the current window is read from.
  final AdminViewModel model;

  /// Called to start picking a closing time.
  final VoidCallback onClose;

  /// Called to let everybody back in.
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final until = model.maintenanceUntil;
    final isClosed = model.isUnderMaintenance;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isClosed
              ? AppTheme.warn
              : AppTheme.mutedInk.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isClosed ? Icons.lock_clock : Icons.construction,
                size: 18,
                color: isClosed ? AppTheme.warn : AppTheme.mutedInk,
              ),
              const SizedBox(width: 8),
              const Expanded(child: _SectionTitle('Maintenance')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isClosed && until != null
                ? 'The event is closed. Nobody can join until '
                      '${formatLocalMoment(until)}, and everybody who was in '
                      'it has been disconnected.'
                : 'Closing the event disconnects everybody and keeps the '
                      'doors shut until a time you pick. Nobody is banned or '
                      'kicked — they come back as themselves.',
            style: TextStyle(
              color: isClosed ? AppTheme.warn : AppTheme.mutedInk,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          if (isClosed)
            FilledButton.icon(
              onPressed: onReopen,
              icon: const Icon(Icons.lock_open, size: 18),
              label: const Text('Reopen the event now'),
            )
          else
            OutlinedButton.icon(
              onPressed: onClose,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.bad,
                side: const BorderSide(color: AppTheme.bad),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.lock_clock, size: 18),
              label: const Text('Close the event for maintenance'),
            ),
        ],
      ),
    );
  }
}

/// One map's crowd dial.
class _BotDial extends StatelessWidget {
  const _BotDial({required this.map, required this.model});

  /// Which world this dial turns.
  final MapId map;

  /// Where the number comes from and where a change goes.
  final AdminViewModel model;

  /// How many bots [map] ships with.
  ///
  /// Where the dial starts counting down from when it has been showing
  /// **All**. Approximate on the conference, which grows a bean per sponsor
  /// booth — it is a starting point for a thumb, not a claim.
  static int rosterSize(MapId map) => switch (map) {
    MapId.conference => ConferenceMap.empty.bots.length,
    MapId.beach => const BeachMap().bots.length,
  };

  @override
  Widget build(BuildContext context) {
    final count = model.botCountFor(map);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              map.label,
              style: const TextStyle(color: AppTheme.ink, fontSize: 14),
            ),
          ),
          IconButton(
            tooltip: 'Fewer',
            onPressed: (count ?? rosterSize(map)) <= 0
                ? null
                : () => model.setBotCount(map, (count ?? rosterSize(map)) - 1),
            icon: const Icon(Icons.remove_circle_outline, size: 22),
          ),
          SizedBox(
            width: 44,
            child: Text(
              count?.toString() ?? 'All',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: count == null
                ? null
                : () => model.setBotCount(map, count + 1),
            icon: const Icon(Icons.add_circle_outline, size: 22),
          ),
          TextButton(
            onPressed: count == null ? null : () => model.clearBotCount(map),
            child: const Text('All'),
          ),
        ],
      ),
    );
  }
}

/// A small all-caps heading.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  /// What it says.
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: AppTheme.ink,
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
    ),
  );
}
