import 'dart:async';

import 'package:client/core/player_identity.dart';
import 'package:client/core/server_endpoint.dart';
import 'package:client/core/sponsor.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/world/view/credit_badge.dart';
import 'package:client/features/world/view/emote_bar.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:client/features/world/view/minimap.dart';
import 'package:client/features/world/view/online_badge.dart';
import 'package:client/features/world/view/perf_hud.dart';
import 'package:client/features/world/view/sponsor_panel.dart';
import 'package:client/features/world/view/world_toast.dart';
import 'package:client/game/beach_map.dart';
import 'package:client/game/bean_appearance.dart';
import 'package:client/game/conference_game.dart';
import 'package:client/game/joystick_side.dart';
import 'package:client/game/world_hud.dart';
import 'package:client/services/connection_supervisor.dart';
import 'package:client/services/identity_store.dart';
import 'package:client/services/network_client.dart';
import 'package:client/services/reconnect_policy.dart';
import 'package:client/services/sponsor_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';
import 'package:provider/provider.dart';

/// Full-screen host for the game plus its HUD.
///
/// The game surface is Flame; anything that is plain UI stays in Flutter
/// widgets on top of it. The boundary is the one rule that matters here:
///
/// - The HUD reads the **connection phase** through Provider. It changes a few
///   times a session.
/// - It reads the **head count, the nearest booth and the minimap** through
///   the game's [WorldHud] notifiers, each of which is written at most a few
///   times a second, and each of which rebuilds exactly one small widget.
/// - It never touches player positions, which change sixty times a second and
///   stay inside Flame where they belong.
class WorldScreen extends StatefulWidget {
  /// Creates the world screen.
  const WorldScreen({
    required this.identity,
    required this.store,
    super.key,
    this.mapId = MapId.conference,
    this.appConfig = AppConfig.defaults,
    this.onConfig,
    this.network,
    this.sponsors = const AssetSponsorRepository(),
    this.joystickSide = JoystickSide.right,
    this.onEditIdentity,
    this.onLogout,
    this.onSwitchMap,
    this.onRejected,
  });

  /// Who this client is.
  final PlayerIdentity identity;

  /// Which world this screen is showing.
  ///
  /// Decides two things and nothing else: which `GameMap` the game is built
  /// with, and the `?map=` on the socket. Everything downstream of those two
  /// is map-agnostic, which is what Phase 10's refactor bought.
  final MapId mapId;

  /// Where the joystick-side preference is persisted.
  final IdentityStore store;

  /// The config this world is built from.
  ///
  /// Only one line of it reaches the game — the Code Lab's projector — and it
  /// is a value rather than a `context.watch`, because it has to be known
  /// *before* the game is built. Config that arrived after the furniture was
  /// recorded would need the display list torn up and rebuilt, and a projector
  /// slide is not worth that.
  final AppConfig appConfig;

  /// Called when the server pushes a newer config down the socket.
  ///
  /// The screen does not act on it — the game already has, in place — this is
  /// how it reaches the provider above the app, so the front door behind this
  /// screen is showing the same event by the time anybody walks back out to
  /// it.
  final void Function(AppConfig config)? onConfig;

  /// The connection to the relay, or `null` to build a real one.
  final NetworkClient? network;

  /// Where the booth list comes from.
  final SponsorRepository sponsors;

  /// Which side the joystick starts on.
  final JoystickSide joystickSide;

  /// Called when the player asks to change their name or bean.
  final VoidCallback? onEditIdentity;

  /// Called when the player asks to walk into the other world.
  ///
  /// The screen does not switch itself. It asks, and whoever owns the app's
  /// stage changes the map and rebuilds this screen under a new key — which
  /// is what tears the old socket, supervisor and game down through the
  /// dispose path that already works, rather than through a second one
  /// written specially for switching.
  final void Function(MapId map)? onSwitchMap;

  /// Called when the player asks to be forgotten by this device.
  ///
  /// Separate from [onEditIdentity] because they are opposite intents: an
  /// edit keeps the person and changes the bean, a log out keeps the phone
  /// and changes the person. Only the caller knows what "forget" has to
  /// clear, so this screen does no more than ask and report.
  final VoidCallback? onLogout;

  /// Called when the server refuses this client's join.
  /// Called when the server refuses this client, with the whole rejection.
  ///
  /// The whole message, not just its sentence: the caller has to branch on
  /// *why*. A bad name sends the player back to setup to fix it; a ban has
  /// nothing to fix, and dropping somebody onto a form they can retype
  /// forever is the cruellest possible version of that screen.
  final void Function(JoinRejectedMessage rejection)? onRejected;

  @override
  State<WorldScreen> createState() => _WorldScreenState();
}

class _WorldScreenState extends State<WorldScreen> {
  /// Owned by this state only when it built the client itself.
  ///
  /// The map is in the URL, at socket-open, because that is the only moment
  /// the server can act on it — see `resolveServerUriFor`.
  late final NetworkClient? _ownedNetwork = widget.network == null
      ? NetworkClient(url: resolveServerUriFor(widget.mapId))
      : null;

