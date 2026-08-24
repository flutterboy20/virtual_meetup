import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/sponsor.dart';
import 'package:client/game/ambience.dart';
import 'package:client/game/bean_animation.dart';
import 'package:client/game/bean_appearance.dart';
import 'package:client/game/bean_component.dart';
import 'package:client/game/bot_component.dart';
import 'package:client/game/camera_bounds.dart';
import 'package:client/game/collision.dart';
import 'package:client/game/crowd_glow_component.dart';
import 'package:client/game/disco_component.dart';
import 'package:client/game/emote_layer.dart';
import 'package:client/game/floor_component.dart';
import 'package:client/game/frame_profile.dart';
import 'package:client/game/furniture_component.dart';
import 'package:client/game/hint_bean_component.dart';
import 'package:client/game/joystick_art.dart';
import 'package:client/game/joystick_side.dart';
import 'package:client/game/movement.dart';
import 'package:client/game/nametag_layer.dart';
import 'package:client/game/position_throttle.dart';
import 'package:client/game/remote_players.dart';
import 'package:client/game/self_marker_component.dart';
import 'package:client/game/stage_screen_component.dart';
import 'package:client/game/tap_target.dart';
import 'package:client/game/tap_unlock.dart';
import 'package:client/game/water_component.dart';
import 'package:client/game/water_watcher.dart';
import 'package:client/game/world_hud.dart';
import 'package:client/game/world_layout.dart';
import 'package:client/services/network_client.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show KeyEventResult;
import 'package:protocol/protocol.dart';

/// The walk-around world.
///
/// The local bean owns its own position — that is the project's core
/// architecture decision (the server is a relay, not a simulator), so nothing
/// here waits on a round trip before moving. Position goes *up* to the server
/// on a throttle, and everybody else's positions come *down* and are applied
/// to [remotePlayers].
///
/// Since Phase 5 the flat test zone is the real cross-shaped venue: five
/// zones, static collision against the furniture, proximity nametags and
/// booth panels, emotes, and a sampled feed to the HUD. All of it is drawn
/// from vector shapes in code rather than from images, which is what keeps
/// the cold load on conference wifi to the size of the app itself.
///
/// With no [network] the game is a perfectly good single-player world, which
/// is also how the widget tests run it.
class ConferenceGame extends FlameGame with KeyboardEvents, TapCallbacks {
  /// Creates the game with the given bean look and joystick placement.
  ConferenceGame({
    this.appearance = const BeanAppearance(),
    this.playerName = '',
    this.network,
    this.spawnAngle,
    AppConfig config = AppConfig.defaults,
    GameMap? map,
    List<Sponsor> sponsors = const [],
    WorldHud? hud,
    JoystickSide joystickSide = JoystickSide.right,
    bool hasBoard = false,
    this.onBoardChanged,
    this.onConfig,
  }) : layout = map ?? WorldLayout.of(sponsors),
       hud = hud ?? WorldHud(),
       // A named parameter cannot be private, so this cannot be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _config = config,
       _unlock = TapUnlock(armed: hasBoard) {
    _joystickSide = joystickSide;
    collision = WorldCollision(layout);
  }

  /// Size of this world's bounding box, in world units.
  ///
  /// Taken from the map's `MapSpec`, which comes from `protocol/`: the server
  /// clamps inbound positions to the same bounds, and two ideas of how big
  /// the world is would put remote beans through walls.
  Vector2 get worldSize => Vector2(layout.spec.width, layout.spec.height);

  /// Fixed camera zoom. Never changes: pinch-zoom would let a player see far
  /// more of the world than the interest grid will send them.
  static const double cameraZoom = 1.6;

  /// Top speed of the bean, in world units per second.
  static const double beanMaxSpeed = 140;

  /// How fast the bean's velocity eases towards the stick's direction.
  static const double moveResponsiveness = 14;

  /// Camera catch-up speed; above [beanMaxSpeed] so it never falls behind.
  static const double cameraFollowSpeed = 260;

  /// How often the minimap is handed a fresh sample, in seconds.
  ///
  /// Six times a second, against a game loop running at sixty. A minimap is
  /// a hundred pixels across; a dot on it moves less than one pixel per game
  /// frame, so streaming every frame would rebuild a widget sixty times a
  /// second to redraw an identical picture.
  static const double minimapSampleInterval = 1 / 6;

  /// The shortest gap between two emotes from this client, in seconds.
  ///
  /// Advice, not a rule. The rule is the server's token bucket, because
  /// anything enforced here is enforced by code the player controls. This
  /// exists so an honest client does not spend its own allowance on presses
  /// nobody meant to make.
  static const double emoteMinimumGap = 0.3;

