import 'dart:async';

import 'package:client/game/bean_animation.dart';
import 'package:client/game/bean_appearance.dart';
import 'package:client/game/bean_component.dart';
import 'package:client/game/interpolation_buffer.dart';
import 'package:client/game/world_layout.dart';
import 'package:flame/components.dart';
import 'package:protocol/protocol.dart';

/// Everybody else's beans.
///
/// Owns one [BeanComponent] per remote player and applies the server's
/// snapshots to them. This is the Flame side of the network boundary: remote
/// state changes ~15 times a second, so it lives in components and never in a
/// Provider — pushing it through the widget tree would rebuild the UI at that
/// rate and cost the frame budget for nothing.
///
/// Since Phase 3 nothing here snaps to a reported position. Each remote bean
/// keeps a short history of where it has been and is drawn
/// [interpolationDelay] seconds in the past, *between* two positions the
/// server actually sent. Fifteen samples a second become sixty frames of
/// smooth motion.
///
/// The local bean is not in here and is never interpolated. It is the one
/// bean whose position this client owns outright, and it has to answer the
/// player's thumb instantly.
class RemotePlayers extends Component {
  /// Creates the container. Add it to the game world.
  RemotePlayers({
    required this.maxSpeed,
    GameMap? map,
    this.delay = interpolationDelay,
  }) : map = map ?? ConferenceMap.empty;

  /// The world these beans are standing in.
  ///
  /// Handed down to every remote bean so it can ask whether it is in water.
  /// That question is answered locally, on every client, for every bean —
  /// which is why a remote player swims on this screen without the server
  /// ever mentioning water.
  final GameMap map;

  /// Ceiling on the velocity handed to a bean's animation.
  ///
  /// A player who teleports (or whose connection hiccups) would otherwise
  /// produce an absurd velocity and a bean flattened by squash for a moment.
  final double maxSpeed;

  /// How far behind the newest snapshot remote beans are drawn, in seconds.
  final double delay;

  final Map<String, _RemoteBean> _players = {};

  /// Seconds since this component started running.
  ///
  /// The buffers are stamped and read against this rather than wall-clock
  /// time: it advances with the game loop, so a stalled tab cannot leave the
  /// render head hours past every sample, and tests can step it by hand.
  double _clock = 0;

  /// The remote beans, by player id.
  Map<String, BeanComponent> get beans =>
      Map.unmodifiable({for (final e in _players.entries) e.key: e.value.bean});

  /// Everybody currently drawn, with the name to write above them.
  ///
  /// Names live here rather than on the bean because a bean is a *view*: it
  /// knows how it looks, not who it is. The nametag layer and the emote layer
  /// both need "who is where", and this is the one place that can answer it.
  Iterable<({String id, String name, BeanComponent bean})> get views sync* {
    for (final entry in _players.entries) {
      yield (id: entry.key, name: entry.value.name, bean: entry.value.bean);
    }
  }

  /// The bean belonging to [id], or `null` if they are not in view.
  BeanComponent? beanOf(String id) => _players[id]?.bean;

  /// How many other players are currently in view.
  int get count => _players.length;

  /// The time remote beans are currently being drawn at.
  double get renderTime => _clock - delay;