  late final NetworkClient _network = widget.network ?? _ownedNetwork!;

  late final ConnectionSupervisor _supervisor = ConnectionSupervisor(
    network: _network,
    identity: widget.identity,
  );

  /// Owned here rather than by the game, because the widgets listening to it
  /// and the game writing to it are torn down in an order neither controls.
  final WorldHud _hud = WorldHud();

  /// Built once the booth config has been read.
  ConferenceGame? _game;

  late JoystickSide _joystickSide = widget.joystickSide;
  bool _reportedRejection = false;
  bool _boothsFailed = false;

  @override
  void initState() {
    super.initState();
    _supervisor.addListener(_onSupervisorChanged);
    unawaited(_start());
  }

  @override
  void dispose() {
    _supervisor
      ..removeListener(_onSupervisorChanged)
      ..dispose();
    _hud.dispose();
    // Only close what this screen opened; an injected client belongs to
    // whoever passed it in.
    unawaited(_ownedNetwork?.dispose());
    super.dispose();
  }

  /// Reads the booth config, then builds the world and connects.
  ///
  /// The booths have to be known before the game is built, because they are
  /// both furniture and collision. Reading a bundled asset is a frame or two,
  /// so this is a flicker rather than a loading screen — and if it fails, the
  /// world still opens with no booths in it. A conference world that will not
  /// start because a sponsor's blurb has a stray comma is the wrong trade.
  Future<void> _start() async {
    var sponsors = const <Sponsor>[];
    var failed = false;
    try {
      sponsors = await widget.sponsors.load();
    } on Object {
      failed = true;
    }
    // Read before the game is built, because the board decides how the local
    // bean is drawn from its very first frame in the water.
    final hasBoard = await widget.store.readHasBoard();
    if (!mounted) return;

    setState(() {
      _boothsFailed = failed;
      _game = ConferenceGame(
        appearance: BeanAppearance(
          bodyColor: Color(widget.identity.color),
          cosmetic: widget.identity.cosmetic,
          cosmeticColor: BeanAppearance.darken(
            Color(widget.identity.color),
            0.34,
          ),
        ),
        playerName: widget.identity.name,
        network: _network,
        config: widget.appConfig,
        onConfig: widget.onConfig,
        map: gameMapFor(
          widget.mapId,
          sponsors: sponsors,
          boardMessage: widget.appConfig.boardMessage,
          stageLines: widget.appConfig.stageLines,
        ),
        hud: _hud,
        joystickSide: _joystickSide,
        hasBoard: hasBoard,
        onBoardChanged: _persistBoard,
      );
    });
    await _supervisor.start();
  }

  /// Writes the board through to the device.
  ///
  /// Fire and forget: the game has already applied the change and drawn it,
  /// and a board that failed to persist costs somebody one re-hunt rather
  /// than a broken world. Same trade the joystick side already makes.
  void _persistBoard({required bool hasBoard}) =>
      unawaited(widget.store.writeHasBoard(hasBoard: hasBoard));

  void _onSupervisorChanged() {
    final rejection = _supervisor.rejection;
    if (rejection == null || _reportedRejection) return;
    _reportedRejection = true;
    widget.onRejected?.call(rejection);
  }

  Future<void> _toggleJoystickSide() async {
    final side = _joystickSide.opposite;
    setState(() {
      _joystickSide = side;
      _game?.joystickSide = side;
    });
    await widget.store.writeJoystickSide(side);
  }

  /// The map this screen is *not* showing: the one the switch goes to.
  ///
  /// Two maps, so "the other one" is a complete answer. A third would make
  /// this a menu, which is exactly the reason Phase 10 stopped at two.
  MapId get _otherMap => MapId.values.firstWhere(
    (map) => map != widget.mapId,
    orElse: () => widget.mapId,
  );

  /// Asks before letting the app forget who this device is.
  ///
  /// The only chip up here with a confirm step, and the only one that is not
  /// undone by tapping it again: this throws away the name, the bean and the
  /// session id. A HUD that floats over a thumb-driven game gets mis-tapped,
  /// and a mis-tap must not cost somebody their identity mid-conversation.
  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Log out?'),
        content: const Text(
          'This device will forget your name and your bean. You will start '
          'again from the welcome screen.',
          style: TextStyle(color: AppTheme.mutedInk),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppTheme.mutedInk),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    // The dialog outlives nothing, but the screen it sits on can: a kick or
    // a ban arriving while it is open tears this state down underneath it.
    if (!mounted) return;
    if (confirmed ?? false) widget.onLogout?.call();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    // The emote button sits opposite the joystick. The design puts it on the
    // left, which is right up until a left-handed player moves the stick
    // there — two controls in one thumb's corner is worse than either side.
    final emoteOnLeft = _joystickSide == JoystickSide.right;

