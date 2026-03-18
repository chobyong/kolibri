# HIM Education Server — System Specification

> Auto-discovered: 2026-03-17
> Hostname: **HIM-010** | OS: **Debian GNU/Linux 13 (trixie)** | Arch: amd64

---

## 1. Hardware & Storage

| Item | Value |
|------|-------|
| Root disk | /dev/sda — 476.9 GB SSD |
| EFI partition | /dev/sda1 — 976 MB, vfat, UUID `7AB5-ECBB` |
| Root partition | /dev/sda2 — 460.2 GB, ext4, UUID `0b1e17d3-49b6-42d6-b5ec-7bbc0ed41497` |
| Swap | /dev/sda3 — 15.8 GB, UUID `d070495b-5f81-4e0c-a918-c7ae8b85f339` |
| Disk usage | 258 GB used / 452 GB total (61%) |

---

## 2. Network Interfaces

| Interface | Role | Address |
|-----------|------|---------|
| `enp1s0` | Upstream ethernet (DHCP) | 10.0.1.108/24, GW 10.0.1.1 |
| `wlp2s0` | Wi-Fi AP (hotspot) | 10.42.0.1/24 (static) |
| `docker0` | Docker default bridge | 172.17.0.1/16 |
| `br-61f471462265` | Docker `cloud` network | 172.18.0.1/16 |
| `tailscale0` | Tailscale VPN | 100.81.19.10/32 |

### /etc/network/interfaces
Minimal — only loopback. All other interfaces managed by NetworkManager / scripts.

---

## 3. Users & Authentication

| User | UID | Groups | Shell |
|------|-----|--------|-------|
| `him` | 1000 | him, docker, sudo (via sudoers) | /bin/bash |

### SSH (`/etc/ssh/sshd_config`)
- Default config; `KbdInteractiveAuthentication no`
- `UsePAM yes`, `X11Forwarding yes`
- Password authentication enabled (default)
- Subsystem: sftp via `/usr/lib/openssh/sftp-server`
- `AcceptEnv LANG LC_* COLORTERM NO_COLOR`

---

## 4. Wi-Fi Access Point — hostapd

Configuration generated dynamically by `start_ap.sh` / `him-ap.service`:

```
interface=wlp2s0        # auto-detected at runtime
driver=nl80211
ssid=him-edu
hw_mode=g
channel=6
ieee80211n=1
auth_algs=1
wpa=2
wpa_passphrase=1234567890
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
```

- **AP IP:** 10.42.0.1/24
- **SSID:** him-edu
- **Passphrase:** 1234567890
- **Security:** WPA2-PSK (CCMP)
- **Band:** 2.4 GHz, channel 6

`/etc/default/hostapd` — system hostapd daemon is **disabled** (managed manually).

---

## 5. DHCP & DNS — dnsmasq

Generated dynamically at runtime:

```ini
interface=wlp2s0
bind-interfaces
except-interface=lo
listen-address=10.42.0.1
dhcp-range=10.42.0.10,10.42.0.254,255.255.255.0,12h
dhcp-option=3,10.42.0.1      # default gateway
dhcp-option=6,10.42.0.1      # DNS server
address=/#/10.42.0.1          # wildcard DNS → portal IP
log-queries
log-dhcp
```

System dnsmasq service is **disabled** (managed manually via pid file `/run/him-dnsmasq.pid`).

---

## 6. Walled Garden — iptables

All client traffic is intercepted and confined to the local server.

```
FORWARD policy: DROP

NAT PREROUTING (on wlp2s0):
  UDP/TCP :53  → DNAT 10.42.0.1:53   (catch hardcoded DNS)
  TCP     :80  → DNAT 10.42.0.1:80   (HTTP → captive portal)
  TCP     :443 → DNAT 10.42.0.1:443  (HTTPS → captive portal)
```

Script: `/opt/him-edu/iptables_rules.sh apply|clear [IFACE] [AP_IP]`

---

## 7. Captive Portal — server.py

Python3 `ThreadingHTTPServer` serving `www/index.html` on both HTTP (:80) and HTTPS (:443).

- Every GET/POST/HEAD returns the landing page (no redirects needed — DNS already points everywhere to 10.42.0.1)
- Self-signed TLS certificate auto-generated via openssl (`ssl/cert.pem`, `ssl/key.pem`)
- No-cache headers prevent stale portal pages
- Landing page links: Kolibri → `http://10.42.0.1:8080/`, NextCloud → `http://10.42.0.1:8081/`

---

## 8. Kolibri Learning Platform

| Item | Value |
|------|-------|
| Version | 0.19.2 |
| Port | 8080 |
| Init system | SysVinit (`/etc/init.d/kolibri`) |
| Service | `kolibri.service` — enabled, active |
| Install method | `.deb` package from learningequality.org |
| Data directory | `/var/kolibri` (default) |