  /// Called when the server pushes a new config.
  ///
  /// The game applies it to itself first and *then* tells the widget layer,
  /// which is the order that matters: everything above this line — the
  /// welcome screen's wordmark, anything else reading the provider — is copy,
  /// and copy can wait a frame. The world cannot.
  final void Function(AppConfig config)? onConfig;

  /// The player's bean. Available once [onLoad] has run.
  late final BeanComponent bean;

  /// The recorded furniture, kept so a config edit can re-record it.
  late final FurnitureComponent furniture;

  /// The hall's screen, or `null` on a map with no stage.
  StageScreenComponent? stageScreen;

  /// The virtual joystick. Available once [onLoad] has run.
  late final JoystickComponent joystick;

  /// How the player's bean looks.
  final BeanAppearance appearance;

  /// The name to float over the player's own bean, always.
  ///
  /// Empty in a test that does not care, which is the whole of "draw no tag
  /// over me" — see `NametagLayer.localTag`.
  final String playerName;

  /// The connection to the relay server, or `null` to play offline.
  ///
  /// The game reads from it and reports its position to it, but it does not
  /// *join* on it. Who this client is, and re-announcing that after a drop,
  /// belongs to the connection supervisor — the game layer must not be the
  /// second thing sending joins, or a reconnect sends two.
  final NetworkClient? network;

  /// Called whenever the local player picks the board up or puts it down.
  ///
  /// The game does not touch `shared_preferences` itself, for the same reason
  /// it does not open its own socket: persistence belongs to the screen that
  /// owns the store, and a game layer that wrote to disk would be a second
  /// thing writing the same keys.
  final void Function({required bool hasBoard})? onBoardChanged;

  /// Where on the spawn ring this client starts, in radians, or `null` for a
  /// random spot.
  ///
  /// Random by default so a hundred people arriving at once do not stack into
  /// one bean-shaped pile; injectable so a test can say exactly where the
  /// bean is.
  final double? spawnAngle;

  /// The world this game is running: its geometry, its art, its furniture.
  ///
  /// A value since Phase 10 rather than a wall of statics. Everything below
  /// that used to reach for `WorldLayout.something` now asks this, which is
  /// what lets one `ConferenceGame` run either map.
  final GameMap layout;

  /// What the bean can and cannot walk through.
  late final WorldCollision collision;

  /// The narrow, throttled channel to the Flutter HUD.
  ///
  /// Not disposed here: whoever created it owns it, because the widget that
  /// listens to it and the game that writes to it are torn down in an order
  /// neither of them controls.
  final WorldHud hud;

  /// Everybody else's beans. Available once [onLoad] has run.
  late final RemotePlayers remotePlayers;

  /// The floating reactions. Available once [onLoad] has run.
  late final EmoteLayer emotes;

  /// The map's gather-here glow. Available once [onLoad] has run.
  late final CrowdGlowComponent crowdGlow;

  /// The swimmable water. Available once [onLoad] has run.
  late final WaterComponent water;

  /// The beans standing around this map who are not people.
  ///
  /// Client-side scenery, built from the map's own constants — see
  /// `GameMap.bots`. They are exposed because the tests assert on where they
  /// stand and on what they are and are not counted in; nothing else in the
  /// app reaches for them.
  final List<BotComponent> bots = [];

  /// Every bot this map *could* show, mounted or not.
  ///
  /// Built once, in roster order. A moderator turning the crowd down does not
  /// destroy anything — it unmounts the tail of this list, and turning it
  /// back up mounts the same beans in the same places. Rebuilding them would
  /// re-seed every brain, so the garden would visibly restart every time
  /// somebody nudged the dial.
  late final List<BotComponent> allBots;

  /// What this device's frame rate has actually been doing.
  ///
  /// Fed from the engine's own timings rather than from the game loop, so it
  /// measures build **and** raster — which is what a player feels and what
  /// `PerfHud` already reports. It exists here, outside the debug HUD,
  /// because the water reads it to decide how much detail it can afford: an
  /// LOD that only worked in a build with the profiler switched on would be
  /// an LOD that never ran on a phone at the event.
  final FrameProfile frameProfile = FrameProfile();

  /// The id the server gave this client, once it has been welcomed.
  String? get myId => _myId;

  /// What the local bean is called inside the pool's bookkeeping.
  ///
  /// A constant rather than the server-assigned id, so swimming works offline
  /// and across a reconnect. Prefixed so it can never collide with a real
  /// session id.
  static const String _localSwimmerId = 'local:me';

