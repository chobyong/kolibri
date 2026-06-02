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
| `start_ap.sh` | Start walled garden (hostapd + dnsmasq + iptables + server.py) |
| `stop_ap.sh` | Stop walled garden and restore NetworkManager |
| `www/index.html` | Landing page. Fetches `/config` at load to get service URLs dynamically |
| `www/admin.html` | Bulk Kolibri user creator (students/coaches/admins via Kolibri API) |
| `www/browse.html` | Coach Lesson Builder |
| `channels.json` | Authoritative list of installed Kolibri channels for replication |
| `export-channel-list.sh` | Dumps installed channels from running Kolibri → `channels.json` |
| `import-kolibri-channels.sh` | Downloads channels into Kolibri (from file or by language group) |
| `classes-lessons.json` | Exported Kolibri classes and lesson playlists for replication |
| `export-classes-lessons.sh` | Dumps all classes + lessons from running Kolibri → `classes-lessons.json` |
| `import-classes-lessons.sh` | Creates classes and lessons on a new host from `classes-lessons.json` |

## USB Wi-Fi NIC & AP Configuration

### Hardware

| Interface | Role | Notes |
|-----------|------|-------|
| `wlx00c0cabb67ce` | USB Wi-Fi adapter — runs the AP | `wlx` prefix = USB; chipset: **mt7921u** |
| `wlp1s0` | Internal Wi-Fi card — **disabled** while AP is active | Conflicts with hostapd; set unmanaged + down in `start_ap.sh` |

### AP Startup Order (critical — do not change)

The mt7921u chipset requires a specific sequence or `NL80211_CMD_START_AP` fails:

1. `iw reg set US` — set regulatory domain **first**; world reg (`00`) caps TX power to 3 dBm and silently prevents beaconing even though hostapd daemonizes successfully.
2. `nmcli device set wlx… managed no` — remove from NetworkManager.
3. `ip link set wlx… down` + `ip addr flush` — interface must be **DOWN in managed mode** when hostapd starts; bringing it UP first causes "Failed to set beacon parameters".
4. `hostapd` starts and owns the AP setup (brings interface UP itself).
5. Wait up to 30 s for interface to reach state UP.
6. `ip addr add 10.42.0.1/24` — assign IP only **after** hostapd has the interface UP.
7. `pkill dnsmasq; dnsmasq` — kill any stale dnsmasq first to avoid port 53 conflict.
8. `exec sleep infinity` — keeps `walled-garden.service` CGroup alive so systemd tracks all child processes (hostapd, dnsmasq, server.py).

### Conflict Resolution

| Conflict | Symptom | Fix |
|----------|---------|-----|
| NetworkManager takes back the interface | hostapd loses AP after a short time | `nmcli device set $IFACE managed no` before starting |
| Internal card (`wlp1s0`) competes | hostapd starts on wrong interface | `nmcli device set wlp1s0 managed no && ip link set wlp1s0 down` |
| Interface UP before hostapd | `NL80211_CMD_START_AP` fails; "Failed to set beacon parameters" | Leave interface DOWN; let hostapd bring it up |
| World regulatory domain | hostapd starts but no clients can connect (TX power 3 dBm, no beaconing) | `iw reg set US` as the very first step |
| Port 53 already in use | dnsmasq fails to start | `pkill dnsmasq` before `dnsmasq` in startup |
| `systemd-resolved` on port 53 | dnsmasq fails with "address in use" | `sudo systemctl stop systemd-resolved` |
| him-ap / him-firewall / him-webserver vs walled-garden | Two services fight over the adapter | Those `.service` files are `.disabled`; use `walled-garden.service` only |
| CGroup lost on boot | `systemctl status walled-garden` shows "inactive" immediately after start | `start_ap.sh` ends with `exec sleep infinity`; service is `Type=simple` |
| NextCloud container not ready at boot | `him-nc-trust` fails to update trusted_domains | Wait loop in `update-nc-trusted-domains.sh` is 60 s |

## Architecture Constraints

- **No HTTPS redirect in iptables** — only port 80 is intercepted. Port 443 is served by `server.py` with a self-signed cert to satisfy HTTPS-only clients, but is not force-redirected.
- **NextCloud is Docker** — lives at `172.17.x.x` internally. iptables must have `ACCEPT -d 172.16.0.0/12` before the `DROP` rule or wireless clients can't reach port 8081.
- **`/config` hostname logic** — three cases: (1) CF tunnel hostname → return CF URLs from `portal-config.json`; (2) IP address → return `http://<ip>:8080` / `http://<ip>:8081`; (3) random walled-garden domain → fall back to `ap_ip` (10.42.0.1). Case 3 happens when a client visits any internet URL and dnsmasq redirects it here.
- **All services run as root** — `server.py` binds to port 80/443. Git repo and all files in `/opt/him-edu` are owned by root.

## Systemd Services

| Service | What it does |
|---------|-------------|
| `walled-garden.service` | **Primary** — all-in-one (start_ap.sh / stop_ap.sh); `Type=simple` |
| `him-ap.service` | hostapd + dnsmasq only (disabled — use walled-garden instead) |
| `him-firewall.service` | iptables walled garden rules (disabled) |
| `him-webserver.service` | server.py (HTTP + HTTPS) (disabled) |
| `him-nc-trust.service` | Update NextCloud trusted_domains on boot |

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
systemctl status walled-garden him-nc-trust
```

### Restart the walled garden
```bash
sudo systemctl restart walled-garden
```

### Restart only the portal server
```bash
sudo pkill -f server.py
sudo nohup python3 /opt/him-edu/server.py > /opt/him-edu/server.log 2>&1 &
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