---

## 9. NextCloud Docker Stack

Compose file: `/opt/him-edu/nextcloud/docker-compose.yml`
All volumes under: `/opt/him-edu/nextcloud/`

| Container | Image | Ports | Role |
|-----------|-------|-------|------|
| `nextcloud` | nextcloud | 8081→80 | App server (Apache) |
| `nextcloud-db` | mariadb | — | Database |
| `redis` | redis:alpine | — | Cache |
| `collabora` | collabora/code | 9980→9980 | Online Office |
| `nginx-proxy` | jc21/nginx-proxy-manager | 81→81 | Reverse proxy admin |

### Environment Variables
```
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
MYSQL_PASSWORD=dbpassword
MYSQL_HOST=nextclouddb
REDIS_HOST=redis
TZ=America/Los_Angeles
```

### NextCloud Configuration
```
Admin user:     admin
Admin password: admin123
Trusted domain: 10.42.0.1:8081
CLI URL:        http://10.42.0.1:8081
```

### Installed Apps
| App | Version |
|-----|---------|
| calendar | 6.2.1 |
| notes | 4.13.0 |
| richdocuments (NextCloud Office) | 10.1.0 |

### Collabora (NextCloud Office)
```
WOPI URL:     http://collabora:9980
Public WOPI:  http://10.42.0.1:9980
Domain allow: 10.42.0.0/24, 172.18.0.0/16
SSL:          disabled (plain HTTP)
```

### Volume Directories
```
/opt/him-edu/nextcloud/
├── html/           nextcloud web root
├── custom_apps/    installed apps
├── config/         config.php and friends
├── data/           user files
├── nextclouddb/    mariadb data
├── redis/          redis persistence
├── npm-data/       nginx proxy manager data
└── letsencrypt/    certs (unused offline)
```

---

## 10. Systemd Services

| Service | Unit file | Function |
|---------|-----------|----------|
| `him-ap.service` | /etc/systemd/system/ | Start hostapd + dnsmasq |
| `him-firewall.service` | /etc/systemd/system/ | Apply iptables walled garden |
| `him-webserver.service` | /etc/systemd/system/ | Start captive portal server.py |
| `walled-garden.service` | /etc/systemd/system/ | All-in-one via start_ap.sh |
| `kolibri.service` | sysvinit + systemd shim | Kolibri learning platform |
| `docker.service` | docker package | Docker daemon |
| `tailscaled.service` | tailscale package | Tailscale VPN |

Service start order: `him-ap` → `him-firewall` → `him-webserver`

---

## 11. Scripts (`/opt/him-edu/` = `/home/him/kolibri/`)

| Script | Purpose |
|--------|---------|
| `start_ap.sh` | Start walled garden (hostapd, dnsmasq, iptables, server.py) |
| `stop_ap.sh` | Stop walled garden, restore NetworkManager |
| `iptables_rules.sh` | Apply/clear iptables walled garden rules |
| `server.py` | Python3 captive portal HTTP/HTTPS server |
| `install.sh` | Full automated installation (8 phases) |
| `setup-him-edu.sh` | Bootstrap: clone repo → install.sh → start |

---

## 12. Package Sources

```
# /etc/apt/sources.list — Debian trixie
deb http://deb.debian.org/debian trixie main non-free-firmware
deb http://security.debian.org/debian-security trixie-security main non-free-firmware
deb http://deb.debian.org/debian trixie-updates main non-free-firmware

# /etc/apt/sources.list.d/docker.list
deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable

# /etc/apt/sources.list.d/nodesource.sources
deb https://deb.nodesource.com/node_20.x nodistro main

# /etc/apt/sources.list.d/tailscale.list
deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/debian trixie main
```

---

## 13. Installed Packages (key)

```
git, curl, wget
hostapd, dnsmasq
iptables, iptables-persistent
python3, openssl, iw
docker-ce (or docker.io), docker-compose-plugin
kolibri 0.19.2 (deb)
tailscale
network-manager
```

---

## 14. Locale & Time

| Setting | Value |
|---------|-------|
| Locale | en_US.UTF-8 |
| Timezone | America/Los_Angeles (TZ in Docker containers) |

---

## 15. Architecture Diagram

```
Internet
    │
    │ (upstream DHCP)
    ▼
[enp1s0: 10.0.1.108]
    │
[HIM-010 Server]
    │
[wlp2s0: 10.42.0.1]  ← Wi-Fi AP "him-edu" (WPA2)
    │
    ├─ dnsmasq :53  → 10.42.0.1 (all DNS → portal)
    ├─ server.py :80/:443  → captive portal / landing page
    ├─ kolibri :8080        → learning platform
    └─ nextcloud :8081      → file sharing
           │
           └─ Docker: nextcloud + mariadb + redis + collabora + nginx-proxy
```
