/// A reaction one player can throw above their bean.
///
/// A closed set, not free text. Two reasons, and only one of them is
/// technical: a fixed enum is three characters on the wire instead of an
/// arbitrary string, and — the one that actually matters at a public event —
/// a closed set cannot be used to say something that needs moderating. This
/// world has no chat on purpose; emotes are the whole expressive vocabulary,
/// so the vocabulary is chosen up front.
enum EmoteKind {
  /// 👋
  wave('wave', '👋'),

  /// 👏
  clap('clap', '👏'),

  /// ❤️
  heart('heart', '❤️'),

  /// 😂
  laugh('laugh', '😂'),

  /// 🔥
  fire('fire', '🔥'),

  /// 🎉
  party('party', '🎉');

  const EmoteKind(this.wireName, this.glyph);

  /// The string written into a message's `emote` field.
  final String wireName;

  /// The character drawn above the bean.
  ///
  /// Lives here rather than in the client so the two ends agree on what a
  /// `wave` *is*; the client still owns how it is animated.
  final String glyph;

  /// Returns the emote named by [wireName], or `null` if it is not one.
  ///
  /// Unlike a cosmetic, an unreadable emote has no sensible default —
  /// silently turning an unknown reaction into a wave would put words in
  /// somebody's mouth — so this returns `null` and the server rejects it.
  static EmoteKind? fromWireName(String? wireName) {
    for (final kind in EmoteKind.values) {
      if (kind.wireName == wireName) return kind;
    }
    return null;
  }
}
