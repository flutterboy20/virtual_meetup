import 'dart:async';

import 'package:client/core/app_route.dart';
import 'package:client/core/player_identity.dart';
import 'package:client/core/server_endpoint.dart';
import 'package:client/core/theme.dart';
import 'package:client/features/admin/view/admin_screen.dart';
import 'package:client/features/admin/view_model/admin_view_model.dart';
import 'package:client/features/app_config/view_model/app_config_view_model.dart';
import 'package:client/features/full/view/full_screen.dart';
import 'package:client/features/maintenance/view/maintenance_screen.dart';
import 'package:client/features/setup/view/setup_screen.dart';
import 'package:client/features/welcome/view/welcome_screen.dart';
import 'package:client/features/welcome/view_model/welcome_view_model.dart';
import 'package:client/features/world/view/world_screen.dart';
import 'package:client/game/joystick_side.dart';
import 'package:client/services/app_config_repository.dart';
import 'package:client/services/identity_store.dart';
import 'package:client/services/network_client.dart';
import 'package:client/services/server_status_service.dart';
import 'package:client/services/sponsor_repository.dart';
import 'package:flutter/material.dart';
import 'package:protocol/protocol.dart';
import 'package:provider/provider.dart';

/// The root widget of the client.
class VirtualConferenceApp extends StatelessWidget {
  /// Creates the root widget.
  ///
  /// Every collaborator is injectable so a widget test can run the whole app
  /// against a fake store, a fake status service and a fake socket — no
  /// platform channels, no server.
  const VirtualConferenceApp({
    required this.store,
    super.key,
    this.statusService,
    this.network,
    this.sponsors = const AssetSponsorRepository(),
    AppConfigRepository? appConfig,
    this.route = AppRoute.world,
    this.adminNetwork,
  }) : appConfig = appConfig ?? const _LiveConfig();

  /// Where identity and settings are persisted.
  final IdentityStore store;

  /// Where the online count comes from. A real HTTP one when omitted.
  final ServerStatusService? statusService;

  /// The connection to the relay. A real one when omitted.
  final NetworkClient? network;

  /// Where the booth list comes from. The bundled config when omitted.
  final SponsorRepository sponsors;

  /// Where the app's editable copy comes from.
  ///
  /// The relay's `/config` endpoint when omitted. A test passes a fake and
  /// gets no network at all — which is the whole reason this is a parameter
  /// and not a constructor call further down.
  final AppConfigRepository appConfig;

  /// Which face of the app this tab is, decided once from the URL.
  ///
  /// A parameter rather than a read of `Uri.base` in here, so a widget test
  /// can open either one without a browser.
  final AppRoute route;

  /// The admin socket. A real one pointed at `/admin` when omitted.
  final NetworkClient? adminNetwork;

  @override
  Widget build(BuildContext context) {
    // Above the `MaterialApp`, not inside one screen: config is app-wide by
    // definition, and the next value somebody wants to edit without a rebuild
    // should find the provider already in place.
    return ChangeNotifierProvider<AppConfigViewModel>(
      create: (_) {
        final model = AppConfigViewModel(repository: appConfig);
        // Not awaited: every screen renders the built-in copy immediately and
        // swaps to the fetched copy if and when it arrives.
        unawaited(model.load());
        return model;
      },
      child: _App(
        store: store,
        statusService: statusService,
        network: network,
        sponsors: sponsors,
        route: route,
        adminNetwork: adminNetwork,
      ),
    );
  }
}

/// The default repository: the relay's endpoint, built lazily.
///
/// A tiny indirection so [VirtualConferenceApp]'s constructor can stay
/// `const`-friendly for its callers while still defaulting to something that
/// opens an HTTP client — which a default value in a parameter list cannot do.
class _LiveConfig implements AppConfigRepository {
  const _LiveConfig();

  @override
  Future<AppConfig> load() => HttpAppConfigRepository().load();
}

/// The `MaterialApp` and the one routing decision in the app.
///
/// Split out from [VirtualConferenceApp] only so the config provider above it
/// has a child to wrap.
class _App extends StatelessWidget {
  const _App({
    required this.store,
    required this.statusService,
    required this.network,
    required this.sponsors,
    required this.route,
    required this.adminNetwork,
  });

