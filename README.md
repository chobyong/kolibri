HIM Education — Walled Garden Server
=====================================

A self-contained offline educational server. It broadcasts a Wi-Fi hotspot
(`him-edu`) and redirects all connected wireless clients to a landing page
with links to **Kolibri** and **NextCloud** — no internet required.

| Setting     | Value                    |
|-------------|--------------------------|
| SSID        | `him-edu`                |
| Password    | `1234567890`             |
| AP IP       | `10.42.0.1`              |
| Portal      | `http://10.42.0.1`       |
| Kolibri     | `http://10.42.0.1:8080`  |
| NextCloud   | `http://10.42.0.1:8081`  |

---
- username : him , password: ABCD_1234 for all application, admin console, etc.

Quick Start — Full Installation
--------------------------------

### Step 1 — Install the OS

- Install **Debian 12** (or Ubuntu Server). Create a user (e.g., `him`) with sudo access.
- Debian or Ubuntu install will prompt for `root` and a user name `him`, password to be ABCD_1234
- initial OS install will prompt for host name is him-xxx , xxx is sequential numeric value that is unique per server
- initial OS set up will prompt for service enable, you need to enable `ssh` but not web service

```bash
su - #password to be ACBD_1234
usermond -aG sudo him
# log out and log back in to server
```
### Step 2 — Clone and Run
- run command from him user, NOT a root user for the rest of command.

```bash
sudo apt-get update && sudo apt-get install -y git curl
curl -fsSL -o /tmp/setup-him-edu.sh https://raw.githubusercontent.com/chobyong/kolibri/main/setup-him-edu.sh
chmod +x /tmp/setup-him-edu.sh
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

```bash
sudo import-kolibri-channels.sh english|spanish
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
4. The landing page shows buttons for Kolibri and NextCloud

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
     │   │  iptables        → Blocks internet (FORWARD    │
     │   │                    DROP), redirects DNS/HTTP/   │
     │   │                    HTTPS to portal              │
     │   │  server.py       → Captive portal on :80/:443  │
     │   │                                               │
     │   │  Kolibri         → Learning platform on :8080  │
     │   │  NextCloud       → File sharing on :8081       │
     │   └───────────────────────────────────────────────┘
     │
     └─ Client sees "HIM Education" landing page
        with buttons to Kolibri and NextCloud
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
   - `FORWARD DROP` — Clients cannot reach the internet.
   - DNS redirect (port 53 UDP/TCP) — Catches clients with hardcoded DNS
     (e.g. 8.8.8.8) and sends queries to our dnsmasq.
   - HTTP redirect (port 80) → captive portal.
   - HTTPS redirect (port 443) → captive portal (self-signed cert warning).

4. **server.py** — A Python HTTP/HTTPS server on ports 80 and 443.
   Serves `www/index.html` (the "HIM Education" landing page) for every
   request. Auto-generates a self-signed SSL certificate on first run.

5. **Kolibri** (port 8080) — Offline learning platform with videos,
   exercises, and lessons. Clients access it directly at `http://10.42.0.1:8080`.

6. **NextCloud** (port 8081) — File sharing and collaboration platform.
   Accessed at `http://10.42.0.1:8081`.

### What the scripts do

