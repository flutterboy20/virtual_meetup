/// Why the server would not let a client into the world.
///
/// A closed set rather than a free-text string, for the same reason every
/// other decision in `protocol/` is: the client has to *do* something
/// different per reason — a bad name sends the player back to the setup
/// screen, a bad session id is the client's own bug and is retried with a
/// fresh id — and a string it has to pattern-match on is how that goes wrong.
///
/// The human sentence travels alongside it, in the rejection message's
/// `detail` field, so the client can show the server's wording without
/// parsing it.
enum JoinRejection {
  /// The display name failed the server's own run of the shared name rules.
  ///
  /// This is not the client's filter having missed something — the client
  /// filter is UX and the server's is the rule, so a client that skipped the
  /// check entirely (or was written by somebody else) lands here.
  invalidName('invalidName'),

  /// The session id was missing or not shaped like one this project issues.
  invalidSession('invalidSession'),

  /// A moderator removed this session from the event.
  ///
  /// Unlike the other two, there is nothing the player can change to get in —
  /// so the client must *not* send them back to the setup screen to try a
  /// different name. Saying so plainly is kinder than a lobby that silently
  /// refuses every attempt.
  banned('banned'),

  /// A moderator kicked this session, and the cooling-off period is not over.
  ///
  /// The one *temporary* refusal. It exists because a kick is otherwise
  /// invisible: the socket simply closes, the client cannot tell that from a
  /// dropped connection, and it reconnects within half a second under the
  /// same session id — so the person is back before the moderator has looked
  /// up. The client must stop retrying and let the *person* decide to come
  /// back, which is what makes a kick a warning shot rather than a flicker.
  kicked('kicked'),

  /// The event is closed for maintenance, and this is when it opens again.
  ///
  /// The only refusal that is not about the person being refused. Everybody
  /// gets it, nobody did anything, and the `detail` carries the moment the
  /// door unlocks — which is the one thing somebody staring at a closed
  /// event actually wants to know.
  maintenance('maintenance'),

  /// Every seat this server will hand out is taken.
  ///
  /// The second refusal that is not about the person being refused, and the
  /// only one that fixes itself: somebody leaves, a seat frees, and the same
  /// join that was refused a minute ago succeeds. So the client neither sends
  /// them back to setup — there is nothing to retype — nor treats it as a
  /// dead end. It waits and asks again.
  ///
  /// Deliberately *not* given a time. Unlike [maintenance], nobody knows when
  /// a seat frees, and a countdown here would be the client inventing a
  /// number the server never sent.
  ///
  /// **What a v4 peer does with it.** [fromWireName] fails *closed*: an
  /// unknown wire name reads as [invalidName], so a pre-v5 client meeting a
  /// full v5 server is sent back to setup and told to pick a different name.
  /// That is wrong, and it is safe, and it is self-correcting — the person
  /// changes their name, tries again, and either gets in or sees it again.
  /// Failing closed is the deliberate choice: the alternative, throwing on a
  /// reason this build has never heard of, would turn every future addition
  /// to this enum into a crash on every older client.
  worldFull('worldFull');

  const JoinRejection(this.wireName);

  /// The string this reason travels as.
  final String wireName;

  /// Returns the reason named by [wireName], or [JoinRejection.invalidName].
  ///
  /// Falls back to the name case because it is the only one a person can
  /// actually fix: sending somebody to the setup screen over a reason this
  /// build has never heard of is a far better failure than a dead end.
  static JoinRejection fromWireName(String? wireName) {
    for (final value in JoinRejection.values) {
      if (value.wireName == wireName) return value;
    }
    return JoinRejection.invalidName;
  }
}
