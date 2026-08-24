# `server`

The relay. It culls and rebroadcasts player state; it does **not** simulate movement.

Run it: `fvm dart run bin/server.dart` (set `PORT` to override the default 8080).

| Route     | What it does |
|-----------|--------------|
| `/health` | 200 with the protocol banner |
| `/ws`     | WebSocket upgrade — join, move, leave |

Inside: `PlayerRegistry` is who is here (pure logic, no sockets), `Relay` is the
join/move/leave protocol, and `ws_handler.dart` is the only file that knows what a
WebSocket is. Broadcast is naive and O(n²) on purpose — interest culling replaces it
in Phase 3.
