# Security policy

This is a real-time WebSocket server that is meant to be put on a public URL
for the length of an event, with a few hundred strangers connected to it. That
is the threat model, and reports about it are welcome.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting: the **Security** tab of this
repository → **Report a vulnerability**. That opens a private thread visible
only to the maintainer.

Please include what you were able to do, the steps to reproduce it, and the
commit or version you tested against. A proof of concept against **your own**
local server is ideal.

This is a hobby project maintained by one person, so there is no guaranteed
response time. Expect a reply within about a week.

## Scope

In scope — the interesting ones first:

- Anything that lets one client **crash, hang or exhaust** the server: the
  frame guards, the token buckets, the connection gate, the tick loop.
- Anything that lets a client **act as another client**, forge a session, or
  bypass a ban or a kick.
- Anything that reaches the **moderation surface** without the admin token, or
  that leaks the token.
- Anything that lets one client **read another client's** data beyond what the
  relay is meant to broadcast.
- Path traversal or unintended file access via the config, ban or audit paths.

Out of scope, because they are **known, documented, deliberate** trade-offs:

- **A client lying about its own position.** The server is a relay, not a
  simulator: clients own their position, and the worst case is somebody
  teleporting their own character. Accepted by design.
- **Bans keyed on a session id in browser storage.** Clearing storage produces
  a new id. This is a tool for removing a disruption in ten seconds, not an
  access control system.
- **The moderation route being discoverable.** `/#og-route` is compiled into
  the shipped bundle and can be read out of the JavaScript. Opening it grants
  nothing; every action behind it is refused until a valid token arrives.
- **`Origin` pinning not stopping non-browser clients.** A request with no
  `Origin` header passes, which is what keeps the load tester working. Origin
  pinning stops a hostile web page using its visitors' browsers; the socket
  cap is what limits everything else.
- Reports from automated scanners with no demonstrated impact.

## Deploying this safely

If you are running your own instance, the following are not optional. All of
them are documented in [`deploy/`](deploy/README.md) and
[`deploy/.env.example`](deploy/.env.example):

- **`wss://` only.** The admin token crosses the wire inside a WebSocket
  frame; over plaintext anyone on the same wifi can read it.
- **`ADMIN_TOKEN` from the host's secret store**, never a committed file,
  never a `--dart-define`, never a URL. Absent means moderation is *off*, not
  open.
- **`ALLOWED_ORIGINS` set to your real origin.** Unset refuses every browser,
  which is deliberate: it fails loudly rather than leaving a server open to
  the whole web.
- **A memory ceiling on the process** (`DART_VM_OPTIONS`), and a container
  memory limit above it.
- **`BAN_FILE` and `AUDIT_FILE` on a persistent disk**, or every ban silently
  becomes a kick on the next redeploy.

## What this project collects

No accounts, no email addresses, no passwords. A player supplies a display
name and gets a random session id kept in their browser's local storage. The
server holds name, colour, character and position in memory for the length of
the session, and broadcasts them to nearby players — that is the whole point
of the app. Bans persist a session id and a moderator note; the audit log
records moderator actions.
