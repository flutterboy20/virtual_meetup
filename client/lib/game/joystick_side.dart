import 'package:flutter/widgets.dart' show EdgeInsets;

/// Which side of the screen the virtual joystick sits on.
///
/// Right-handed players want it on the right, left-handed players on the
/// left. Phase 4 persists the choice; for now it lives in memory.
enum JoystickSide {
  /// Joystick pinned to the left edge of the viewport.
  left,

  /// Joystick pinned to the right edge of the viewport.
  right;

  /// The other side, for a toggle.
  JoystickSide get opposite => this == left ? right : left;

  /// Human-readable label for the settings toggle.
  String get label => this == left ? 'Left' : 'Right';

  /// The viewport margin that pins the joystick to this side.
  ///
  /// Flame's `ComponentViewportMargin` reads a zero edge as "not this side",
  /// so exactly one horizontal edge is set.
  EdgeInsets margin({required double inset, required double bottomInset}) {
    return this == left
        ? EdgeInsets.only(left: inset, bottom: bottomInset)
        : EdgeInsets.only(right: inset, bottom: bottomInset);
  }
}
