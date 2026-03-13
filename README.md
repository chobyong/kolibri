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

New Host Installation (Step-by-Step)
------------------------------------

Follow these steps to set up a fresh machine from scratch.

### Step 1 — Install the OS

Install **Debian 12** (or Ubuntu Server). During install:
- Create a user named `him`
- Enable SSH server (optional, for remote management)

### Step 2 — First boot setup

Log in as `him` and run:

```bash
# Add him to sudo group (run as root if needed)
su -c 'usermod -aG sudo him'

# Re-login for group to take effect, then:
sudo apt-get update && sudo apt-get install -y git
```

### Step 3 — Clone this repository

```bash
git clone https://github.com/chobyong/kolibri.git /home/him/walled_garden
cd /home/him/walled_garden
```

### Step 4 — (Optional) Place the Kolibri installer

Download the Kolibri `.deb` from https://learningequality.org/kolibri/download/
and copy it into `/home/him/walled_garden/`.

### Step 5 — Run the automated setup

```bash
chmod +x setup_server.sh
sudo ./setup_server.sh
```

This script will:
- Disable suspend/hibernate (server stays on)
- Install required packages (`hostapd`, `dnsmasq`, `iptables`, `python3`, `openssl`)
- Install Kolibri if the `.deb` is present
- Set file permissions
- Copy systemd service files to `/etc/systemd/system/`

### Step 6 — Install NextCloud (Docker)

```bash
sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker him
cd /home/him/walled_garden/nextcloud
sudo ./nextcloud-setup.sh
```

Then follow the detailed setup in [nextcloud/README.md](nextcloud/README.md)
(initial install, trusted domains, app installation, Collabora config).

### Step 7 — Start the walled garden

```bash
sudo ./start_ap.sh
```

### Step 8 — (Optional) Enable on boot

```bash
sudo systemctl enable walled-garden
```

### Step 9 — Test

1. On a phone or laptop, connect to Wi-Fi `him-edu` with password `1234567890`
2. A captive portal page should appear automatically
3. If not, open any HTTP URL (e.g. `http://neverssl.com`) in a browser
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
| `setup_server.sh`   | One-time setup: installs packages, sets permissions,        |
|                     | installs systemd services, optionally installs Kolibri.     |
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
# Check processes
pgrep -a hostapd
pgrep -a dnsmasq
pgrep -af server.py

# Check Wi-Fi AP
sudo iw dev | grep -A5 "type AP"

# Check iptables rules
sudo iptables -t nat -L PREROUTING -n

# Check DHCP leases
cat /var/lib/misc/dnsmasq.leases
```

---

File Structure
--------------

```
/home/him/walled_garden/
├── start_ap.sh            # Start everything
├── stop_ap.sh             # Stop everything
├── iptables_rules.sh      # Firewall rules (called by start/stop)
├── server.py              # Captive portal web server
├── setup_server.sh        # One-time installation script
├── hostapd.conf           # Generated at runtime by start_ap.sh
├── dnsmasq.conf           # DNS/DHCP config (generated at runtime)
├── www/
│   └── index.html         # Landing page shown to clients
├── ssl/                   # Auto-generated SSL certs (gitignored)
├── nextcloud/             # NextCloud Docker stack
│   ├── docker-compose.yml # NextCloud, MariaDB, Collabora, Redis, Nginx
│   ├── nextcloud-setup.sh # Creates volume dirs and starts stack
│   └── README.md          # NextCloud setup documentation
├── him-ap.service         # Systemd: hotspot (hostapd+dnsmasq)
├── him-firewall.service   # Systemd: iptables rules
├── him-webserver.service  # Systemd: captive portal server
├── walled-garden.service  # Systemd: all-in-one start/stop
└── README.md              # This file
```

---

Troubleshooting
---------------

| Problem | Solution |
|---------|----------|
| No captive portal popup | Open `http://neverssl.com` manually in a browser |
| HTTPS certificate warning | Expected — click "Advanced" → "Proceed". The portal uses a self-signed cert |
| No IP address on client | Check `pgrep dnsmasq` is running. Check `sudo iw dev` shows AP mode |
| hostapd fails to start | Run `sudo iw list` and verify "AP" is in supported interface modes |
| "Address already in use" for dnsmasq | Another dnsmasq is running — `sudo pkill dnsmasq` then retry |
| Kolibri unreachable | Verify Kolibri is running: `systemctl status kolibri` |
| NextCloud unreachable | Verify container is running: `docker ps` |
| DNS not redirecting | Check iptables DNS rules: `sudo iptables -t nat -L -n` should show port 53 DNAT |
| Wi-Fi interface not found | Check `ls /sys/class/net/ \| grep wl` — may need a USB Wi-Fi adapter |

---

Cloning to a New Machine
-------------------------

To replicate this server onto another identical machine:

```bash
# On the new machine:
sudo apt-get update && sudo apt-get install -y git

git clone https://github.com/chobyong/kolibri.git /home/him/walled_garden
cd /home/him/walled_garden

# Place Kolibri .deb in this directory if needed, then:
chmod +x setup_server.sh
sudo ./setup_server.sh

# Set up NextCloud:
sudo apt-get install -y docker.io docker-compose-plugin
cd nextcloud && sudo ./nextcloud-setup.sh
# Then follow nextcloud/README.md for initial config

# Start:
cd /home/him/walled_garden
sudo ./start_ap.sh

# Enable on boot:
sudo systemctl enable walled-garden
```

For Kolibri content, either:
- Run the Kolibri setup wizard and import channels over the network, or
- Copy `/home/him/.kolibri/` from the old machine to the new one.
