HIM Education — Walled Garden Server
=====================================

A self-contained offline educational server. It broadcasts a Wi-Fi hotspot
(`him-edu`) and redirects all connected wireless clients to a landing page
with links to **Kolibri**, **NextCloud**, and a coach **Lesson Builder** — no internet required.

The same server is also accessible remotely through a **Cloudflare tunnel** at `heaveninme.us`.

| Setting        | Value                                        |
|----------------|----------------------------------------------|
| SSID           | `him-edu`                                    |
| Password       | `1234567890`                                 |
| AP IP          | `10.42.0.1`                                  |
| Portal (HTTP)  | `http://10.42.0.1`                           |
| Portal (HTTPS) | `https://10.42.0.1` (self-signed cert)       |
| Kolibri        | `http://10.42.0.1:8080`                      |
| Lesson Builder | `http://10.42.0.1/browse`                    |
| User Manager   | `http://10.42.0.1/admin`                     |
| NextCloud      | `http://10.42.0.1:8081`                      |
| CF Portal      | `https://edu-portal.heaveninme.us`           |
| CF Kolibri     | `https://kolibri.heaveninme.us`              |
| CF NextCloud   | `https://nextcloud.heaveninme.us`            |

---
- username : him , password: ABCD_1234 for all application, admin console, etc.

Quick Start — Full Installation
--------------------------------

### Step 1 — Install the OS

- Install **Debian 12** (or Ubuntu Server). Create a user (e.g., `him`) with sudo access.
- Debian or Ubuntu install will prompt for `root` and a user name `him`, password to be ABCD_1234
- initial OS install will prompt for host name is him-xxx , xxx is sequential numeric value that is unique per server
- During installation you will be prompted to select which services to enable. Check **SSH server** and leave **web server** unchecked, as shown below:

  > Check `SSH server` ✓  — leave `web server` unchecked

```bash
su - #password to be ACBD_1234
usermod -aG sudo him
# log out and log back in to server
```
### Step 2 — Clone and Run
- run command from him user, NOT a root user for the rest of command.
- run this script while server is connected to Internet using `Ethenet port`, Wireless NIC will be converted to access point during setup.
```bash
sudo apt-get update && sudo apt-get install -y git curl
curl -fsSL -o /tmp/setup-him-edu.sh https://raw.githubusercontent.com/chobyong/kolibri/main/setup-him-edu.sh
sudo chmod +x /tmp/setup-him-edu.sh
sudo /tmp/setup-him-edu.sh
```

Or manually:
```bash
sudo rm -rf /opt/him-edu
sudo git clone https://github.com/chobyong/kolibri.git /opt/him-edu
cd /opt/him-edu
chmod +x install.sh
sudo ./install.sh
```

The `install.sh` script handles **everything** in one run:

1. **Prerequisites** — Installs git, curl, hostapd, dnsmasq, iptables, python3, openssl, iw
2. **Docker** — Installs Docker + Compose, adds your user to the `docker` group
3. **Kolibri** — Installs from local `.deb` or downloads automatically
4. **NextCloud** — Starts Docker stack, runs initial setup, installs Calendar, Notes, and NextCloud Office (Collabora)
5. **Walled Garden** — Sets scripts executable, installs systemd services
6. **Verification** — Checks all components are running

### Step 3 — Import Kolibri Channels

Connect the server to Ethernet (internet required), then run:

```bash
# English channels only (~270 GB):
sudo /opt/him-edu/import-kolibri-channels.sh english

# Spanish channels only (~140 GB):
sudo /opt/him-edu/import-kolibri-channels.sh spanish

# Both languages (~410 GB — check disk space first: df -h):
sudo /opt/him-edu/import-kolibri-channels.sh all
```

> **Note:** Channels are not imported automatically by `setup.sh`. Run this step manually after installation to load content into Kolibri.

### Step 4 — (Optional / Troubleshooting) Start the Walled Garden