  final IdentityStore store;
  final ServerStatusService? statusService;
  final NetworkClient? network;
  final SponsorRepository sponsors;
  final AppRoute route;
  final NetworkClient? adminNetwork;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Virtual Meetup',
      theme: AppTheme.dark,
      // Two entirely separate faces, chosen once. Not a `Navigator` route:
      // there is no link, no button and no back stack between the world and
      // the moderation screen, and there must not be one — a moderation tool
      // an attendee can stumble into is a moderation tool that gets probed.
      home: switch (route) {
        AppRoute.world => AppFlow(
          store: store,
          statusService: statusService,
          network: network,
          sponsors: sponsors,
        ),
        AppRoute.admin => ChangeNotifierProvider<AdminViewModel>(
          create: (_) => AdminViewModel(
            network:
                adminNetwork ?? NetworkClient(url: resolveAdminSocketUri()),
          ),
          child: const AdminScreen(),
        ),
      },
    );
  }
}

/// Which screen the player is on.
enum AppStage {
  /// Reading the device's saved identity. Milliseconds, usually.
  loading,

  /// The front door.
  welcome,

  /// Choosing a name and a bean.
  setup,

  /// In the world.
  world,

  /// Removed by a moderator. A dead end, on purpose.
  removed,

  /// Kicked by a moderator, and waiting out the cooling-off period.
  ///
  /// Its own stage rather than a flavour of [removed] because the two need
  /// opposite things from the screen: a ban has no way forward and a kick is
  /// nothing but a way forward, delayed.
  kicked,

  /// The event is closed for maintenance.
  ///
  /// The one stage that is not about this player at all, which is why it can
  /// be entered without anybody having done anything: the config alone puts
  /// everybody here at once. It is *also* a stage, rather than only a read of
  /// the config, because a client refused at the door has been told something
  /// its config may not know yet.
  maintenance,

  /// Every seat in the world is taken.
  ///
  /// The second stage that is not about this player, and the one difference
  /// from [maintenance] is what the client can *know*. Maintenance is in the
  /// config, so a client can enter that stage on its own; nothing in the
  /// config says how full the world is, so this stage can only ever be
  /// entered by being refused at the door. That is why there is no guard for
  /// it above the switch the way there is for maintenance.
  full,
}

/// The app's one piece of routing.
///
/// An explicit stage rather than a `Navigator` stack, because the rules here
/// are about *state*, not history: a returning player skips setup, and a
/// dropped socket must never pop anybody anywhere. A back stack would give
/// the browser's back button the power to yank somebody out of the world
/// mid-conversation, which is exactly the bounce this phase is meant to stop.
class AppFlow extends StatefulWidget {
  /// Creates the flow.
  const AppFlow({
    required this.store,
    super.key,
    this.statusService,
    this.network,
    this.sponsors = const AssetSponsorRepository(),
  });

  /// Where identity and settings are persisted.
  final IdentityStore store;

  /// Where the online count comes from.
  final ServerStatusService? statusService;

  /// The connection to the relay.
  final NetworkClient? network;

  /// Where the booth list comes from.
  final SponsorRepository sponsors;

  @override
  State<AppFlow> createState() => _AppFlowState();
}

class _AppFlowState extends State<AppFlow> {
  late final ServerStatusService _statusService =
      widget.statusService ?? HttpServerStatusService();

  AppStage _stage = AppStage.loading;
  String? _sessionId;
  PlayerIdentity? _identity;
  JoystickSide _joystickSide = JoystickSide.right;
  MapId _mapId = MapId.conference;
  String? _rejectionMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  /// Reads what the device already knows before showing anything.
  ///
  /// This is what makes a refresh mid-session invisible: the session id and
  /// the identity are both on the device, so the app can be back in the world
  /// before the player has finished noticing the page reloaded.
  Future<void> _bootstrap() async {
    final sessionId = await widget.store.sessionId();
    final identity = await widget.store.readIdentity();
    final side = await widget.store.readJoystickSide();
    final map = await widget.store.readMapId();
    if (!mounted) return;

    setState(() {
      _sessionId = sessionId;
      _identity = identity;
      _joystickSide = side;
      _mapId = map;
      _stage = AppStage.welcome;
    });
  }