  /// Applies one message from the server.
  ///
  /// Messages the client sends (join, move) and anything unreadable are
  /// ignored: this is the receiving end only.
  void apply(ProtocolMessage message) {
    switch (message) {
      case WelcomeMessage():
        // A welcome means a fresh session, so anything left over from an
        // earlier connection goes. The first snapshot repopulates it.
        _clear();
      case SnapshotMessage():
        _applySnapshot(message);
      case PlayerLeftMessage():
        // Gone from the world, not merely out of range. Same removal, but
        // the distinction is the server's to make and it made it.
        _remove(message.id);
      case JoinRejectedMessage():
        // Handled by the connection supervisor, which is the only thing that
        // can act on it. The game layer just keeps drawing.
        break;
      case PlayerEmotedMessage():
        // Reactions are drawn by the emote layer, which needs the bean this
        // one belongs to. Routing it through here as well would mean two
        // things owning the same event.
        break;
      case PlayerBoardMessage():
        // The *edge*. The steady state arrives in `appeared` instead, which
        // is why somebody who walks into range of a surfer sees the board
        // without this message being involved at all.
        //
        // Nothing happens if they are not on screen: a board change from
        // somebody this client has no bean for has nowhere to go, and the
        // next appearance carries the flag anyway.
        _players[message.id]?.bean.hasBoard = message.hasBoard;
      case WorldStatsMessage():
        // A world-wide counter is HUD state, not world state. It crosses into
        // the widget layer through a notifier, never through a component.
        break;
      case ConfigMessage():
        // The event's copy and its crowd size. The game applies it, the
        // widget layer above shows it; either way it says nothing about
        // where anybody is standing, which is all this class tracks.
        break;
      case JoinMessage():
      case MoveMessage():
      case EmoteMessage():
      case BoardMessage():
      case UnknownMessage():
      case AdminSetConfigMessage():
      case AdminSetMaintenanceMessage():
      case AdminAuthMessage():
      case AdminAuthResultMessage():
      case AdminPlayerListMessage():
      case AdminKickMessage():
      case AdminBanMessage():
      case AdminMuteNameMessage():
      case AdminActionResultMessage():
      case AdminErrorMessage():
        // Admin traffic arrives on its own socket, handled by its own
        // screen, and never reaches the game layer at all.
        break;
    }
  }

  /// Removes every remote bean, e.g. when the connection drops.
  void clear() => _clear();

  @override
  void update(double dt) {
    super.update(dt);
    _clock += dt;
    final at = renderTime;

    for (final player in _players.values) {
      final target = player.buffer.positionAt(at);
      final bean = player.bean;
      // Velocity is measured from what was actually drawn, not from what the
      // server said. The animation then always matches the motion on screen,
      // including the moment a bean holds still waiting for a late snapshot.
      if (dt > 0) {
        final velocity = Vector2(
          (target.x - bean.position.x) / dt,
          (target.y - bean.position.y) / dt,
        );
        if (velocity.length > maxSpeed) velocity.scaleTo(maxSpeed);
        bean.velocity.setFrom(velocity);
      }
      bean.position.setValues(target.x, target.y);
    }
  }

  void _applySnapshot(SnapshotMessage snapshot) {
    // Appearances first: a player is in both lists on the tick they arrive,
    // and the bean has to exist before its position can be recorded.
    snapshot.appeared.forEach(_upsert);
    snapshot.positions.forEach(_record);
    snapshot.outOfRange.forEach(_remove);
  }

  void _upsert(PlayerState player) {
    final existing = _players[player.id];
    if (existing != null) {
      existing.name = player.name;
      // Re-appearing after a gap: keep the bean, drop the stale history so
      // it does not glide across the map from where it used to be.
      existing.bean
        ..appearance = BeanAppearance.fromPlayer(player)
        ..hasBoard = player.hasBoard
        ..position.setValues(player.x, player.y)
        ..velocity.setZero();
      existing.buffer = InterpolationBuffer()..add(_clock, player.x, player.y);
      return;
    }

    final bean =
        BeanComponent(
            position: Vector2(player.x, player.y),
            appearance: BeanAppearance.fromPlayer(player),
            animation: BeanAnimation(maxSpeed: maxSpeed),
            map: map,
          )
          // Set after construction rather than through the constructor,
          // because the setter is what asks the map whether surfing happens
          // here at all — see `BeanComponent.hasBoard`.
          ..hasBoard = player.hasBoard;
    _players[player.id] = _RemoteBean(
      bean: bean,
      name: player.name,
      buffer: InterpolationBuffer()..add(_clock, player.x, player.y),
    );
    // Not awaited: `add` completes when the component mounts, a frame later.
    unawaited(Future<void>.value(add(bean)));
  }

  void _record(PlayerPosition position) {
    // A position for somebody we were never told about: possible if an
    // `appeared` was missed. Dropping it is right — the next appearance
    // fixes it, and inventing a bean with no name or colour would be worse.
    _players[position.id]?.buffer.add(_clock, position.x, position.y);
  }

  void _remove(String id) => _players.remove(id)?.bean.removeFromParent();

  void _clear() {
    for (final player in _players.values) {
      player.bean.removeFromParent();
    }
    _players.clear();
  }
}

/// One remote player: the thing on screen, and the history it is drawn from.
class _RemoteBean {
  _RemoteBean({required this.bean, required this.name, required this.buffer});

  final BeanComponent bean;
  String name;
  InterpolationBuffer buffer;
}