> **Note:** `setup.sh` handles all remaining steps automatically. Steps 4 and beyond are only needed for manual troubleshooting or re-configuration.

```bash
sudo ./start_ap.sh
```

### Step 5 — (Optional / Troubleshooting) Enable on Boot

```bash
sudo systemctl enable walled-garden
```

### Step 6 — Test

1. Connect to Wi-Fi `him-edu` (password: `1234567890`)
2. A captive portal page should appear automatically
3. If not, open `http://neverssl.com` in a browser
4. The landing page shows buttons for Kolibri, Lesson Builder, and NextCloud

---

How It Works
------------

### Architecture

```
 Client device (phone/laptop)
     │
     ├─ Connects to Wi-Fi "him-edu" (WPA2, password: 1234567890)
     │
     │   ┌──────────── HIM Education Server ────────────┐
     │   │                                               │
     ├──►│  hostapd         → Runs the Wi-Fi AP          │
     │   │  dnsmasq         → DHCP (10.42.0.10-254)      │
     │   │                    DNS (all domains→10.42.0.1) │
     │   │  iptables        → Docker ACCEPT (172.16/12)  │
     │   │                    FORWARD DROP (no internet) │
     │   │                    DNS + HTTP redirect to AP  │
     │   │  server.py       → Captive portal on :80 (HTTP)│
     │   │                    and :443 (HTTPS, self-signed)│
     │   │                    /config → service URL JSON  │
     │   │                                               │
     │   │  Kolibri         → Learning platform on :8080  │
     │   │  NextCloud       → File sharing on :8081       │
     │   └───────────────────────────────────────────────┘
     │
     └─ Client sees "HIM Education" landing page
        with buttons to Kolibri, Lesson Builder, User Manager, and NextCloud

 Remote access (internet required):
     Cloudflare Tunnel → edu-portal.heaveninme.us → portal
                       → kolibri.heaveninme.us    → Kolibri
                       → nextcloud.heaveninme.us  → NextCloud
```

### What each component does

1. **hostapd** — Creates the Wi-Fi access point (SSID: `him-edu`).
   The wireless interface is taken from NetworkManager and configured
   manually with IP `10.42.0.1/24`.

2. **dnsmasq** — Provides DHCP (assigns `10.42.0.x` addresses to clients)
   and DNS. The DNS wildcard rule `address=/#/10.42.0.1` resolves **every
   domain** to the portal IP, so any URL the client opens leads to the
   landing page.

3. **iptables** — Enforces the walled garden:
   - `FORWARD ACCEPT` for Docker-DNAT traffic (172.16.0.0/12) — allows clients to reach NextCloud on port 8081 (Docker rewrites the destination before FORWARD is checked).
   - `FORWARD DROP` — Clients cannot reach the internet.
   - DNS redirect (port 53 UDP/TCP) — Catches clients with hardcoded DNS
     (e.g. 8.8.8.8) and sends queries to our dnsmasq.
   - HTTP redirect (port 80) → captive portal.

4. **server.py** — A Python HTTP/HTTPS server.
   - Port 80 (HTTP): serves the captive portal and all pages.
   - Port 443 (HTTPS): same handler with a self-signed certificate (avoids browser errors for HTTPS-only clients).
   - `GET /config` → returns JSON with service URLs (Kolibri, NextCloud). If the request comes through a Cloudflare tunnel hostname, returns the CF URLs; if the Host is an IP, returns port-based local URLs; otherwise falls back to `ap_ip` (10.42.0.1).
   - `GET /browse` → `www/browse.html` (Lesson Builder).
   - `GET /admin` → `www/admin.html` (bulk user manager — add students/coaches/admins).
   - `/kolibri-api/*` → proxied to Kolibri on port 8080.
   - Static files in `www/` served by extension.

5. **Kolibri** (port 8080) — Offline learning platform with videos,
   exercises, and lessons. Clients access it directly at `http://10.42.0.1:8080`.

