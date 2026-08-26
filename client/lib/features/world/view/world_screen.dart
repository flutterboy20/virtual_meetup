import 'dart:async';

import 'package:client/core/player_identity.dart';
import 'package:client/core/server_endpoint.dart';
import 'package:client/core/share_link.dart';
import 'package:client/core/sponsor.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/world/view/connection_chip.dart';
import 'package:client/features/world/view/credit_badge.dart';
import 'package:client/features/world/view/emote_bar.dart';
import 'package:client/features/world/view/hud_chip.dart';
import 'package:client/features/world/view/minimap.dart';
import 'package:client/features/world/view/online_badge.dart';
import 'package:client/features/world/view/perf_hud.dart';
import 'package:client/features/world/view/sponsor_panel.dart';
import 'package:client/features/world/view/world_menu_drawer.dart';
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

/// The width, in logical pixels, under which the HUD draws itself smaller.
///
/// 480 rather than a tablet breakpoint: this is the width at which the two
/// HUD columns stop leaving a middle of the screen between them. Every phone
/// in portrait is under it and every phone in landscape is over it, which is
/// also the right answer — landscape has the width and not the height.
const double phoneWidth = 480;

/// The gap between two chips in a HUD column, in logical pixels.
const double hudGap = 8;

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
  ///
  /// This is the **first** read of the booth list. Later ones arrive down the
  /// socket and go through [_onConfig], which stands the new booths in the
  /// running world — a moderator's edit shows up in the room within a frame,
  /// in front of the people who are already standing in it.
  Future<void> _start() async {
    var sponsors = const <Sponsor>[];
    var failed = false;
    try {
      // The config first, the bundled file behind it. A moderator who has
      // pushed a sponsor list owns the booths; everybody else gets the one
      // that shipped.
      sponsors = await ConfigSponsorRepository(
        widget.appConfig,
        fallback: widget.sponsors,
      ).load();
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
        onConfig: _onConfig,
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

  /// Takes a config the server pushed while somebody is already in the world.
  ///
  /// Two jobs, and they belong to different layers. The app above wants to
  /// know the config moved — that is [WorldScreen.onConfig], and it is what
  /// keeps the front door's copy current. The world in front of the player
  /// wants the **booths**, which is a client-side parse of an opaque config
  /// list plus a fallback to the bundled file, and so belongs here rather
  /// than in the game: the repository is this screen's.
  void _onConfig(AppConfig config) {
    widget.onConfig?.call(config);
    unawaited(_applyBooths(config));
  }

  /// Re-reads the booth list and hands it to the running world.
  ///
  /// Silent on failure, unlike [_start]'s first read. A booth list that has
  /// stopped parsing is already being shouted about on the admin screen, in
  /// front of the person who broke it; here the honest thing is to keep
  /// standing the booths the room already has rather than emptying an arm of
  /// the map under everybody at once.
  Future<void> _applyBooths(AppConfig config) async {
    try {
      final sponsors = await ConfigSponsorRepository(
        config,
        fallback: widget.sponsors,
      ).load();
      if (!mounted) return;
      _game?.setSponsors(sponsors);
    } on Object {
      // See above.
    }
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
    // A phone held in portrait, where the HUD and the world are competing for
    // the same pixels. Measured on width alone because that is what decides
    // whether there is a middle of the screen left between the two columns.
    //
    // On a laptop every chip stays on screen: there is room for two columns
    // and a world between them. On a phone there is not, so the HUD keeps
    // only what a thumb uses *while walking* — the minimap, the emotes, the
    // joystick and the door to the other world — and everything else moves
    // into [WorldMenuDrawer], one tap away behind the menu button.
    final isPhone = MediaQuery.sizeOf(context).width < phoneWidth;
    // The other world, or `null` when there is nowhere else to go.
    final otherMap = widget.onSwitchMap != null && _otherMap != widget.mapId
        ? _otherMap
        : null;

    final chips = <Widget>[
      if (!isPhone)
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
      // On screen on a phone as well as in the drawer. Walking into the other
      // world is the one menu item that is also a thing people do mid-step,
      // and a duplicated door costs one chip.
      if (otherMap != null)
        HudChip(
          onTap: () => widget.onSwitchMap!.call(otherMap),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_outlined, size: 16),
              const SizedBox(width: 6),
              Text('Go to ${otherMap.label}'),
            ],
          ),
        ),
      // On screen everywhere, and in the drawer as well. Passing the link on
      // is how the room fills up: the person you want in here is standing
      // next to you, and a control they have to go looking for is a control
      // that gets used once, by the maker, in a demo.
      HudChip(
        onTap: () => unawaited(
          shareApp(context, worldName: widget.appConfig.worldName),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ios_share, size: 16),
            SizedBox(width: 6),
            Text('Share'),
          ],
        ),
      ),
      if (!isPhone && widget.onEditIdentity != null)
        HudChip(
          onTap: widget.onEditIdentity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.face_retouching_natural, size: 16),
              const SizedBox(width: 6),
              Text(widget.identity.name),
            ],
          ),
        ),
      if (!isPhone && widget.onLogout != null)
        HudChip(
          onTap: () => unawaited(_confirmLogout()),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, size: 16, color: AppTheme.bad),
              SizedBox(width: 6),
              Text('Log out'),
            ],
          ),
        ),
    ];

    return ChangeNotifierProvider<ConnectionSupervisor>.value(
      value: _supervisor,
      child: Scaffold(
        drawer: isPhone
            ? WorldMenuDrawer(
                playerName: widget.identity.name,
                online: _hud.online,
                githubLink: widget.appConfig.githubLink,
                joystickSide: _joystickSide,
                onToggleJoystick: () => unawaited(_toggleJoystickSide()),
                onShare: () => unawaited(
                  shareApp(context, worldName: widget.appConfig.worldName),
                ),
                otherMap: otherMap,
                onSwitchMap: widget.onSwitchMap,
                onEditIdentity: widget.onEditIdentity,
                onLogout: () => unawaited(_confirmLogout()),
                boothsFailed: _boothsFailed,
              )
            : null,
        // The joystick owns a bottom corner, and on the left half the time. An
        // edge swipe that drags a drawer out from under a moving thumb is the
        // worst possible way to lose a walk, so the button is the only way in.
        drawerEnableOpenDragGesture: false,
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
                          if (isPhone)
                            const _MenuButton()
                          else ...[
                            const ConnectionChip(),
                            const SizedBox(height: 8),
                            OnlineBadge(online: _hud.online),
                            const SizedBox(height: 8),
                            CreditBadge(
                              githubLink: widget.appConfig.githubLink,
                            ),
                            if (_boothsFailed) ...[
                              const SizedBox(height: 8),
                              const _BoothWarning(),
                            ],
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
                          HallAwareMinimap(
                            frames: _hud.minimap,
                            spec: MapSpec.of(widget.mapId),
                            width: isPhone
                                ? Minimap.phoneWidth
                                : Minimap.deskWidth,
                          ),
                          for (final chip in chips) ...[
                            const SizedBox(height: hudGap),
                            chip,
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

/// The phone's way into [WorldMenuDrawer].
///
/// Carries the connection phase as well as the hamburger, because the drawer
/// it opens is now where "Reconnecting…" lives — and a socket that has dropped
/// is the one piece of HUD state a player must not have to go looking for.
/// Silent while the socket is healthy, which is almost always.
class _MenuButton extends StatelessWidget {
  const _MenuButton();

  @override
  Widget build(BuildContext context) {
    final phase = context.watch<ConnectionSupervisor>().phase;
    final healthy = phase == ConnectionPhase.connected;

    return Builder(
      builder: (context) => HudChip(
        onTap: Scaffold.of(context).openDrawer,
        child: Semantics(
          button: true,
          label: 'Menu. ${ConnectionChip.labelFor(phase)}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu, size: 18),
              if (!healthy) ...[
                const SizedBox(width: 6),
                Icon(
                  ConnectionChip.iconFor(phase),
                  size: 16,
                  color: ConnectionChip.colorFor(phase),
                ),
              ],
            ],
          ),
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
