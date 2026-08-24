import 'dart:ui' show Offset;

import 'package:client/core/sponsor.dart';
import 'package:flutter/foundation.dart';

/// What the minimap draws, as of the last sample.
///
/// A value object rather than live references, so the widget layer can never
/// reach into a Flame component and read a position mid-frame.
@immutable
class MinimapFrame {
  /// Creates a frame.
  const MinimapFrame({required this.you, required this.others});

  /// Nobody anywhere. The state before the first sample.
  static const MinimapFrame empty = MinimapFrame(
    you: Offset.zero,
    others: [],
  );

  /// Where the local bean is, in world units.
  final Offset you;

  /// Where every visible remote bean is, in world units.
  final List<Offset> others;

  @override
  bool operator ==(Object other) =>
      other is MinimapFrame &&
      other.you == you &&
      listEquals(other.others, others);

  @override
  int get hashCode => Object.hash(you, Object.hashAll(others));
}

/// One line of text the world wants to say, once.
///
/// A value object with an id rather than a bare string, and the id is the
/// whole reason: two identical toasts in a row — three taps that each say
/// "keep going", say — must still each be *a toast*, and a `ValueNotifier`
/// holding the same string twice does not notify. The counter makes every
/// raise a distinct value.
@immutable
class WorldToast {
  /// Creates a toast saying [message].
  WorldToast(this.message) : id = ++_counter;

  static int _counter = 0;

  /// What to say.
  final String message;

  /// Which raise this is, so two identical messages are two values.
  final int id;

  @override
  bool operator ==(Object other) =>
      other is WorldToast && other.id == id && other.message == message;

  @override
  int get hashCode => Object.hash(id, message);

  @override
  String toString() => 'WorldToast($id: $message)';
}

/// The narrow channel between the game loop and the HUD.
///
/// This is the boundary the whole client architecture is built around, and
/// the rule is one sentence: **game-loop state never goes into a Provider.**
/// Remote positions change fifteen times a second and beans move sixty;
/// pushing either through the widget tree would rebuild the UI at that rate
/// and spend the frame budget on nothing.
///
/// So the three things the HUD genuinely needs cross here instead, as plain
/// [ValueNotifier]s, each deliberately slower than the loop that feeds it:
///
/// - [online] changes about once a second, because the server says so.
/// - [nearbySponsor] changes when somebody walks up to a booth — seconds
///   apart, and written only on an actual change.
/// - [minimap] is *sampled*, not streamed: the game pushes a frame a few
///   times a second, which is far below 60 and far above what the eye needs
///   from a 100-pixel map.
///
/// Each notifier rebuilds exactly one small widget through a
/// `ValueListenableBuilder`, never the screen.
class WorldHud {
  /// How many people are in the world, everywhere. Fed by the server.
  final ValueNotifier<int> online = ValueNotifier<int>(0);

  /// The booth the local bean is standing at, or `null`.
  final ValueNotifier<Sponsor?> nearbySponsor = ValueNotifier<Sponsor?>(null);

  /// The most recent minimap sample.
  final ValueNotifier<MinimapFrame> minimap = ValueNotifier<MinimapFrame>(
    MinimapFrame.empty,
  );

  /// The last thing the world said out loud, or `null` if it has said
  /// nothing.
  ///
  /// Written a handful of times in a whole session — three taps on a board
  /// and one on a hint bean — which is exactly what earns it a place on this
  /// side of the boundary. Read by one small widget that fades it in, holds
  /// it, and fades it out; nothing else in the HUD rebuilds.
  final ValueNotifier<WorldToast?> toast = ValueNotifier<WorldToast?>(null);

  /// Says [message] to the player.
  ///
  /// A method rather than the caller building a [WorldToast], so the game
  /// layer never has to know that two identical messages need distinct
  /// values to notify.
  void say(String message) => toast.value = WorldToast(message);

  /// Releases the notifiers. Called by whoever created this.
  void dispose() {
    online.dispose();
    nearbySponsor.dispose();
    minimap.dispose();
    toast.dispose();
  }
}