6. **NextCloud** (port 8081) — File sharing and collaboration platform.
   Accessed at `http://10.42.0.1:8081`.

7. **portal-config.json** — Configuration file for the `/config` endpoint.
   Maps Cloudflare tunnel hostnames to their respective service URLs.
   Also supports an `ap_ip` key to override the default `10.42.0.1`.
   The server reloads this file on every `/config` request — no restart needed after edits.

8. **him-nc-trust.service** — Systemd oneshot service that runs
   `update-nc-trusted-domains.sh` on boot (after network is up) to ensure
   NextCloud always accepts connections from all current server IP addresses
   and Cloudflare hostnames.

### What the scripts do

| Script                        | What it does                                                 |
|-------------------------------|--------------------------------------------------------------|
| `start_ap.sh`                 | Auto-detects the Wi-Fi interface, removes it from            |
|                               | NetworkManager, assigns IP 10.42.0.1, generates hostapd      |
|                               | and dnsmasq configs, starts hostapd → dnsmasq → iptables →  |
|                               | captive portal server.                                       |
| `stop_ap.sh`                  | Kills hostapd, dnsmasq, captive portal server. Clears        |
|                               | iptables rules. Returns the Wi-Fi interface to               |
|                               | NetworkManager.                                              |
| `iptables_rules.sh`           | Applies or clears the walled garden firewall rules. Adds     |
|                               | ACCEPT for Docker-DNAT (172.16/12) before DROP, then         |
|                               | intercepts DNS and HTTP only. Called by start/stop.          |
| `install.sh`                  | Full automated installation — installs all packages,         |
|                               | Docker, Kolibri, NextCloud, systemd services.                |
| `import-kolibri-channels.sh`  | Downloads Kolibri content channels from the internet.        |
|                               | Run once after installation while Ethernet is connected.     |
|                               | Usage: `sudo ./import-kolibri-channels.sh [english|spanish|all]` |
| `fix-kolibri.sh`              | Repairs Kolibri after a database reset or corruption.        |
|                               | Re-registers channels already on disk without re-downloading.|
|                               | Usage: `sudo bash fix-kolibri.sh`                            |
| `update-nc-trusted-domains.sh`| Rebuilds NextCloud `trusted_domains` with all current RFC    |
|                               | 1918 IPs plus fixed entries (localhost, 10.42.0.1,           |
|                               | nextcloud.heaveninme.us). Run automatically on boot via      |
|                               | `him-nc-trust.service`.                                      |
| `server.py`                   | Python captive portal web server. Serves the landing page    |
|                               | on HTTP (:80) and HTTPS (:443, self-signed), the Lesson      |
|                               | Builder at `/browse`, the User Manager at `/admin`, serves   |
|                               | static files from `www/`, proxies Kolibri API calls, and     |
|                               | exposes `/config` for dynamic service URL routing.           |

---

Usage
-----

### Start the walled garden

```bash
sudo ./start_ap.sh
```

### Stop the walled garden

```bash
sudo ./stop_ap.sh
```

### Enable auto-start on boot

**All-in-one (recommended):**
```bash
sudo systemctl enable walled-garden
```

**Or individual services:**
```bash
sudo systemctl enable him-ap him-firewall him-webserver him-nc-trust
```

### Check status

```bash
sudo bash /opt/him-edu/troubleshooting/check-status.sh
```

### Update Cloudflare tunnel hostnames

Edit `portal-config.json` to add or change Cloudflare tunnel hostnames:

```json
{
  "cloudflare_hosts": {
    "edu-portal.heaveninme.us": {
      "kolibri":   "https://kolibri.heaveninme.us",
      "nextcloud": "https://nextcloud.heaveninme.us"
    }
  }
}
```

The server reloads this file on every `/config` request — no restart needed.

---

File Structure
--------------

