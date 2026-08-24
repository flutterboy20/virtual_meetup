# `protocol`

The wire protocol shared by `client` and `server`. Every message that crosses the
WebSocket is defined here exactly once, so the two ends cannot drift apart.

**Pure Dart, no Flutter dependency.** That is the whole point — a plain Dart server
cannot import a package that pulls in Flutter.
