# syntax=docker/dockerfile:1
#
# The relay server, AOT-compiled. Build context is the REPOSITORY ROOT, not
# this directory:
#
#   docker compose -f deploy/docker-compose.yml build
#
# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
# `dart:stable` rather than a pinned tag because a wrong pin is a build that
# fails on the day. The one hard requirement is Dart >= 3.13 — both pubspecs
# declare `sdk: ^3.13.0`, and an older image fails at `pub get` with a version
# solve error rather than anything subtle. Pin this to the exact tag once the
# first successful deploy tells you which one that was.
FROM dart:stable AS build

WORKDIR /app

# Only the two packages the server actually needs. `client/` is deliberately
# absent — see below.
COPY protocol/ protocol/
COPY server/ server/

# **The pub workspace problem, and why this sed is here.**
#
# The repo root is a Dart pub workspace whose members are client, protocol,
# server and tool/loadtest. Pub resolves a workspace as one unit, so a
# `dart pub get` anywhere inside it resolves ALL FOUR — and `client` depends
# on the Flutter SDK. This image has no Flutter and should never have one, so
# the workspace cannot be used here at all.
#
# The fix is to make `server` a standalone package for the length of the
# build: drop the `resolution: workspace` line from both pubspecs, and point
# `protocol` at its sibling directory with an override. Nothing in the repo
# changes; this rewrite happens only inside the image.
#
# Verified locally against the repo's pinned Dart 3.13.0: `pub get` resolves
# 48 dependencies and `dart compile exe` produces a working binary.
RUN sed -i '/^resolution: workspace$/d' server/pubspec.yaml protocol/pubspec.yaml \
 && printf 'dependency_overrides:\n  protocol:\n    path: ../protocol\n' \
      > server/pubspec_overrides.yaml

WORKDIR /app/server
RUN dart pub get
RUN dart compile exe bin/server.dart -o /app/relay

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
# debian-slim rather than `scratch`, which the official Dart images support.
# `scratch` is smaller and has no shell — which is also why it cannot answer a
# container healthcheck, and why you cannot look at anything from inside it
# during an incident. For a one-day event, being able to exec into the box is
# worth more than the megabytes.
FROM debian:stable-slim AS runtime

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/relay /usr/local/bin/relay

# Not root. The relay opens a socket and writes three files; it needs nothing
# else. The uid is fixed rather than generated so the bind-mounted data
# directory can be chowned to a number that does not move between rebuilds:
#
#   sudo chown -R 10001:10001 deploy/data
#
# Forgetting that chown fails LOUDLY — the first ban throws on write — which
# is the intended trade. A silently unwritable ban list would be worse.
RUN useradd --system --uid 10001 --gid nogroup relay \
 && mkdir -p /data \
 && chown 10001:nogroup /data

USER 10001:nogroup
WORKDIR /data
VOLUME ["/data"]

# Container-internal only. Never published to the host: Caddy reaches it over
# the compose network. If you change this, PORT in .env, the compose
# healthcheck and the Caddyfile upstream all have to change with it.
EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/relay"]