  /// Moves the player to another map, from inside the world.
  ///
  /// Nothing here tears anything down by hand. The world screen is keyed on
  /// the map, so changing this field rebuilds it from scratch: a new socket
  /// with the new `?map=`, a new supervisor, a new Flame game with a new
  /// `GameMap`. Every timer, component and subscription the old one owned
  /// goes through its own `dispose`, which is the path that already works.
  ///
  /// The **session id survives**, because it lives on the device and not in
  /// the screen. That is what makes a kick or a ban follow somebody across a
  /// switch rather than being escaped by one.
  Future<void> _switchMap(MapId map) async {
    if (map == _mapId) return;
    setState(() => _mapId = map);
    await widget.store.writeMapId(map);
  }

  /// Re-reads the map the welcome screen may have changed while it was open.
  Future<void> _syncMap() async {
    final map = await widget.store.readMapId();
    if (!mounted || map == _mapId) return;
    setState(() => _mapId = map);
  }

  void _join() {
    // The picker writes straight to the store, so this is where that choice
    // is read back. Doing it here rather than plumbing a callback through the
    // welcome screen keeps one source of truth for "which map am I in".
    unawaited(_syncMap());
    setState(() {
      _rejectionMessage = null;
      _stage = _identity == null ? AppStage.setup : AppStage.world;
    });
  }

  void _editIdentity() => setState(() => _stage = AppStage.setup);

  /// Forgets this device entirely and goes back to the front door.
  ///
  /// [IdentityStore.clear], not [IdentityStore.clearIdentity]: this is the
  /// "not me any more" button — the phone handed to a colleague at a booth —
  /// so the session id goes too. Keeping it would seat the next person in the
  /// previous one's place, which is exactly the thing an edit is careful to
  /// preserve and a log out has to destroy.
  ///
  /// It goes back through [_bootstrap] rather than setting the stage by hand
  /// so the fresh session id is minted by the same path a brand-new device
  /// takes. One place decides what a first visit looks like; a second one
  /// would drift.
  Future<void> _logout() async {
    setState(() {
      _stage = AppStage.loading;
      _sessionId = null;
      _identity = null;
      _rejectionMessage = null;
    });
    await widget.store.clear();
    await _bootstrap();
  }

  void _onSetupDone(PlayerIdentity identity) {
    setState(() {
      _identity = identity;
      _rejectionMessage = null;
      _stage = AppStage.world;
    });
  }

  /// The server said no.
  ///
  /// The only path out of the world that is not the player's choice, and it
  /// is here rather than in the world screen because this is where the two
  /// answers to "what now" live.
  ///
  /// A bad name or a bad session goes back to setup with the server's own
  /// words, because those are things a person can fix. A ban does not: there
  /// is nothing to retype, and a form that silently refuses every attempt is
  /// a worse experience than being told plainly.
  ///
  /// A kick is the third answer, and it is the reason the client has to be
  /// told about kicks at all: the supervisor would otherwise treat the closed
  /// socket as a blip and walk straight back into the world. Landing here
  /// stops that, and hands the decision to come back to the person — which
  /// is the whole difference between a kick and a bean blinking.
  void _onRejected(JoinRejectedMessage rejection) {
    // A kick sends them back through setup as a first-timer: name, colour and
    // bean, all chosen again. The name is the point — a kick in a world with
    // no chat is almost always about one — and the server will refuse the old
    // one anyway, so a form that arrives pre-filled with it is a form that
    // exists to be rejected.
    //
    // The session id deliberately survives (`clearIdentity`, not `clear`):
    // the cooldown, the name block and any ban are all keyed on it, and
    // handing out a fresh one here would make being kicked the fastest way
    // out of all three.
    if (rejection.reason == JoinRejection.kicked) {
      unawaited(widget.store.clearIdentity());
    }

    // The socket died before it could carry a config, so the copy this app is
    // holding may predate the closure entirely. Re-reading it over HTTP is
    // what lets the screen name the moment the doors reopen instead of just
    // saying "closed". Not awaited: the screen renders without it and fills
    // the time in when the answer lands.
    if (rejection.reason == JoinRejection.maintenance) {
      unawaited(context.read<AppConfigViewModel>().load());
    }

    setState(() {
      _rejectionMessage = rejection.detail;
      if (rejection.reason == JoinRejection.kicked) _identity = null;
      _stage = switch (rejection.reason) {
        JoinRejection.banned => AppStage.removed,
        JoinRejection.kicked => AppStage.kicked,
        JoinRejection.maintenance => AppStage.maintenance,
        JoinRejection.worldFull => AppStage.full,
        JoinRejection.invalidName ||
        JoinRejection.invalidSession => AppStage.setup,
      };
    });
  }

