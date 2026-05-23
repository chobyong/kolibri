# HIM Education — Developer Guide (CLAUDE.md)

## Project Overview

Self-contained offline educational server for HIM (Heaven In Me) ministry. Runs on a Linux box with a Wi-Fi NIC, creates a walled-garden hotspot (`him-edu`), and serves Kolibri + NextCloud to connected devices — no internet required. Also reachable remotely via Cloudflare tunnel at `heaveninme.us`.

## Key Files

| File | Purpose |
|------|---------|
| `server.py` | Python HTTP/HTTPS captive portal (port 80/443). Routes, static files, `/config` JSON endpoint, Kolibri API proxy |
| `portal-config.json` | Cloudflare hostname → service URL mapping. Reloaded live on each `/config` request |
| `iptables_rules.sh` | Walled garden firewall. Must ACCEPT Docker-DNAT (172.16/12) before DROP |
| `update-nc-trusted-domains.sh` | Rebuilds NextCloud trusted_domains with all current IPs + CF hostnames |
| `www/index.html` | Landing page. Fetches `/config` at load to get service URLs dynamically |
| `www/admin.html` | Bulk Kolibri user creator (students/coaches/admins via Kolibri API) |
| `www/browse.html` | Coach Lesson Builder |
| `channels.json` | Authoritative list of installed Kolibri channels for replication |
| `export-channel-list.sh` | Dumps installed channels from running Kolibri → `channels.json` |
| `import-kolibri-channels.sh` | Downloads channels into Kolibri (from file or by language group) |
| `classes-lessons.json` | Exported Kolibri classes and lesson playlists for replication |
| `export-classes-lessons.sh` | Dumps all classes + lessons from running Kolibri → `classes-lessons.json` |
| `import-classes-lessons.sh` | Creates classes and lessons on a new host from `classes-lessons.json` |

## Architecture Constraints

- **No HTTPS redirect in iptables** — only port 80 is intercepted. Port 443 is served by `server.py` with a self-signed cert to satisfy HTTPS-only clients, but is not force-redirected.
- **NextCloud is Docker** — lives at `172.17.x.x` internally. iptables must have `ACCEPT -d 172.16.0.0/12` before the `DROP` rule or wireless clients can't reach port 8081.
- **`/config` hostname logic** — three cases: (1) CF tunnel hostname → return CF URLs from `portal-config.json`; (2) IP address → return `http://<ip>:8080` / `http://<ip>:8081`; (3) random walled-garden domain → fall back to `ap_ip` (10.42.0.1). Case 3 happens when a client visits any internet URL and dnsmasq redirects it here.
- **All services run as root** — `server.py` binds to port 80/443. Git repo and all files in `/opt/him-edu` are owned by root.

## Systemd Services

| Service | What it does |
|---------|-------------|
| `him-ap.service` | hostapd + dnsmasq (Wi-Fi AP) |
| `him-firewall.service` | iptables walled garden rules |
| `him-webserver.service` | server.py (HTTP + HTTPS) |
| `him-nc-trust.service` | Update NextCloud trusted_domains on boot |
| `walled-garden.service` | All-in-one wrapper |

## Kolibri API Notes

The Kolibri REST API (v0.19) uses these base paths — **not** `/api/core/`:

| Purpose | Path |
|---------|------|
| Login (POST) | `/api/auth/session/` |
| Classrooms | `/api/auth/classroom/` |
| Lessons | `/api/lessons/lesson/` |
| Exams | `/api/exams/exam/` |
| Public channels | `/api/public/v1/channels/` |

Authentication requires a session cookie. Hit `/en/user/` first to get the CSRF cookie, then POST credentials to `/api/auth/session/`. The `X-CSRFToken` header is only needed if a CSRF cookie is present.

Lesson resources use stable `contentnode_id` values (content-addressed) that are identical across Kolibri instances for the same channel version. Classes/lessons can therefore be replicated to any host that has the same channels installed.

## Common Tasks

### Check if services are running
```bash
systemctl status him-ap him-firewall him-webserver him-nc-trust
```

### Restart the portal server
```bash
sudo systemctl restart him-webserver
```

### Update Cloudflare hostnames
Edit `portal-config.json` — changes take effect immediately (no restart).

### Fix NextCloud "untrusted domain" error
```bash
sudo /opt/him-edu/update-nc-trusted-domains.sh
```

### Fix ownership so `him` user can edit files
```bash
sudo chown -R him:him /opt/him-edu
```

### Export and replicate Kolibri channels to a new server
```bash
# On source server — update channels.json
/opt/him-edu/export-channel-list.sh

# On new server — download the same channels
sudo /opt/him-edu/import-kolibri-channels.sh from-file /opt/him-edu/channels.json
```

### Export and replicate classes and lessons to a new server
```bash
# On source server — update classes-lessons.json
/opt/him-edu/export-classes-lessons.sh

# On new server — create the same classes and lessons
sudo /opt/him-edu/import-classes-lessons.sh /opt/him-edu/classes-lessons.json
```

> Channels must be imported before lessons (lessons reference content by channel/node ID).
> Both import scripts are idempotent — safe to re-run; they skip anything that already exists.

### Commit and push as root
```bash
sudo git -C /opt/him-edu add -A
sudo git -C /opt/him-edu commit -m "message"
sudo git -C /opt/him-edu push
```

## Credentials

All apps use the same credentials:
- **Username:** `him`
- **Password:** `ABCD_1234`

Wi-Fi: SSID `him-edu`, password `1234567890`

## Cloudflare Tunnel (heaveninme.us)

| CF Hostname | Routes to |
|-------------|-----------|
| `edu-portal.heaveninme.us` | portal (server.py :80) |
| `kolibri.heaveninme.us` | Kolibri :8080 |
| `nextcloud.heaveninme.us` | NextCloud :8081 |

## Git Workflow Notes

- Repo is at `/opt/him-edu`, owned by root.
- Either run git as `sudo git -C /opt/him-edu ...` or fix ownership first with `sudo chown -R him:him /opt/him-edu`.
- Remote: `https://github.com/chobyong/kolibri.git`
