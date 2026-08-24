# `client`

The Flutter web app players actually see.

Run it: `fvm flutter run -d chrome`, optionally with
`--dart-define=SERVER_URL=ws://<host>:8080/ws`.

Two layers with different rules: `lib/game/` is Flame (beans, camera, joystick,
remote players — no Provider, ever), and everything else is plain Flutter widgets.
`lib/services/network_client.dart` is the one connection to the relay; it knows
nothing about Flame.
