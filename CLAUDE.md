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