    return ChangeNotifierProvider<ConnectionSupervisor>.value(
      value: _supervisor,
      child: Scaffold(
        body: Stack(
          children: [
            if (game != null)
              GameWidget(game: game)
            else
              const ColoredBox(color: AppTheme.background),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _ConnectionChip(),
                          const SizedBox(height: 8),
                          OnlineBadge(online: _hud.online),
                          const SizedBox(height: 8),
                          const CreditBadge(),
                          if (_boothsFailed) ...[
                            const SizedBox(height: 8),
                            const _BoothWarning(),
                          ],
                          if (perfHudEnabled) ...[
                            const SizedBox(height: 8),
                            const PerfHud(),
                          ],
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.topRight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Minimap(
                            frames: _hud.minimap,
                            spec: MapSpec.of(widget.mapId),
                          ),
                          const SizedBox(height: 8),
                          HudChip(
                            onTap: () => unawaited(_toggleJoystickSide()),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.swap_horiz, size: 16),
                                const SizedBox(width: 6),
                                Text('Joystick: ${_joystickSide.label}'),
                              ],
                            ),
                          ),
                          if (widget.onSwitchMap != null &&
                              _otherMap != widget.mapId) ...[
                            const SizedBox(height: 8),
                            HudChip(
                              onTap: () => widget.onSwitchMap!.call(_otherMap),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.explore_outlined, size: 16),
                                  const SizedBox(width: 6),
                                  Text('Go to ${_otherMap.label}'),
                                ],
                              ),
                            ),
                          ],
                          if (widget.onEditIdentity != null) ...[
                            const SizedBox(height: 8),
                            HudChip(
                              onTap: widget.onEditIdentity,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.face_retouching_natural,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(widget.identity.name),
                                ],
                              ),
                            ),
                          ],
                          if (widget.onLogout != null) ...[
                            const SizedBox(height: 8),
                            HudChip(
                              onTap: () => unawaited(_confirmLogout()),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.logout,
                                    size: 16,
                                    color: AppTheme.bad,
                                  ),
                                  SizedBox(width: 6),
                                  Text('Log out'),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Lifted clear of the joystick, which owns a corner of the
                    // bottom edge on whichever side the player put it.
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 168),
                        child: ValueListenableBuilder<Sponsor?>(
                          valueListenable: _hud.nearbySponsor,
                          builder: (context, sponsor, _) =>
                              SponsorPanel(sponsor: sponsor),
                        ),
                      ),
                    ),
                    // Above the booth panel and clear of both bottom
                    // corners, because either one of them may be holding the
                    // joystick.
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 236),
                        child: WorldToastView(toasts: _hud.toast),
                      ),
                    ),
                    Align(
                      alignment: emoteOnLeft
                          ? Alignment.bottomLeft
                          : Alignment.bottomRight,
                      child: EmoteBar(
                        onEmote: (emote) => game?.emote(emote),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Says the booth config could not be read, without stopping the world.
class _BoothWarning extends StatelessWidget {
  const _BoothWarning();

  @override
  Widget build(BuildContext context) {
    return const HudChip(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: 14, color: AppTheme.warn),
          SizedBox(width: 6),
          Text('Booths unavailable'),
        ],
      ),
    );
  }
}

/// Shows whether the client is talking to the server.
///
/// Small and calm on purpose. A dropped socket is not an error screen and not
/// a modal: the player's own bean keeps walking, because it always owned its
/// own position, and this chip is the only thing that changes. Bouncing
/// somebody to the lobby because their phone lost wifi for four seconds is
/// the failure Phase 4 exists to prevent.
class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip();

  @override
  Widget build(BuildContext context) {
    final phase = context.watch<ConnectionSupervisor>().phase;

    return HudChip(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(phase), size: 16, color: _colorFor(phase)),
          const SizedBox(width: 6),
          Text(_labelFor(phase)),
        ],
      ),
    );
  }

  static IconData _iconFor(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.connected => Icons.cloud_done,
    ConnectionPhase.connecting => Icons.cloud_sync,
    ConnectionPhase.waiting || ConnectionPhase.reconnecting => Icons.cloud_sync,
    ConnectionPhase.idle => Icons.cloud_queue,
  };

  static Color _colorFor(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.connected => AppTheme.good,
    ConnectionPhase.connecting => AppTheme.warn,
    ConnectionPhase.waiting || ConnectionPhase.reconnecting => AppTheme.warn,
    ConnectionPhase.idle => AppTheme.mutedInk,
  };

  static String _labelFor(ConnectionPhase phase) => switch (phase) {
    ConnectionPhase.connected => 'Connected',
    ConnectionPhase.connecting => 'Connecting…',
    // One word for the whole waiting-then-retrying cycle, so it does not
    // flicker between two labels once a second while the backoff runs.
    ConnectionPhase.waiting || ConnectionPhase.reconnecting => 'Reconnecting…',
    ConnectionPhase.idle => 'Offline',
  };
}
