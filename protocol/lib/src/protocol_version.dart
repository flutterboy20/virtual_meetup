/// The version every message on the wire carries.
///
/// It is bumped when a message shape changes in a way an older peer cannot
/// read. Both ends stamp it on everything they send and neither end refuses a
/// message because of it — the field exists so a future version *can* make
/// that call without a flag day.
///
/// v2 (Phase 3) replaced the per-move broadcast with interest-managed
/// snapshots: `playerJoined` and `playerMoved` are gone, `snapshot` arrived,
/// and `welcome` shrank to just an id. A v1 client cannot read a v2 world.
///
/// v3 (Phase 4) gave `join` a `sessionId` and added `joinRejected`. A v2
/// client still parses every v3 message it receives — the change is on the
/// way *up* — but it joins without a session id and so cannot be re-seated
/// after a drop, which the server answers with a `joinRejected`.
/// v4 (Phase 11) added the surfboard: `PlayerState` grew a `hasBoard` flag,
/// and two messages appeared — `board` on the way up and `playerBoard` on the
/// way down.
///
/// A v3 peer is fine in both directions, and that is not luck. `hasBoard` is
/// read with `readOptionalBool`, so a v3 sender's `PlayerState` — which has
/// no such field — reads as "no board" instead of failing to parse. The two
/// new message types decode to an unknown message on a v3 build, and both
/// ends already drop those. So a v3 client on a v4 server sees people who
/// never find a board, a v4 client on a v3 server never gets one, and nobody
/// crashes or is refused.
///
/// v5 (Phase 13) added one value to `JoinRejection`: `worldFull`, the answer
/// a server gives when every seat it will hand out is taken. No message grew
/// a field and no message was removed — the whole change is one more string
/// that can appear in a `joinRejected`'s `reason`.
///
/// A v4 peer is fine, in the only direction this can travel. `worldFull` only
/// ever goes server → client, and `JoinRejection.fromWireName` falls back to
/// `invalidName` for a name it does not know, so a v4 client meeting a full
/// v5 server is sent back to setup instead of crashing or hanging. The wording
/// it shows is wrong; the behaviour is safe and self-correcting. Nothing on
/// the way *up* changed at all, so a v5 client on a v4 server is unaffected.
const int protocolVersion = 5;

/// Returns a human-readable banner naming the protocol version.
///
/// The client renders it and the server logs it, which is how we can see at a
/// glance that both are built against the same [protocolVersion].
String helloProtocol() => 'Hello from protocol v$protocolVersion';