```
/opt/him-edu/
├── setup-him-edu.sh            # Bootstrap script (clones repo + runs install)
├── install.sh                  # Full installation script (run this first)
├── import-kolibri-channels.sh  # Download Kolibri content channels (english/spanish/all)
├── fix-kolibri.sh              # Repair Kolibri after database reset (no re-download needed)
├── start_ap.sh                 # Start the walled garden
├── stop_ap.sh                  # Stop the walled garden
├── iptables_rules.sh           # Firewall rules — Docker ACCEPT, then DROP, DNS+HTTP redirect
├── server.py                   # Captive portal web server (HTTP :80, HTTPS :443)
├── portal-config.json          # Cloudflare tunnel hostname → service URL mapping
├── hostapd.conf                # Wi-Fi access point config (generated by start_ap.sh)
├── hostapd.conf.tmpl           # Template for hostapd.conf (used by start_ap.sh)
├── dnsmasq.conf                # DHCP/DNS configuration
├── update-nc-trusted-domains.sh# Rebuild NextCloud trusted_domains on boot
├── www/
│   ├── index.html              # Landing page (hero photo, grouped service cards)
│   ├── browse.html             # Coach Lesson Builder (browse by grade/subject)
│   ├── admin.html              # Bulk user manager — create students/coaches/admins
│   └── hero.jpg                # Hero photo for the landing page
├── nextcloud/                  # NextCloud Docker stack
│   ├── docker-compose.yml      # NextCloud, MariaDB, Collabora, Redis, Nginx
│   ├── README.md               # NextCloud setup documentation
│   ├── config/                 # NextCloud runtime config
│   ├── custom_apps/            # Installed NextCloud apps
│   ├── data/                   # NextCloud user data
│   ├── html/                   # NextCloud web root
│   ├── letsencrypt/            # SSL certificate storage
│   ├── nextclouddb/            # MariaDB data volume
│   ├── npm-data/               # Nginx Proxy Manager data
│   └── redis/                  # Redis data volume
├── server-setup/               # Tools for building new servers (not used in normal operation)
│   ├── README.md               # What this folder is and how to use it
│   ├── build-iso.sh            # Build custom Debian installer ISO
│   ├── preseed.cfg             # Debian unattended install config
│   ├── provision.sh            # First-boot provisioning script
│   ├── docker-compose.yml      # Reference copy of NextCloud Docker stack
│   ├── deployment-guide.md     # Step-by-step deployment guide
│   ├── deployment-guide.pdf    # PDF version of deployment guide
│   └── SETUP.md                # Reference server (HIM-010) system spec
├── doc/                        # Detailed documentation
│   ├── 01-prerequisites.md
│   ├── 02-walled-garden.md
│   ├── 03-kolibri.md
│   └── 04-nextcloud.md
├── troubleshooting/            # Troubleshooting guides and diagnostic tools
│   ├── README.md               # Quick problem/solution table
│   ├── guide.md                # In-depth fixes for each component
│   └── check-status.sh         # Script to check all services at once
├── ssl/                        # Auto-generated self-signed TLS certificate (git-ignored)
│   ├── cert.pem
│   └── key.pem
├── him-ap.service              # Systemd: hotspot (hostapd+dnsmasq)
├── him-firewall.service        # Systemd: iptables rules
├── him-webserver.service       # Systemd: captive portal server (HTTP + HTTPS)
├── him-nc-trust.service        # Systemd: update NextCloud trusted_domains on boot
├── walled-garden.service       # Systemd: all-in-one start/stop
└── README.md                   # This file
```

---

Troubleshooting
---------------

See the **[troubleshooting/](troubleshooting/)** folder:

- [troubleshooting/README.md](troubleshooting/README.md) — quick problem/solution table
- [troubleshooting/guide.md](troubleshooting/guide.md) — in-depth fixes for each component
- [troubleshooting/check-status.sh](troubleshooting/check-status.sh) — run to check all services at once

---

Setting Up a New Server
-----------------------

Follow these steps on a freshly installed Debian or Ubuntu machine.
