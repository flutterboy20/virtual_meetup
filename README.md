# Virtual Conference

A browser-based, multiplayer walk-around world for any conference or meetup — open a
link on your phone, pick a character, and roam one shared map with everyone else in
the room. The event's name and front-door copy are config, not code.

[![CI](https://github.com/flutterboy20/virtual_conference/actions/workflows/ci.yml/badge.svg)](https://github.com/flutterboy20/virtual_conference/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> **Status:** feature-complete and hardened. Not yet deployed.
>
> Five themed zones in a cross, static collision, sponsor booths driven by config,
> proximity nametags, emotes, a minimap and a live head count. Moderation is built —
> mute, kick and ban behind a token, with an audit log. The relay culls with a spatial
> grid on a tuned 15Hz tick with a nearest-N neighbour cap on top
> (see [Measured load](#measured-load)), and holds up to 300 concurrent clients with
> tick headroom to spare.
>
> Hardened for a public URL: admission control at the HTTP upgrade, per-socket size
> and rate limits before decode, join deadlines, and origin pinning that fails closed.
> The deployment stack — Docker, Caddy, one origin for app and socket — is written and
> lives in [`deploy/`](deploy/). The public URL is the last piece.

## The world

A **cross**, not a maze. Five zones meet along walkways as wide as the rooms
themselves, because two hundred people funnelled through a doorway is a jam.

```
                    +-------------+
                    |  CONFERENCE |     stage, screen, seat rows
                    |     HALL    |
      +-------------+-------------+-------------+
      |   PHOTO     |   ATRIUM    |   SPONSOR   |
      |    WALL     |  (spawn)    |     ROW     |   booths from config
      +-------------+-------------+-------------+
                    |   LOUNGE    |     pool, loungers
                    |   & POOL    |
                    +-------------+
```

- **Atrium** — everybody spawns here, on a ring around the credit pillar.
- **Conference hall** — the stage and its seating.
- **Sponsor row** — booths; walk up to one and its panel opens.
- **Lounge & pool** — the chill zone.
- **Photo wall** — a "gather here" beacon that brightens as people stand on it.

All of it is drawn from vector shapes in code. There is not one image in the bundle —
every prop, bean and floor tile is a path — because every image is cold-load time on
venue wifi. The only binary assets are the four bundled typefaces (Archivo and
Bricolage Grotesque, ~410KB together), which are bundled rather than fetched for the
same reason: a face that arrives over the network arrives after the wordmark has
already been painted in something else.

You walk through other people, never into them. Player-player collision would turn a
busy atrium into a traffic jam and give anyone a way to trap somebody in a corner.

## Repo layout

| Path             | What it is |
|------------------|------------|
| `client/`        | Flutter web app — the player experience |
| `server/`        | Dart `shelf` server — the relay |
| `protocol/`      | Pure-Dart shared package — wire message types, defined once |
| `tool/loadtest/` | Dart CLI — opens N bot clients that wander, to measure the server |
| `deploy/`        | Production stack — Dockerfile, Caddyfile, compose, and the runbook |

`protocol/` has **no Flutter dependency**, which is what lets both the Flutter client
and the plain-Dart server import the same message definitions.

## Run locally

Requires [`fvm`](https://fvm.app). The Flutter version is pinned in `.fvmrc`.

```bash
git clone https://github.com/flutterboy20/virtual_conference.git
cd virtual_conference

fvm install                                  # installs the pinned Flutter SDK
fvm exec dart run melos bootstrap            # resolves the pub workspace
```

`fvm exec` puts the pinned SDK on `PATH`, which is how melos finds `dart` and
`flutter`.

Run the server:

```bash
cd server
ALLOWED_ORIGINS='*' fvm dart run bin/server.dart   # listens on :8080
curl localhost:8080/health                         # -> Hello from protocol v5
curl localhost:8080/metrics                        # -> live load numbers as JSON
```

**`ALLOWED_ORIGINS='*'` is required to run the web client against it**, and it is
deliberately not the default. With the variable unset the server runs, moderation
works, `curl` and the load tester connect — and no browser can open a socket. That
is the safe end of the switch: forgetting it in production costs you an outage you
notice in seconds, rather than an open door you notice never. See
[Configuration](#configuration).

On PowerShell:

```powershell
$env:ALLOWED_ORIGINS = '*'
fvm dart run bin/server.dart
```

It logs every connect, join and leave, and a metrics line every five seconds. The
startup banner prints which origins are accepted, so a misconfiguration is one line
of output rather than a mystery. To run it with moderation enabled, see
[Moderation](#moderation).

Run the client in Chrome (twice, for two players):

```bash
cd client
fvm flutter run -d chrome
```

The client connects to `ws://localhost:8080/ws` unless you point it somewhere
else:

```bash
fvm flutter run -d chrome --dart-define=SERVER_URL=ws://192.168.1.20:8080/ws
```

### Load-test it

With the server running, fill the world with bots that walk around:

```bash
cd tool/loadtest
fvm dart run bin/loadtest.dart --bots 200 --seconds 60
```

Then join with a real browser or phone and walk among them. Watch the server's
metrics line while it runs — `perSnapshot` far below `players` is interest
management doing its job.

| Flag        | Default                  | Meaning |
|-------------|--------------------------|---------|
| `--bots`    | `50`                     | How many simulated players |
| `--url`     | `ws://localhost:8080/ws` | Which relay to hit |
| `--seconds` | `30`                     | How long to walk after everyone connects |
| `--report`  | `5`                      | Seconds between report lines |
| `--seed`    | `1`                      | Random seed, so a run can be repeated exactly |
| `--scenario`| `spread`                 | `spread` (wander the whole map), `cluster` (crowd at the atrium spawn), or `churn` (wander, with bots leaving and rejoining continuously) |
| `--ramp`    | `10`                     | Seconds to spread the connections over, so the swarm arrives like a conference filling up rather than a connect storm |
| `--cluster` | _(from scenario)_        | Override the cluster radius, in world units |
| `--churn`   | _(from scenario)_        | Override the fraction of the swarm that leaves and rejoins each minute, e.g. `0.2` |
| `--csv`     | _(off)_                  | Append one row per report line, for charting a long run afterwards |

The clustered run is the interesting one. Bots spread evenly over the map put a handful
of people in each interest cell and make the culling look free; piling them into the
atrium is what a real event does at 09:30 — and it costs the server about 38% more per
tick at the same head count.

```bash
fvm dart run bin/loadtest.dart --bots 200 --scenario cluster --seconds 30
```

`churn` is the one that finds leaks. A steady swarm never exercises join or leave, and
join/leave is where a six-hour event goes wrong: an orphaned grid entry, a seat held
forever, a socket never really closed. The signature is a flat player count with a
rising memory line, so run it long and chart the trend:

```bash
# server
METRICS_CSV=soak.csv fvm dart run bin/server.dart
# bots: a clustered crowd, a fifth of which swaps out every minute, for 35 minutes
fvm dart run bin/loadtest.dart -n 250 --scenario churn --cluster 200 --churn 0.2   --seconds 2100 --csv soak-client.csv
```

## Checks

```bash
fvm exec dart run melos run ci --no-select   # format + analyze + test, everything
```

## Configuration

| Setting      | Where  | Default                    | Meaning |
|--------------|--------|----------------------------|---------|
| `PORT`       | server | `8080`                     | TCP port the server listens on |
| `CELL_SIZE`  | server | `320`                      | Interest grid cell edge, in world units. Each client is sent the players in its own cell plus the eight around it. |
| `SERVER_URL` | client | `ws://localhost:8080/ws`   | WebSocket endpoint, passed at build time as `--dart-define=SERVER_URL=…`. Production will be `wss://`. The welcome screen's online count is read over HTTP from the same host. |
| `SESSION_LINGER_SECONDS` | server | `90` | How long a disconnected player's seat is held for their return. `0` disables it, so every reconnect is a new player at a new spawn point. |
| `NEIGHBOUR_CAP` | server | `40` | The most neighbours one snapshot may carry. A hard limit on top of the grid, for when everybody stands in the same cell. |
| `ADMIN_TOKEN` | server | *(unset)* | The shared secret for the moderation screen. **Unset means moderation is switched off**, not open — every admin message is refused. At least 16 characters; the server refuses to start with a shorter one. Never commit a value. |
| `BAN_FILE` | server | `bans.json` | Where the ban list is persisted, so a restart mid-event does not readmit everybody you removed. |
| `AUDIT_FILE` | server | `audit.log` | Where every moderation action is appended. Also written to stderr. |
| `KICK_COOLDOWN_SECONDS` | server | `30` | How long a kicked session is refused before it may rejoin. It has to outlive the client's own reconnect backoff, or the kicked client simply reconnects and the kick undoes itself. `0` makes a kick a bare disconnect. |
| `TICK_HZ` | server | `15` | How often each client is sent a snapshot. The single biggest lever on server CPU and bandwidth — both scale with it linearly. Lowering it means raising the client's interpolation delay to match. |
| `MAX_SOCKETS` | server | `800` | The most sockets held open at once, checked at the HTTP upgrade — past it the server answers `503` and allocates no socket. This is the cap a flood meets, and it counts **sockets, not players**: a socket that connects and never joins is invisible to the player count. Far above any real crowd; it should never fire on the day. |
| `MAX_PLAYERS` | server | `400` | The most players seated at once. A join past it is refused with `worldFull` and the client shows a screen that says so and lets itself back in when a seat frees. Costs a socket on purpose, so the person can be told why. |
| `ALLOWED_ORIGINS` | server | *(none)* | Comma-separated origins a **browser** may connect from, e.g. `https://meet.example.com`. Drives both WebSocket handshakes and the `Access-Control-Allow-Origin` on `/config` and `/metrics`. **Unset means no browser may connect** — set it to `*` for local development and the LAN demo, or to your exact HTTPS origin in production. `*` mixed into a list is refused rather than guessed at. **Not access control:** a browser always sends `Origin`, so this stops a hostile web page using its visitors' browsers — but `curl` and the load tester send no `Origin` at all and pass straight through. `MAX_SOCKETS` is what limits them. |
| `METRICS_CSV` | server | *(off)* | Append one row of load metrics per reporting window to this file, for charting a run afterwards. Off by default: a server that writes files nobody asked for is a server that fills a disk during a six-hour event. |
| `PERF_HUD` | client | `false` | Compiles in an on-screen `fps / p95 / jank% / worst` readout, for profiling on a real phone where there is no DevTools. `--dart-define=PERF_HUD=true`. Tree-shaken out of the shipping bundle. |

Sponsor booths are not environment configuration — they live in the **event document**
a moderator pushes from the admin screen, under a `sponsors` key holding the same
entries `client/assets/sponsors.json` holds. A document that names no sponsors falls
back whole to that bundled file, so the app still ships with a working sponsor row and
still opens it with no network. Booths are read when a world is built, so a pushed
sponsor list lands for everybody on their next reload rather than moving a booth out
from under a bean standing in it.

No secrets live in this repo. Configuration is read from the environment at runtime.
`bans.json` and `audit.log` are runtime state about real attendees and are gitignored.

## Moderation

Free-text names are allowed on purpose — a name is most of what makes a bean *you*.
The safety net for that is **post-hoc, not pre-approval**: an automated filter at the
door, and a reactive kill switch behind it. Manually approving three hundred people
between talks is not a thing anybody can do, and it would destroy the
scan-and-play-in-five-seconds flow the whole app depends on.

### Turning it on

The token is a **shared secret you invent**. The server reads it from its environment
at startup and holds it in memory; you type the same string into the moderation
screen once. It is never in this repo, never in the client bundle, and never logged.

PowerShell:

```powershell
cd server
$env:ADMIN_TOKEN = 'a-long-random-string-you-invent'
fvm dart run bin/server.dart
```

Bash / zsh:

```bash
cd server
ADMIN_TOKEN='a-long-random-string-you-invent' fvm dart run bin/server.dart
```

Startup prints `moderation: on` — never the value. Without the variable it prints
`moderation: OFF` and refuses every admin message.

Open the moderation screen by adding `#og-route` to the client's URL —
`http://localhost:8080/#og-route`. Nothing in the player-facing app links to it or
mentions it, and `#admin` is not it. Enter the token; the screen unlocks and shows a
live list of everybody in the world, searchable by name or player id.

The route name lives in two constants that **must agree**:
`adminWebSocketPath` in `server/lib/src/handler.dart` and `adminSocketPath` /
`adminRouteFragment` in `client/lib/core/`. Tests on both sides pin the value, so
changing one without the other fails CI rather than failing at the event.

Three actions, in increasing severity:

| Action | What happens | Reversible |
|--------|--------------|------------|
| **Mute name** | Their displayed name becomes `Guest` for everybody, within one tick (~66ms). They stay in the world and are not disconnected. | Yes, from the same row |
| **Kick** | Disconnected immediately; their session is refused for `KICK_COOLDOWN_SECONDS` (30 by default) so their client cannot quietly reconnect, and the name they were kicked under is refused for the rest of the run. They come back through setup as a first-timer: new name, colour and bean. | The cooldown expires on its own; the name block lasts until the server restarts |
| **Ban** | Disconnected, and their session is refused for the rest of the event. Survives a server restart. | Yes, from the **Banned** tab |

The **Banned** tab lists every ban in force and lifts one in two taps. Rows made
during the current run are labelled with the name the person was banned under;
rows read back off disk after a restart show only a handle and the date is gone,
because the ban file keeps session ids and nothing else — a file of the names
people were removed for is a document somebody then has to own, and it would
outlive the event that needed it. A forgotten row is still liftable: the handle
is a one-way digest of the session id, so it is the same handle before and after
a restart.

Mute-name is the one to reach for first. A bad *name* is the likely incident in a
world with no chat, and it fixes exactly that without throwing somebody out of a
conference.

Some deliberate limits, so nobody is surprised by them on the day:

- **Bans key on the session id**, which lives in the browser's storage for the
  site. Clearing site data — or just opening a private window — produces a new
  one, and the banned person walks back in as a first-timer: new name, new bean,
  nothing of theirs kept. The same is true of the name block a kick leaves
  behind. This is a tool for removing a disruption in ten seconds, not an access
  control system, and over-building it was not worth the complexity. The Banned
  tab says so on the screen, so nobody learns it during an incident.
- **Session ids never leave the server.** One is a bearer token — anybody holding
  it can walk into that player's bean — so neither the player list nor the ban
  list carries one. A ban is named on the wire by a truncated SHA-256 of the
  session id: one-way, and the same across restarts so a persisted ban stays
  liftable.
- **The token is held in memory only.** It is never persisted, never in the URL, and
  never in the client bundle. A refresh asks for it again — deliberately, because a
  moderator's phone gets put down on tables.
- **The route name is quiet, not secret.** It is compiled into the client bundle, so
  anybody willing to read the shipped JavaScript can find it. What it buys is that no
  attendee poking at `/admin` finds anything, and the server log stays quiet enough
  that a *real* probe stands out. Authorization is checked on the server, on every
  message, every time. Obscurity is why nobody stumbles in; the token is why it is
  safe that they could.

### Deploying it

The whole stack — Dockerfile, Caddyfile, `docker-compose.yml`, an annotated
`.env.example` and the provisioning steps — lives in **[`deploy/`](deploy/README.md)**.
The shape is one VM, one origin: Caddy terminates TLS and serves the Flutter bundle,
and the relay sits behind it on a private network, never published to the host.

Five things that are only true in production:

- **`wss://`, not `ws://` — non-negotiable.** The token crosses the wire inside the
  WebSocket frame. Over plaintext, anybody on the venue wifi can read it. Terminate
  TLS at your host or reverse proxy, and build the client with
  `--dart-define=SERVER_URL=wss://your-host/ws`.
- **The token comes from the host's secret store**, not a shell you typed in: a
  systemd `Environment=`, `docker run -e ADMIN_TOKEN=…`, or the secrets panel of
  whatever PaaS you are on. Rotating it is a restart, and it invalidates every open
  moderation session.
- **`BAN_FILE` and `AUDIT_FILE` need a persistent disk.** On a container with an
  ephemeral filesystem they vanish on every redeploy, which quietly turns every ban
  into a kick. Point them at a mounted volume.
- **`ALLOWED_ORIGINS` must name your real origin.** Not `*`, which is the
  development value. The server refuses every browser without it, so this one
  announces itself immediately rather than failing quietly.
- **Give the process a memory ceiling.** Dart's default old-generation heap is
  30 GB, which is not a limit so much as the absence of one. The frame parser
  already refuses oversized frames before allocating them, but a heap cap is the
  backstop for everything that is not a frame:

  ```bash
  # AOT binary, which is how this should be deployed.
  # COMMA-separated. A space-separated value is parsed as one flag and the whole
  # thing is discarded — see below.
  DART_VM_OPTIONS="--old_gen_heap_size=512,--abort_on_oom" ./server
  ```

  **The separator is a comma, and getting it wrong fails almost silently.** Measured
  on Dart 3.13.0, `"--old_gen_heap_size=512 --abort_on_oom"` produces one line —
  `Ignoring flag: 512 --abort_on_oom is an invalid value for old_gen_heap_size` —
  and then runs with no ceiling at all. That line scrolls past in a startup banner
  and the server looks entirely healthy until the day something allocates.

  `--abort_on_oom` matters: without it the isolate throws and the process limps on
  in a state nothing tests. With it the process dies and the supervisor restarts it.
  Set the container or VM memory limit above that number, not equal to it.

## Architecture in one line

**The server is a relay, not a simulator.** Clients own their own position; the server
culls and rebroadcasts. Nothing here runs movement physics on the server.

### How a session goes

1. The client opens `ws://…/ws` and sends `join` (session id, name, colour,
   cosmetic). The session id is a random 128-bit token the *device* generated and
   saved locally — it is how the server recognises somebody who comes back.
2. The server re-runs the shared name rules, and refuses with a typed
   `joinRejected` if they fail. Otherwise it seats the join one of three ways:
   a session it has never seen gets a new id and a spot on the atrium's spawn ring;
   a session
   that is already seated has its socket swapped underneath it; a session whose
   socket died within `SESSION_LINGER_SECONDS` gets its old id and its old
   position back. Either way it replies `welcome` — just the id.
3. The client sends `move` about ten times a second — never per frame, and never
   while standing still. The server clamps it into the world, records it, and
   relays nothing.
4. Fifteen times a second the server ticks: for each client it asks the spatial
   grid who is nearby, trims that to the nearest `NEIGHBOUR_CAP`, and sends one
   `snapshot` — the positions of those players, plus full metadata for anyone who
   just came into range, plus the ids of anyone who just left it. A client with
   nobody nearby is sent nothing at all.
5. The client renders remote beans 100ms in the past, interpolating between the
   two snapshots either side of that moment, which turns 15Hz data into smooth
   60fps motion. Its own bean is never interpolated — that has to feel instant.
   Collision is resolved here and only here; the server never checks a wall.
6. Once a second the server sends `worldStats` — the total head count. It is the
   only message that is *not* culled, and deliberately so: interest management
   hides how big the room is, and "three hundred people are here" is most of why
   walking into a busy room feels good.
7. Tapping a reaction sends `emote` — a kind, and no id, because the server knows
   whose socket it arrived on. The server rate-limits it per player with a token
   bucket and relays `playerEmoted` to that player's neighbours only. Emotes are
   ephemeral: never stored, never replayed to somebody who arrives later.
8. When a socket closes — cleanly, or because a tab was killed — the server
   removes the player and sends `playerLeft` to everyone who could see them. The
   bean leaves the world immediately, but the *seat* is held for
   `SESSION_LINGER_SECONDS`.
9. The client notices the drop and retries on an exponential backoff with jitter,
   capped at 20 seconds, re-joining with the same session id every time. There is
   no error screen and no bounce back to the lobby: your own bean never stopped
   working, because it always owned its own position.

Every message carries a `type` tag and a protocol `version`, and anything a peer
cannot read is dropped rather than treated as fatal. That is what lets the client
and the server be deployed slightly out of step.

### Identity, and what it is not

A **session id** names a device and is the client's to keep. A **player id** names a
seat in the world and is the server's to give. The socket is neither, and it dies
constantly — a phone leaves wifi, a lid closes, a tab backgrounds — so the session
id is the only thing that can say "this is the same person" over a connection the
server has never seen before.

It is a bearer token with no server-side secret behind it. That is a deliberate,
bounded risk: the worst somebody can do with a stolen one is take over a bean at a
conference.

### Names

Names are validated by **the same functions in `protocol/`, on both ends**. Length
(2–16), then a character whitelist, then a wordlist checked against a form with the
separators stripped and leetspeak digits folded back, so `f.u.c.k` and `5h1t` do not
get through. Duplicate names are allowed — turning people away at the door for a
name collision buys nothing, and beans are told apart by colour and position.

The client's pass exists so the person typing gets a message. **The server's pass is
the rule**, and it runs whether or not the client bothered.

The whitelist is Latin-only, which is a real cost at an Indian conference and is
written down as such in `protocol/lib/src/name_validation.dart`. It buys immunity to
zalgo, bidi overrides, zero-width padding and Cyrillic homoglyphs without having to
enumerate them.

### Why interest management

Rebroadcasting every move to every player costs roughly `players² × send rate`
messages — about 400,000/sec at 200 attendees, which is dead on arrival. The grid
makes each client's cost depend on its *neighbours* instead.

## Measured load

One laptop (i7-12650H, 10 cores, Windows 11), AOT-compiled server and bots on the
**same machine** over loopback. That makes every tick figure pessimistic — the server
competes with the swarm generating its load — and every bandwidth figure optimistic,
because loopback has no latency and no MTU. Numbers are the server's own, in steady
state, at the shipping configuration: 15 Hz tick, 320-unit cells, neighbour cap 40.

### Why a grid is not enough on its own

Phase 3 measured players spread evenly over the map. Phase 5 gave the world a shape
that concentrates them, and the clustered load test found the hole:

> The atrium is 400 world units across. A 3×3 block of 320-unit interest cells is 960
> units across. When everybody piles into the atrium, **every person is inside every
> other person's interest block and the grid culls nothing at all.**

Shrinking the cells does not fix it — the interest area has to stay wider than the
screen (a laptop sees ~875 units across) or players pop into existence at its edge. So
there is a second, harder limit: the server sends the **nearest 40** neighbours and no
more. In a crowd that dense you cannot tell 40 beans from 115 without walking through
them. A player already known gets a 25% distance discount so nobody at the boundary
flickers in and out, re-sending their metadata every tick.

120 bots, all clustered within 220 units of spawn:

| | grid only | grid + cap |
|---|---:|---:|
| players per snapshot | 115 | 40 |
| per client | 56 KiB/s | 22 KiB/s |

### Steady state

The complete app — art, nametags, emotes, booths, minimap, moderation all live:

| Players | Spread | Per snapshot | Avg tick | p95 tick | Overruns | Per client |
|--------:|:-------|-------------:|---------:|---------:|---------:|-----------:|
|     100 | clustered | 40 |  6.5 ms |  8.7 ms | 0 | 19.9 KiB/s |
|     200 | clustered | 40 | 14.2 ms | 17.2 ms | 0 | 21.5 KiB/s |
|     300 | over the map | 40 | 20.9 ms | 23.3 ms | 0 | 20.8 KiB/s |
|     300 | clustered | 40 | 23.1 ms | 25.6 ms | 0 | 22.5 KiB/s |

At 300 people packed into one room the tick uses **35% of its 66 ms budget** and has
never overrun it. Per-client bandwidth is flat as the crowd grows — that is the cap
working — but 300 × 22.5 KiB/s is ~54 Mbit/s of server egress, which is a venue-uplink
question rather than a code one.

### Sustained

250 players clustered in the atrium, a fifth of them leaving and rejoining every minute,
for **35 continuous minutes** (`--scenario churn --cluster 200`):

- **0 tick overruns** out of ~31,700 ticks; worst single tick 61.8 ms.
- **1,749 leave/rejoin cycles**, and the player count read exactly 250 in all 420
  metric windows. No ghosts, no leaked seats.
- Resident memory **plateaued** at 71 MB — 69.7 → 71.3 over the first three fifths of
  the run, then flat. A leak does not flatten out.

### The optimisation that mattered

Choosing which 40 neighbours to send used to be `list.sort(byDistance)` — `O(n log n)`
comparisons, each one recomputing both operands' distances. At 300 people in one atrium
that was ~4,900 distance calculations per player per tick, 4,500 times a second.

It is now a bounded max-heap (`server/lib/src/nearest.dart`): each candidate's distance
is computed exactly once, and only a candidate that beats the current worst does any
more work. Same output — identical players per snapshot, identical bytes — for **half
the CPU**:

| 300 clustered | sort | heap |
|---|---:|---:|
| avg tick | 49.4 ms | **23.1 ms** |
| p95 tick | 55.3 ms | **25.6 ms** |
| resident | 72.9 MB | 73.1 MB |

The ranks live in a `Float64List`, not a `List<double>`. A growable `List<double>` boxes
every value it holds, and at over a million ranks a second that cost 20 MB of resident
memory for nothing — caught only because the profiler records memory alongside latency.

Two earlier wins still in force: rounding snapshot coordinates to whole world units
halved outbound bandwidth, and full player metadata travels once — when somebody
appears — rather than fifteen times a second.

### Capacity and the levers

**Comfortable at 300 concurrent**, clustered, with 65% tick headroom. Beyond that is
unmeasured here: the load tester saturates a single isolate before the server does.

What breaks first is not the server. It is the **cold load on venue wifi** — ~2.3 MB
gzipped, of which 1.47 MB is the CanvasKit renderer, which is ~18 s on a saturated
1 Mbit/s link, for everybody at once, at 09:30. The renderer is immutable and cached, so
putting the URL on the badge the day before is a real mitigation.

If the server does become the problem, both levers are environment variables and need a
restart rather than a rebuild:

| symptom | lever | effect |
|---|---|---|
| everyone choppy, server tick fine → the pipe | `TICK_HZ=10` | −29% bandwidth and CPU. Pair with raising the client's interpolation delay to ~150 ms. |
| the same, or `tickOverruns` climbing | `NEIGHBOUR_CAP=24` | −34% bandwidth. Degrades the far edge of the view, not the frame rate. |

Set `METRICS_CSV` for the event and the whole day becomes one chart. Watch `/metrics`
for exactly two things: `tickOverruns` above zero, and `residentBytes` rising while
`players` is flat.

## Contributing

Issues and pull requests welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the
setup (the `fvm` pin and `melos bootstrap` are both load-bearing) and for the three
architectural rules a change is expected to respect.

Found a security problem? Please do not open a public issue —
[SECURITY.md](SECURITY.md) has the private reporting route, the scope, and the list
of trade-offs that are deliberate rather than bugs.

## License

MIT — see [LICENSE](LICENSE).

One file, `server/lib/src/web_socket_upgrade.dart`, adapts code from
`package:shelf_web_socket` under the BSD-3-Clause licence. Its full terms are
reproduced in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