| Script              | What it does                                                |
|---------------------|-------------------------------------------------------------|
| `start_ap.sh`       | Auto-detects the Wi-Fi interface, removes it from           |
|                     | NetworkManager, assigns IP 10.42.0.1, generates hostapd     |
|                     | and dnsmasq configs, starts hostapd → dnsmasq → iptables → |
|                     | captive portal server.                                      |
| `stop_ap.sh`        | Kills hostapd, dnsmasq, captive portal server. Clears       |
|                     | iptables rules. Returns the Wi-Fi interface to              |
|                     | NetworkManager.                                             |
| `iptables_rules.sh` | Applies or clears the walled garden firewall rules.         |
|                     | Called by `start_ap.sh` and `stop_ap.sh`.                   |
| `install.sh`        | Full automated installation — installs all packages,        |
|                     | Docker, Kolibri, NextCloud, systemd services.               |
| `server.py`         | Python captive portal web server. Serves the landing        |
|                     | page on HTTP (:80) and HTTPS (:443).                        |

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
sudo systemctl enable him-ap him-firewall him-webserver
```

### Check status

```bash
sudo bash /opt/him-edu/troubleshooting/check-status.sh
```

---

File Structure
--------------

```
/opt/him-edu/
├── setup-him-edu.sh            # Bootstrap script (clones repo + runs install)
├── install.sh                  # Full installation script (run this first)
├── import-kolibri-channels.sh  # Import Kolibri content channels (english/spanish)
├── start_ap.sh                 # Start the walled garden
├── stop_ap.sh                  # Stop the walled garden
├── iptables_rules.sh           # Firewall rules (called by start/stop)
├── server.py                   # Captive portal web server
├── hostapd.conf                # Wi-Fi access point configuration
├── dnsmasq.conf                # DHCP/DNS configuration
├── www/
│   └── index.html              # Landing page shown to clients
├── ssl/                        # Auto-generated SSL certs (gitignored)
│   ├── cert.pem
│   └── key.pem
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
├── him-ap.service              # Systemd: hotspot (hostapd+dnsmasq)
├── him-firewall.service        # Systemd: iptables rules
├── him-webserver.service       # Systemd: captive portal server
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

### Before you start

Make sure you have:
- A machine with **Debian 12** or **Ubuntu Server 22.04+** already installed
- The `him` user created with sudo access
- An **Ethernet cable** plugged in (internet required during install)
- A **Wi-Fi adapter** available (for the hotspot after install)

### Step 1 — Log in as the `him` user

```bash
# If you just finished OS install, log out of root and log in as him
# Or switch from root:
su - him
```

### Step 2 — Run the one-line installer

Copy and paste this into the terminal. It downloads and runs everything automatically:

```bash
curl -fsSL -o /tmp/setup-him-edu.sh https://raw.githubusercontent.com/chobyong/kolibri/main/setup-him-edu.sh && sudo bash /tmp/setup-him-edu.sh
```

This single command will:
1. Install `git` and `curl` if missing
2. Clone this repo to `/opt/him-edu`
3. Install Docker, Kolibri, NextCloud, and all services
4. Start the Wi-Fi hotspot and captive portal
5. Enable everything to start automatically on boot

> The full install takes **20–40 minutes** depending on internet speed. You can monitor progress as it runs.

### Step 3 — Import Kolibri content channels

Once the server is up, load educational content:

```bash
# English channels (~270 GB):
sudo bash /opt/him-edu/import-kolibri-channels.sh english

# Spanish channels (~140 GB):
sudo bash /opt/him-edu/import-kolibri-channels.sh spanish

# Both:
sudo bash /opt/him-edu/import-kolibri-channels.sh
```

> Make sure the Ethernet cable is still connected — this downloads content from the internet.
> Check available disk space first: `df -h`

### Step 4 — Test it

1. On a phone or laptop, connect to Wi-Fi: **`him-edu`** / password **`1234567890`**
2. Open any browser — the HIM Education landing page should appear automatically
3. Tap **Kolibri** or **NextCloud** to verify both load

### Something not working?

```bash
sudo bash /opt/him-edu/troubleshooting/check-status.sh
```

See [troubleshooting/README.md](troubleshooting/README.md) for common fixes.

---

Documentation
-------------

Detailed documentation is available in the `doc/` folder:

| Document                                              | Contents                                          |
|-------------------------------------------------------|---------------------------------------------------|
| [doc/01-prerequisites.md](doc/01-prerequisites.md)    | Hardware, software, and OS requirements            |
| [doc/02-walled-garden.md](doc/02-walled-garden.md)    | Hotspot, DHCP, DNS, captive portal architecture    |
| [doc/03-kolibri.md](doc/03-kolibri.md)                | Kolibri installation, content import, management   |
| [doc/04-nextcloud.md](doc/04-nextcloud.md)            | NextCloud Docker stack, apps, Collabora config     |
| [server-setup/README.md](server-setup/README.md)              | How to build a new server using the ISO installer  |
| [troubleshooting/README.md](troubleshooting/README.md)        | Quick problem/solution table                       |
| [troubleshooting/guide.md](troubleshooting/guide.md)          | In-depth fixes for each component                  |