  static const double _joystickInset = 32;
  static const double _joystickBottomInset = 44;
  static const double _joystickKnobRadius = 24;
  static const double _joystickBackgroundRadius = 56;

  /// The idle fade both halves of the stick share.
  ///
  /// One object, two components: a base fading on a different schedule to its
  /// own knob is the sort of bug nobody notices until a screenshot.
  final JoystickFade joystickFade = JoystickFade();

  /// The event's editable copy and crowd size, as last heard.
  ///
  /// Starts as whatever was fetched before the game was built and is replaced
  /// by every `ConfigMessage` the server pushes. See [applyConfig].
  AppConfig get config => _config;

  AppConfig _config;

  // Not `const`: LogicalKeyboardKey overrides `==`, so it cannot be a
  // constant set element.
  static final Set<LogicalKeyboardKey> _leftKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.keyA,
  };
  static final Set<LogicalKeyboardKey> _rightKeys = {
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyD,
  };
  static final Set<LogicalKeyboardKey> _upKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.keyW,
  };
  static final Set<LogicalKeyboardKey> _downKeys = {
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.keyS,
  };

  /// The three-tap ritual, and whether the board is currently in hand.
  final TapUnlock _unlock;

  /// What the toast says at each step of the secret.
  ///
  /// Constants rather than inline strings so the wording is in one place and
  /// the tests can assert on the *hint* not naming the east end — that is the
  /// difference between a secret worth passing on and an instruction.
  static const String hintText =
      'Somebody left a surfboard on this beach. Nobody remembers where.';

  /// What the board says when it is picked up.
  static const String unlockedText = 'Board unlocked — head into the sea.';

  /// What the board says when it is put back.
  static const String stowedText = 'Board stowed.';

  final PositionThrottle _positionThrottle = PositionThrottle();
  final Vector2 _keyboardDirection = Vector2.zero();

  /// The smoothed input velocity, before the water slows it down.
  ///
  /// Separate from `bean.velocity` — which is what the bean is *actually*
  /// travelling at and what its animation is driven by — so that the input
  /// smoothing is not fed its own damped output. See [update].
  final Vector2 _steering = Vector2.zero();
  final Vector2 _previousPosition = Vector2.zero();
  StreamSubscription<ProtocolMessage>? _messages;
  String? _myId;
  late JoystickSide _joystickSide;
  late final JoystickBase _joystickBase;
  late final JoystickKnob _joystickKnob;
  double _minimapTimer = 0;
  double _sinceEmote = emoteMinimumGap;

  /// Whether the local player is carrying a board.
  bool get hasBoard => _unlock.isArmed;

  /// Which side of the screen the joystick sits on.
  JoystickSide get joystickSide => _joystickSide;

  set joystickSide(JoystickSide value) {
    if (value == _joystickSide) {
      return;
    }
    _joystickSide = value;
    if (isLoaded) {
      _applyJoystickSide();
    }
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    bean = BeanComponent(
      position: _spawnPosition(),
      appearance: appearance,
      animation: BeanAnimation(maxSpeed: beanMaxSpeed),
      map: layout,
    );
    remotePlayers = RemotePlayers(maxSpeed: beanMaxSpeed, map: layout);
    emotes = EmoteLayer();
    crowdGlow = CrowdGlowComponent(
      crowdAt: _crowdAt,
      spot: layout.crowdGlow,
    );
    water = WaterComponent(
      swimmers: _swimmers,
      map: layout,
      localSwimmerId: _localSwimmerId,
      // The camera, as a rectangle. This is what makes the sea's cost
      // O(screen) instead of O(sea) — see `WaterComponent`.
      visibleWorldRect: () => camera.visibleWorldRect,
      frameP95Millis: () => frameProfile.p95Millis,
      isLocalSubmerged: () => bean.swim.submersion > 0.5,
    );

    // Not awaited: `add` completes when the component mounts, which only
    // happens after `onLoad` returns — awaiting it here would deadlock.
    //
    // The order is the z-order: floor, then the crowd glow painted on it,
    // then water, then furniture, then beans, then the things that must never
    // be hidden behind a bean — reactions and names.
    // Whatever was persisted, applied through the setter so the map still
    // gets the last word on whether surfing happens here.
    bean.hasBoard = _unlock.isArmed;

    final hint = layout.hintBean;
    allBots = buildBots(
      specs: layout.bots,
      map: layout,
      isVisible: _isOnCamera,
      // Through the layer everybody else's reactions already go through, so a
      // bot's is drawn, capped and forgotten by the same code — and never
      // sent anywhere, because there is nobody to send it as.
      onEmote: (bot) => emotes.show(bot.brain.pickEmote(), bot),
    );
    bots.addAll(allBots.take(_wantedBotCount(_config)));

    unawaited(
      world.addAll([
        FloorComponent(worldSize: worldSize, map: layout),
        crowdGlow,
        water,
        furniture = FurnitureComponent(layout: layout),
        StringLightsComponent(runs: layout.lightRuns),
        // Only on a map that has a pub, which is the beach.
        if (layout.hasDisco) DiscoComponent(),
        // Only on a map with a stage to put it on, which is the conference.
        // An empty line list is the whole of "nothing here says anything".
        if (layout.hasStageScreen)
          stageScreen = StageScreenComponent(lines: layout.stageLines),
        // Only on a map that has one, which is the beach. `null` here is the
        // whole of "this map keeps no secrets".
        if (hint != null) HintBeanComponent(x: hint.x, y: hint.y),
        remotePlayers,
        ...bots,
        SelfMarkerComponent(bean: bean),
        bean,
        // Droplets go over the beans; the wakes they leave stay under them,
        // inside `water`. A splash you dive *through* and a ripple you swim
        // *on* cannot share one z-order.
        SplashLayer(field: water.field),
        emotes,
        NametagLayer(
          remotePlayers: remotePlayers,
          localPosition: () => bean.position,
          // Your own name, always on. Together with the ring under your feet
          // this is the answer to "which one of these is me" — the ring finds
          // you in the crowd, the name confirms it.
          localBean: bean,
          localName: playerName,
          // The bots get named by the same rules as everybody else: walk up
          // and a name appears, walk away and it goes.
          bots: bots,
        ),
      ]),
    );

    camera.viewfinder.zoom = cameraZoom;
    camera.follow(bean, maxSpeed: cameraFollowSpeed, snap: true);
    // Without bounds the camera would happily show the void past the floor.
    _applyCameraBounds();

    _joystickBase = JoystickBase(
      radius: _joystickBackgroundRadius,
      fade: joystickFade,
    );
    _joystickKnob = JoystickKnob(
      radius: _joystickKnobRadius,
      fade: joystickFade,
    );
    joystick = JoystickComponent(
      knob: _joystickKnob,
      background: _joystickBase,
      margin: _joystickSide.margin(
        inset: _joystickInset,
        bottomInset: _joystickBottomInset,
      ),
    );
    // Both live in the viewport, not the world: the joystick is a HUD control
    // and must not scroll away as the camera follows the bean, and a vignette
    // that scrolled would be a dark patch sliding around the map.
    unawaited(camera.viewport.addAll([VignetteComponent(), joystick]));

    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _startNetwork();
  }

  /// Takes a new config, live, without rebuilding the world.
  ///
  /// This is the whole point of pushing config down the socket rather than
  /// reading it at startup: a moderator fixes a typo on the projector and
  /// two hundred people see the fix, without one of them being teleported
  /// back to the spawn ring.
  ///
  /// Three things can change, and each is applied by the cheapest thing that
  /// can apply it:
  ///
  /// - The **projector's line** is inside the recorded furniture, so the
  ///   recording is made again — one `Picture`, once, on a human's keystroke.
  /// - The **stage programme** is a live component, so it is handed the new
  ///   script.
  /// - The **crowd size** mounts or unmounts the tail of [allBots]. Nothing
  ///   is created or destroyed, so the beans that stay do not so much as
  ///   break stride.
  ///
  /// A config equal to the one already in force does nothing at all, which
  /// matters because the server pushes on every join.
  void applyConfig(AppConfig config) {
    if (config == _config) return;
    _config = config;
    if (!isLoaded) return;

    layout.applyConfig(config);
    furniture.rebuild();
    stageScreen?.setLines(layout.stageLines);
    _setBotCount(_wantedBotCount(config));
  }

  /// How many bots [config] asks this map for, clamped to what exists.
  ///
  /// A map the config says nothing about shows its whole roster. Bots are a
  /// hand-placed list of positions, so there is no twenty-first bean to
  /// invent for somebody who types 21.
  int _wantedBotCount(AppConfig config) {
    final wanted = config.botCountFor(layout.spec.id) ?? layout.bots.length;
    return wanted.clamp(0, layout.bots.length);
  }

  /// Mounts or unmounts bots until exactly [wanted] are in the world.
  void _setBotCount(int wanted) {
    while (bots.length > wanted) {
      bots.removeLast().removeFromParent();
    }
    while (bots.length < wanted) {
      final bot = allBots[bots.length];
      bots.add(bot);
      // The result is deliberately dropped: `add` completes when the
      // component mounts, and nothing here needs to wait for that — the same
      // trade `onLoad` already makes.
      // ignore: discarded_futures
      world.add(bot);
    }
  }

  /// Feeds the engine's frame timings into [frameProfile].
  ///
  /// Cheap: a couple of integer adds per frame and one list append, on a
  /// callback the engine already fires. A profiler that shows up in its own
  /// numbers is not a profiler.
  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      frameProfile.record(
        buildMicros: timing.buildDuration.inMicroseconds,
        rasterMicros: timing.rasterDuration.inMicroseconds,
      );
    }
  }

  @override
  void onRemove() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    // The game can outlive a socket and vice versa; whoever created the
    // client owns closing it, but this subscription belongs to the game.
    unawaited(_messages?.cancel());
    network?.status.removeListener(_onStatusChanged);
    super.onRemove();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // How much world fits on screen changed, so where the camera may sit
    // changed with it. Rotating a phone without this leaves the old bounds.
    _applyCameraBounds();
  }

  /// Clamps the camera so it never shows the void past the floor.
  ///
  /// Deliberately not Flame's `considerViewport: true`: that subtracts the
  /// viewport in pixels from a world measured in world units, which at
  /// [cameraZoom] 1.6 over-shrinks the allowed area and leaves the local bean
  /// off-screen at the map edge while it still shows on the minimap.
  void _applyCameraBounds() {
    // Before the first layout there is no viewport to measure; the resize
    // that gives us one calls back in here.
    if (!hasLayout || size.x <= 0 || size.y <= 0) {
      return;
    }
    camera.setBounds(
      cameraBounds(
        viewportSize: size,
        worldSize: worldSize,
        zoom: cameraZoom,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isLoaded) {
      return;
    }

    final direction = clampToUnitDisk(_inputDirection());
    final steered = steerVelocity(
      velocity: _steering,
      target: direction * beanMaxSpeed,
      responsiveness: moveResponsiveness,
      dt: dt,
    );
    _steering.setFrom(steered);

    // Water slows the bean down. Applied to the *travelling* velocity and not
    // fed back into [_steering], because a smoother whose own output is
    // multiplied every frame converges on far less than the multiplier asks
    // for — 0.55 applied that way settles at about 0.20 of walking pace,
    // which is not swimming, it is wading through setting concrete.
    final travel = steered * localSpeedFactor;
    bean.velocity.setFrom(travel);

    _previousPosition.setFrom(bean.position);
    final wanted = _previousPosition + travel * dt;
    final resolved = collision.resolve(from: _previousPosition, to: wanted);

    // A bean pressed into a wall must stop *animating* as though it were
    // sprinting, or it moonwalks on the spot. The axis that was refused loses
    // its velocity; the one that slid keeps it. The steering state has to be
    // cleared with it, or the bean keeps accelerating into the wall and bursts
    // away from it the moment it turns.
    if (resolved.x == _previousPosition.x && wanted.x != _previousPosition.x) {
      bean.velocity.x = 0;
      _steering.x = 0;
    }
    if (resolved.y == _previousPosition.y && wanted.y != _previousPosition.y) {
      bean.velocity.y = 0;
      _steering.y = 0;
    }
    // Belt and braces: the collision escape hatch lets a bean out of a solid
    // it somehow started inside, and this makes sure "out" is still inside
    // the world the server will accept.
    bean.position.setValues(
      layout.spec.clampX(resolved.x),
      layout.spec.clampY(resolved.y),
    );

    _sinceEmote += dt;
    _updateJoystickChrome(dt);
    _unlock.update(dt);
    _reportPosition(dt);
    _updateNearbySponsor();
    _sampleMinimap(dt);
  }

  /// Tells the drawn stick whether a thumb is on it, and ages its fade.
  ///
  /// The stick itself is Flame's [JoystickComponent] and stays exactly that —
  /// this only decides how its two halves *look*. Reading `direction` rather
  /// than `delta` is deliberate: `delta` is non-zero for a dead-zone wobble
  /// the stick has already decided to ignore.
  void _updateJoystickChrome(double dt) {
    final active = joystick.direction != JoystickDirection.idle;
    joystickFade.update(dt, active: active);
    _joystickBase.isActive = active;
    _joystickKnob.isActive = active;
  }

  /// The speed multiplier the local bean is travelling at right now.
  ///
  /// Public because it is the one number that says whether this bean is
  /// surfing, swimming or walking, and a test that asserted on the distance
  /// covered instead would be measuring the input smoother.
  ///
  /// The one place surfing and swimming are chosen between, and it has to be
  /// here rather than inside the map: `GameMap.speedFactorAt` knows a
  /// *position*, not *which bean is asking*, and only the local bean's speed
  /// is ever computed at all — remote beans are interpolated from snapshots
  /// and derive nothing from a multiplier.
  double get localSpeedFactor {
    final surf = layout.surfSpeedFactor;
    if (surf != null &&
        _unlock.isArmed &&
        layout.isWater(bean.position.x, bean.position.y)) {
      return surf;
    }
    return layout.speedFactorAt(bean.position.x, bean.position.y);
  }

  /// Resolves a tap against this map's tap targets, in world space.
  ///
  /// The first tap handling in this project. Everything before it was the
  /// joystick, the keyboard, or a Flutter widget on top of the game.
  ///
  /// The conversion through the camera is what makes this correct at any
  /// screen size and any camera position: the event arrives in canvas pixels
  /// and the targets are rectangles in world units, and nothing else in this
  /// method knows about either.
  ///
  /// A tap that hits nothing does nothing. There is no drag, no long press
  /// and no double tap — one gesture, one meaning.
  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    final targets = layout.tapTargets;
    if (targets.isEmpty) return;

    final at = camera.globalToLocal(event.canvasPosition);
    for (final target in targets) {
      if (!target.contains(at.x, at.y)) continue;
      _handleTap(target.id);
      return;
    }
  }

  /// What one tap on [target] means.
  void _handleTap(TapTargetId target) {
    switch (target) {
      case TapTargetId.hint:
        // Deliberately does not say where. "There is a board hidden on this
        // beach" is a secret worth passing on to the person next to you; "the
        // board is at the east end" is an instruction, and nobody repeats an
        // instruction.
        hud.say(hintText);
      case TapTargetId.board:
        switch (_unlock.tap()) {
          case TapUnlockResult.counting:
            break;
          case TapUnlockResult.armed:
            _applyBoard(hasBoard: true, message: unlockedText);
          case TapUnlockResult.disarmed:
            _applyBoard(hasBoard: false, message: stowedText);
        }
    }
  }

  /// Applies a board change everywhere it has to land: the bean, the toast,
  /// the persistence hook and the wire.
  ///
  /// Exactly one message per change, never one per tap — the two taps that do
  /// not flip anything cost nothing at all.
  void _applyBoard({required bool hasBoard, required String message}) {
    bean.hasBoard = hasBoard;
    hud.say(message);
    onBoardChanged?.call(hasBoard: hasBoard);
    _sendBoard();
  }

  /// Tells the server what the local bean is carrying, if anybody is
  /// listening.
  void _sendBoard() {
    final client = network;
    if (client == null || !client.isConnected) return;
    client.send(BoardMessage(hasBoard: _unlock.isArmed));
  }

  /// Throws [kind] above the local bean and tells the neighbours.
  ///
  /// Drawn locally the instant it is called, without waiting for the server
  /// to hand it back: the client owns its own state, and a round trip between
  /// a tap and a reaction is the difference between a button that feels
  /// connected and one that feels broken. Returns whether it was sent.
  bool emote(EmoteKind kind) {
    if (_sinceEmote < emoteMinimumGap) return false;
    _sinceEmote = 0;
    emotes.show(kind, bean);
    final client = network;
    if (client != null && client.isConnected) {
      client.send(EmoteMessage(emote: kind));
    }
    return true;
  }

  /// Starts listening to the connection somebody else owns.
  ///
  /// Deliberately does not *open* it. Opening, re-opening and joining belong
  /// to the connection supervisor: two things calling `connect` on one client
  /// means the second one tears down the socket the first just made, which is
  /// a self-inflicted disconnect on every launch.
  void _startNetwork() {
    final client = network;
    if (client == null) {
      return;
    }
    _messages = client.messages.listen(_onMessage);
    client.status.addListener(_onStatusChanged);
  }

  /// Sends the local bean's position, at most ten times a second.
  ///
  /// Sending every frame would be 6× the traffic for movement no human can
  /// tell apart, and it is per *client*, so the cost lands on the server as
  /// n² fan-out. The throttle also stays quiet while the bean is parked.
  void _reportPosition(double dt) {
    final client = network;
    if (client == null || !client.isConnected) {
      return;
    }
    final toSend = _positionThrottle.sample(dt, bean.position);
    if (toSend != null) {
      client.send(MoveMessage(x: toSend.x, y: toSend.y));
    }
  }

  /// Opens and closes the booth panel as the bean walks up and away.
  ///
  /// Two radii, not one. With a single boundary a bean standing exactly on it
  /// flickers the panel on and off every frame — the idle bob alone is enough
  /// to cross it — which is the most irritating bug this feature can have.
  /// Entering is [Sponsor.approachRadius]; leaving is the wider
  /// [Sponsor.leaveRadius], so the panel has to be genuinely walked away from.
  void _updateNearbySponsor() {
    final current = hud.nearbySponsor.value;
    final radius = current == null
        ? Sponsor.approachRadius
        : Sponsor.leaveRadius;
    final nearest = layout.nearestSponsor(
      bean.position.x,
      bean.position.y,
      radius,
    );
    // Assigned only when it actually changed: a ValueNotifier written with
    // the same value still notifies, and this runs every frame.
    if (nearest != current) hud.nearbySponsor.value = nearest;
  }

  /// Hands the minimap a fresh sample a few times a second.
  void _sampleMinimap(double dt) {
    _minimapTimer += dt;
    if (_minimapTimer < minimapSampleInterval) return;
    _minimapTimer = 0;
    hud.minimap.value = MinimapFrame(
      you: Offset(bean.position.x, bean.position.y),
      others: [
        for (final view in remotePlayers.views)
          Offset(view.bean.position.x, view.bean.position.y),
      ],
    );
  }

  /// Whether ([x], [y]) is inside the camera, plus a bean's worth of margin.
  ///
  /// The whole of bot culling: a bot outside this rectangle skips its brain,
  /// its collision, its animation and its draw. Inflated by a bean height so
  /// one does not pop into existence mid-stride at the edge of the screen.
  ///
  /// Before the first layout there is no camera to ask, and the honest answer
  /// is "yes" — a bot that skipped its first frame would spawn one frame late.
  bool _isOnCamera(double x, double y) {
    if (!hasLayout) return true;
    return camera.visibleWorldRect
        .inflate(BeanComponent.bodyHeight)
        .contains(Offset(x, y));
  }

  /// Every bean on this screen, the local one included, as a position.
  ///
  /// This is the entire input to swimming. The pool is handed positions this
  /// client already has and derives dives, splashes and wakes from them, which
  /// is why the whole feature costs nothing on the wire and the server learns
  /// nothing. `_local` is a fixed id rather than [myId] so it still works
  /// offline, before a welcome has arrived.
  Iterable<SwimSample> _swimmers() sync* {
    yield (id: _localSwimmerId, x: bean.position.x, y: bean.position.y);
    // Bots are in here, and deliberately so. This iterable is a *rendering*
    // input — it is what makes the pool bot dive, splash and leave a wake —
    // and a splash is a picture, not a claim about attendance. Contrast
    // `_crowdAt`, which is a census, and which they stay out of.
    for (var i = 0; i < bots.length; i++) {
      final bot = bots[i];
      yield (id: 'bot:$i', x: bot.position.x, y: bot.position.y);
    }
    for (final view in remotePlayers.views) {
      yield (
        id: view.id,
        x: view.bean.position.x,
        y: view.bean.position.y,
      );
    }
  }

  /// How many **people** — the local one included — are within [radius] of a
  /// spot.
  ///
  /// Bots are excluded on purpose. A gather-here glow lit by scenery is a glow
  /// that is always on, which is a glow that says nothing; and the same rule
  /// keeps them out of the head count, which the server owns and which they
  /// could not reach even if we wanted them to.
  int _crowdAt(double x, double y, double radius) {
    final limit = radius * radius;
    var count = 0;
    if (_distanceSquared(bean.position.x, bean.position.y, x, y) <= limit) {
      count++;
    }
    for (final view in remotePlayers.views) {
      final position = view.bean.position;
      if (_distanceSquared(position.x, position.y, x, y) <= limit) count++;
    }
    return count;
  }

  /// Picks the spot on this map's spawn ring this client starts at.
  Vector2 _spawnPosition() {
    final angle = spawnAngle ?? math.Random().nextDouble() * 2 * math.pi;
    final spec = layout.spec;
    final at = Vector2(
      spec.spawnCenterX + math.cos(angle) * spec.spawnRingRadius,
      spec.spawnCenterY + math.sin(angle) * spec.spawnRingRadius,
    );
    // The ring is clear of the credit pillar by design, but a booth moved in
    // config could in principle land on it, and starting inside furniture is
    // a bad first second.
    return collision.nearestFreePoint(at.x, at.y);
  }

  void _onStatusChanged() {
    final client = network;
    if (client == null) return;
    switch (client.status.value) {
      case ConnectionStatus.connected:
        // The supervisor sends the join. All this has to do is make sure the
        // next position sample actually goes out rather than being swallowed
        // by a throttle that thinks nothing has changed since before the
        // socket died.
        _positionThrottle.reset();
      case ConnectionStatus.offline:
        // Nobody's position is being updated any more, so leaving their beans
        // standing there would be a lie. Our own bean keeps working.
        _myId = null;
        remotePlayers.clear();
        emotes.clear();
        // The pool forgets who was in it too: their beans are gone, so a
        // wake still trailing behind one is a ripple with nobody making it.
        water.watcher.clear();
        water.field.clear();
      case ConnectionStatus.idle:
      case ConnectionStatus.connecting:
        break;
    }
  }

  void _onMessage(ProtocolMessage message) {
    switch (message) {
      case WelcomeMessage():
        _myId = message.yourId;
        // First connect *and* every reconnect. The board is a fact about a
        // player and everybody around them was just told how this player
        // looks, so it has to be part of that. It is not folded into the
        // join, because the join belongs to the connection supervisor and
        // two layers in one path is how a reconnect ends up sending twice.
        if (_unlock.isArmed) _sendBoard();
      case WorldStatsMessage():
        // The one number interest management hides from a player, so the
        // server has to say it out loud. About once a second — slow enough to
        // be allowed across the boundary into a widget at all.
        hud.online.value = message.online;
      case PlayerEmotedMessage():
        // Nothing happens if they are not on screen: a reaction from somebody
        // this client has no bean for has nowhere to go.
        final source = remotePlayers.beanOf(message.id);
        if (source != null) emotes.show(message.emote, source);
      case ConfigMessage():
        // Once on join, and again every time a moderator edits it.
        applyConfig(message.config);
        onConfig?.call(message.config);
      case JoinMessage():
      case MoveMessage():
      case EmoteMessage():
      case BoardMessage():
      case PlayerBoardMessage():
      case SnapshotMessage():
      case PlayerLeftMessage():
      case JoinRejectedMessage():
      case UnknownMessage():
      case AdminAuthMessage():
      case AdminAuthResultMessage():
      case AdminPlayerListMessage():
      case AdminKickMessage():
      case AdminBanMessage():
      case AdminMuteNameMessage():
      case AdminActionResultMessage():
      case AdminErrorMessage():
      case AdminSetConfigMessage():
      case AdminSetMaintenanceMessage():
        // Admin traffic never reaches a player socket, so this is the
        // compiler holding the sealed hierarchy together rather than a case
        // that can happen.
        break;
    }
    remotePlayers.apply(message);
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    // Keyboard is a desktop convenience; touch players use the joystick.
    _keyboardDirection.setValues(
      _axis(keysPressed, negative: _leftKeys, positive: _rightKeys),
      _axis(keysPressed, negative: _upKeys, positive: _downKeys),
    );
    final isMovementKey =
        _leftKeys.contains(event.logicalKey) ||
        _rightKeys.contains(event.logicalKey) ||
        _upKeys.contains(event.logicalKey) ||
        _downKeys.contains(event.logicalKey);
    return isMovementKey ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  Vector2 _inputDirection() {
    // The stick wins while it is being held; otherwise fall back to keys.
    if (!joystick.delta.isZero()) {
      return joystick.relativeDelta;
    }
    return _keyboardDirection;
  }

  void _applyJoystickSide() {
    joystick.margin = _joystickSide.margin(
      inset: _joystickInset,
      bottomInset: _joystickBottomInset,
    );
    // `ComponentViewportMargin` only re-reads its margin on a resize and
    // exposes no public re-layout hook, so replay the current size.
    joystick.onGameResize(size);
  }

  static double _distanceSquared(double ax, double ay, double bx, double by) {
    final dx = ax - bx;
    final dy = ay - by;
    return dx * dx + dy * dy;
  }

  static double _axis(
    Set<LogicalKeyboardKey> pressed, {
    required Set<LogicalKeyboardKey> negative,
    required Set<LogicalKeyboardKey> positive,
  }) {
    double value = 0;
    if (pressed.any(negative.contains)) {
      value -= 1;
    }
    if (pressed.any(positive.contains)) {
      value += 1;
    }
    return value;
  }
}