  /// Re-reads the config and, if the event has reopened, lets the player back.
  ///
  /// The server is asked, every time. The client knowing that a countdown hit
  /// zero is not the same fact as the event being open, and the gap between
  /// the two is exactly the overrun that maintenance windows always have.
  Future<void> _leaveMaintenance() async {
    await context.read<AppConfigViewModel>().load();
    if (!mounted) return;
    if (context.read<AppConfigViewModel>().config.isUnderMaintenanceAt(
      DateTime.now(),
    )) {
      // Still closed. The screen stays, with whatever new time came back.
      return;
    }
    setState(() {
      _rejectionMessage = null;
      // Back to the front door rather than straight into the world: the
      // server has just come back up, and a room full of clients that all
      // reconnect the instant a countdown ends is the thundering herd the
      // window was there to avoid.
      if (_stage == AppStage.maintenance) _stage = AppStage.welcome;
    });
  }

  /// Tries the door again after being told the world was full.
  ///
  /// **Asks the server by trying to join**, rather than by reading a number.
  /// There is no number to read: `/metrics` says how many people are online
  /// and nothing tells the client what the cap is, so a client that tried to
  /// work out whether there was room would be guessing at a limit it cannot
  /// see. The join either succeeds or comes back as another `worldFull`,
  /// which lands on [_onRejected] and puts this screen straight back up. The
  /// server stays the only thing that decides.
  ///
  /// Straight into the world rather than back to the front door, which is the
  /// opposite of what [_leaveMaintenance] does — and deliberately. A
  /// maintenance window ends for everybody at one moment, so sending the room
  /// to the lobby is what spreads out the reconnect. A seat freeing is one
  /// person leaving, there is exactly one seat to take, and whoever asks
  /// first should get it rather than being sent to a screen to press another
  /// button.
  Future<void> _rejoinFromFull() async {
    if (!mounted || _stage != AppStage.full) return;
    setState(() {
      _rejectionMessage = null;
      _stage = _identity == null ? AppStage.setup : AppStage.world;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = _sessionId;
    if (_stage == AppStage.loading || sessionId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Above every other stage, and read from the config rather than from
    // `_stage`. A moderator closing the event has to take everybody out of
    // wherever they are — mid-walk, mid-setup, sitting on the front door —
    // and a rule that only applied to people who happened to try to join
    // would leave everybody who was already inside standing in an empty
    // world. Rebuilding without the world screen is also what disposes its
    // socket, so this is the client half of being disconnected.
    final config = context.watch<AppConfigViewModel>().config;
    if (config.isUnderMaintenanceAt(DateTime.now()) ||
        _stage == AppStage.maintenance) {
      return MaintenanceScreen(
        until: config.maintenanceUntil,
        onRetry: _leaveMaintenance,
      );
    }

    return switch (_stage) {
      AppStage.loading => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AppStage.welcome => ChangeNotifierProvider<WelcomeViewModel>(
        // Rebuilt per visit so a name changed in setup shows up on the
        // button when the player comes back to this screen.
        key: ValueKey(_identity),
        create: (_) {
          final model = WelcomeViewModel(
            status: _statusService,
            store: widget.store,
          );
          // Not awaited: the screen renders its loading state immediately
          // and this fills it in when the server answers.
          unawaited(model.load());
          return model;
        },
        child: WelcomeScreen(onJoin: _join, onEditIdentity: _editIdentity),
      ),
      // Handled above, before the config is even consulted for anything
      // else. Present here because the switch is exhaustive and a stage with
      // no arm would be a compile error the day somebody removes the guard.
      AppStage.maintenance => MaintenanceScreen(
        until: config.maintenanceUntil,
        onRetry: _leaveMaintenance,
      ),
      AppStage.full => FullScreen(
        message: _rejectionMessage,
        onRetry: _rejoinFromFull,
      ),
      AppStage.removed => _RemovedScreen(
        message:
            _rejectionMessage ??
            'A moderator removed you from this '
                'event.',
      ),
      AppStage.kicked => _RemovedScreen(
        message:
            _rejectionMessage ?? 'A moderator removed you from this event.',
        footer:
            'You will be asked to set up again, with a name you would be '
            'happy to wear on a badge.',
        onRetry: _join,
      ),
      AppStage.setup => _SetupStage(
        store: widget.store,
        sessionId: sessionId,
        identity: _identity,
        message: _rejectionMessage,
        onDone: _onSetupDone,
      ),
      AppStage.world => WorldScreen(
        // Keyed on the identity **and the map**, so either one changing
        // rebuilds the screen — which rebuilds the socket, the supervisor and
        // the game. A changed name rejoins under the new name; a changed map
        // reconnects with the new `?map=` and builds the other world.
        key: ValueKey((_identity, _mapId)),
        identity: _identity!,
        mapId: _mapId,
        // Read here rather than watched inside the screen: the projector's
        // line has to be known before the furniture is recorded, and a config
        // that arrived a frame later would have nowhere to land. Whatever has
        // been fetched by the time somebody walks in is what gets painted.
        appConfig: context.watch<AppConfigViewModel>().config,
        // The socket is the live path: the repository answered once before
        // anybody was in the world, and from here on the server pushes.
        onConfig: context.read<AppConfigViewModel>().update,
        store: widget.store,
        network: widget.network,
        sponsors: widget.sponsors,
        joystickSide: _joystickSide,
        onEditIdentity: _editIdentity,
        onLogout: () => unawaited(_logout()),
        onSwitchMap: (map) => unawaited(_switchMap(map)),
        onRejected: _onRejected,
      ),
    };
  }
}

/// The setup screen plus, when there is one, the server's reason for sending
/// the player back to it.
class _SetupStage extends StatelessWidget {
  const _SetupStage({
    required this.store,
    required this.sessionId,
    required this.identity,
    required this.message,
    required this.onDone,
  });

  final IdentityStore store;
  final String sessionId;
  final PlayerIdentity? identity;
  final String? message;
  final ValueChanged<PlayerIdentity> onDone;

  @override
  Widget build(BuildContext context) {
    final screen = SetupScreen(
      store: store,
      sessionId: sessionId,
      identity: identity,
      onDone: onDone,
    );
    final reason = message;
    if (reason == null) return screen;

    return Stack(
      children: [
        screen,
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Material(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppTheme.warn,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      reason,
                      style: const TextStyle(color: AppTheme.ink, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// What somebody a moderator removed sees.
///
/// A ban gets no button. Every other failure in this app offers a way forward
/// because every other failure has one; a ban does not, and a "Try again"
/// there would be a lie that turns one refusal into a hundred.
///
/// A kick passes [onRetry], because for a kick the button is the truth: the
/// server will let them back in once the cooling-off period is over, and the
/// only thing that must not happen is the *client* deciding when that is.
class _RemovedScreen extends StatelessWidget {
  const _RemovedScreen({
    required this.message,
    this.footer = 'Please speak to a member of the event team.',
    this.onRetry,
  });

  final String message;

  /// The quieter line under [message]: what happens next, or who to ask.
  final String footer;

  /// What to do when the player asks to come back, or `null` if they cannot.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block, size: 40, color: AppTheme.bad),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.ink, fontSize: 15),
              ),
              const SizedBox(height: 12),
              Text(
                footer,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.mutedInk, fontSize: 13),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
