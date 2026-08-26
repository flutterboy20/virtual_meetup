# Contributing

Thanks for looking. Issues and pull requests are both welcome.

## Setup

The Flutter version is **pinned** in `.fvmrc`, and the repo is a Dart pub
workspace driven by [melos](https://melos.invertase.dev). Both matter: a
mismatched SDK or a plain `flutter pub get` in one package will not resolve the
workspace correctly.

```bash
git clone https://github.com/flutterboy20/virtual_meetup.git
cd virtual_meetup

fvm install                         # installs the pinned Flutter SDK
fvm exec dart run melos bootstrap   # resolves all four packages together
```

`fvm exec` puts the pinned SDK on `PATH`, which is how melos finds `dart` and
`flutter`. If `flutter test` fails immediately in a fresh clone, this is almost
always the step that was skipped.

## The checks CI runs

Run the whole set exactly as CI does:

```bash
fvm dart run melos run ci --no-select
```

Or individually:

```bash
fvm dart run melos run format          # dart format --set-exit-if-changed
fvm dart run melos run analyze         # Dart-only packages
fvm dart run melos run analyze:flutter # Flutter packages
fvm dart run melos run test
fvm dart run melos run test:flutter
```

`analyze` runs with `--fatal-infos --fatal-warnings` under
[`very_good_analysis`](https://pub.dev/packages/very_good_analysis). **Zero
warnings** is the standard, not a goal.

A pull request is expected to be green on all five before review.

## Running it locally

See [Run locally](README.md#run-locally) in the README. The short version:

```bash
cd server && ALLOWED_ORIGINS='*' fvm dart run bin/server.dart
cd client && fvm flutter run -d chrome
```

`ALLOWED_ORIGINS='*'` is required for a browser to connect, and is deliberately
not the default — see [Configuration](README.md#configuration).

## Three architectural rules

These are not style preferences. A pull request that breaks one of them will be
asked to change, so it is worth knowing them before you start.

**1. The server is a relay, not a simulator.** Clients own their own position.
They send it up; the server culls and rebroadcasts. There is no server-side
movement physics, no prediction, and no lag compensation. The worst case of a
client lying is somebody teleporting their own character, which is harmless for
a social toy, and accepting that is what keeps the server cheap enough to run a
few hundred people on one small box.

**2. Wire messages are defined once, in `protocol/`.** Both `client/` and
`server/` import them from there. Never redefine a message shape in two places,
and never put a message type anywhere else. `protocol/` has no Flutter
dependency, which is what makes this possible — please keep it that way.

**3. Interest management is how this scales.** Each client receives only the
players near it, capped at a maximum number of neighbours per snapshot.
Anything that broadcasts to every connected client, however small, needs a
reason.

## Style

- Match the file you are editing. Read its neighbours first.
- Public APIs get doc comments. The existing ones explain **why** a thing is
  the way it is, not what the code plainly says — that is the house style and
  it is worth continuing.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org):
  `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`.

## Tests

Anything with logic in it needs tests, in the same package. There are close to
1,500 across the four packages — 254 in `protocol`, 485 in `server`, 691 in
`client`, 69 in `tool/loadtest` — and the whole suite runs in seconds. There is
no excuse budget here.

Tests are named as sentences describing the behaviour rather than the method
(`a kicked join stops the client from walking back in`), grouped by the
behaviour under test. Please follow that.

## Reporting a security problem

Do not open a public issue. See [SECURITY.md](SECURITY.md).

## Licensing

Contributions are accepted under the [MIT License](LICENSE), the same terms as
the rest of the project. If you adapt code from elsewhere, say so in the file
and add it to [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
