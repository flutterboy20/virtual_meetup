# Deploying

One VM, one origin, two containers: Caddy terminates TLS and serves the Flutter
bundle; the Dart relay sits behind it on a private network and is never published
to the host.

```
browser ──https/wss──▶ Caddy :80 :443 ──▶ relay :8080 ──▶ /data
                       (TLS, static app)   (private)      config · bans · audit
```

Everything here is committed except `.env`, `data/` and `web/`, which exist only
on the server.

---

## 1. The VM

Any always-on Linux box with a public IPv4 and Docker. For an Oracle Cloud Always
Free A1 instance, two things bite in this order:

- **Create it in your home region.** Always Free compute can only be created
  there, it is chosen at signup, and it cannot be changed afterwards.
- **A1 capacity is frequently unavailable** in Indian regions, and Always Free
  reclaims idle instances. Create the VM weeks early, and treat step 2 as a
  script you can re-run rather than an afternoon you spent once.

Open TCP 22, 80 and 443. **Do not open 8080** — nothing outside the VM should
reach the relay directly.

> **The Oracle gotcha that eats an afternoon.** Opening the ports in the OCI
> Security List is not enough. Oracle's Ubuntu images ship iptables rules that
> drop everything except 22, baked into the image and independent of the cloud
> firewall. If Let's Encrypt fails with a connection timeout and the Security
> List looks right, this is why:
>
> ```bash
> sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
> sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
> sudo netfilter-persistent save
> ```

## 2. Prepare the box

```bash
sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2 git
sudo systemctl enable --now docker          # survives a reboot

sudo mkdir -p /opt/virtual-conference
sudo chown "$USER":"$USER" /opt/virtual-conference
git clone <repo-url> /opt/virtual-conference
cd /opt/virtual-conference/deploy

mkdir -p data web
cp .env.example .env
```

`systemctl enable docker` plus `restart: unless-stopped` in the compose file is
the whole of process supervision. No systemd unit of our own: Docker already
restarts a crashed container and already starts on boot, and a second supervisor
on top of that is one more thing to get wrong at 09:00.

## 3. Fill in `.env`

Every variable is documented in `.env.example`. The three that must be right:

```bash
openssl rand -base64 32          # -> ADMIN_TOKEN
```

- `ADMIN_TOKEN` — 16 chars minimum or the server refuses to start. Absent means
  moderation is **off**, not open.
- `ALLOWED_ORIGINS` — `https://your-host`, scheme and host, no trailing slash.
  Unset refuses every browser.
- `SITE_DOMAIN` — the same host **without** the scheme. Caddy issues the
  certificate for this name.

## 4. Ownership of the data directory

The relay runs as uid 10001, not root:

```bash
sudo chown -R 10001:65534 data
```

Skip this and the first ban throws on write. That is deliberate — a loud failure
beats a ban list that silently never persisted.

## 5. DNS before TLS

Point the hostname at the VM's public IP and confirm it resolves **before**
starting Caddy. Certificate issuance is an HTTP request to that name on port 80;
if it does not resolve yet, Caddy retries into a rate limit.

```bash
dig +short your-host.duckdns.org      # must print the VM's IP
```

## 6. Start

```bash
docker compose up -d --build
docker compose logs -f
```

Caddy obtains the certificate on its own. Then:

```bash
curl https://your-host/health         # -> Hello from protocol v5
curl https://your-host/metrics        # -> live numbers as JSON
```

## 7. The client

The bundle is built **elsewhere** and uploaded into `deploy/web/`, because the
server URL is compiled into it:

```bash
cd client
fvm flutter build web --release \
  --dart-define=SERVER_URL=wss://your-host/ws

grep -c "localhost:8080" build/web/main.dart.js    # MUST print 0
rsync -az --delete build/web/ user@host:/opt/virtual-conference/deploy/web/
```

That grep is not paranoia. Forgetting the flag still builds, and ships a bundle
that dials `ws://localhost:8080/ws` forever — the app loads, the art renders, the
front door shows its built-in copy, and nobody can join.

The GitHub Actions workflow (`.github/workflows/deploy.yml`) does all of the
above and fails the build on that grep. It is `workflow_dispatch` only: a merge
to main must never restart the server underneath a room full of people.

Repository secrets it needs: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`.
Repository variable: `SITE_DOMAIN`. The admin token is **not** among them — it
lives only on the VM.

---

## Running it

```bash
docker compose ps                       # what is up
docker compose logs -f relay            # the relay's own log
docker compose restart relay            # picks up an .env change
docker compose up -d --build relay      # picks up new server code
```

`.env` is read at process start, so every knob in it is a **restart, not a
rebuild** — including the two Phase 7 emergency levers, `TICK_HZ=10` and
`NEIGHBOUR_CAP=24`.

Back up before every deploy:

```bash
tar czf ~/vc-backup-$(date +%F-%H%M).tgz -C /opt/virtual-conference/deploy data
```

## Moderation

`https://your-host/#og-route` — a URL **fragment**, which the browser never sends
to a server. The path form `/og-route` does not work: that path belongs to the
admin WebSocket, and Caddy proxies it to the relay.

The token is asked for on every page load and held in memory only.

## When something is wrong

| Symptom | Look at |
|---|---|
| Site loads, nobody can join | `ALLOWED_ORIGINS` — does it match the browser's origin exactly, lowercase, no trailing slash? |
| Everyone alone in an empty world | The bundle points at localhost. Re-run the grep in step 7. |
| Front door shows the built-in copy, count reads 0 | `/config` is not reachable — the client answers every failure with defaults by design. `curl https://your-host/config`. |
| Certificate never issues | DNS, then port 80, then the iptables note in step 1. |
| Sockets fail with 400 | Something turned on h2c to the upstream. The upgrade handler accepts HTTP/1.1 only. |
| Bans vanish on redeploy | `data/` is not mounted, or is not owned by 10001. |
| Relay restarts in a loop | `docker compose logs relay`. A bad value in `.env` throws at startup on purpose. |
