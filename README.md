HIM Education — Walled Garden Server
=====================================

Overview
--------

An offline educational server that broadcasts a Wi-Fi hotspot and redirects all
connected clients to a landing page with links to **Kolibri** (port 8080) and
**NextCloud** (port 8081). DHCP and DNS are managed entirely by **NetworkManager**.

| Setting     | Value              |
|-------------|--------------------|
| SSID        | `him-edu`          |
| Password    | `1234567890`       |
| AP IP       | `10.42.0.1`        |
| Portal      | `http://10.42.0.1` |
| Kolibri     | `http://10.42.0.1:8080` |
| NextCloud   | `http://10.42.0.1:8081` |

Architecture
------------

```
Client device
    │
    ├─ Wi-Fi connects to "him-edu" (WPA2)
    │
    ├─ NetworkManager (ipv4.method=shared)
    │   ├─ DHCP: assigns 10.42.0.x addresses
    │   └─ DNS:  all domains → 10.42.0.1 (via dnsmasq-shared.d)
    │
    ├─ iptables
    │   ├─ FORWARD DROP (walled garden — no internet)
    │   ├─ HTTP :80  → redirect to portal
    │   └─ HTTPS :443 → redirect to portal (cert warning)
    │
    └─ Captive Portal (Python server.py on :80/:443)
        └─ Landing page → links to Kolibri :8080 and NextCloud :8081
```

Hardware Requirements
---------------------

- A wireless network interface (built-in or USB)
- Debian/Ubuntu Linux with NetworkManager

Quick Setup
-----------

```bash
# 1. Clone the repository
git clone https://github.com/chobyong/kolibri.git /home/him/walled_garden
cd /home/him/walled_garden

# 2. (Optional) Place Kolibri .deb installer in this directory

# 3. Run setup
chmod +x setup_server.sh
sudo ./setup_server.sh
```

Usage
-----

### Start manually

```bash
sudo ./start_ap.sh
```

### Stop manually

```bash
sudo ./stop_ap.sh
```

### Enable on boot (systemd)

**Option A — Individual services:**
```bash
sudo systemctl enable him-ap him-firewall him-webserver
sudo systemctl start him-ap him-firewall him-webserver
```

**Option B — All-in-one service:**
```bash
sudo systemctl enable walled-garden
sudo systemctl start walled-garden
```

### Check status

```bash
systemctl status him-ap him-firewall him-webserver
nmcli connection show him-edu-hotspot
```

File Structure
--------------

| File                    | Purpose                                   |
|-------------------------|-------------------------------------------|
| `start_ap.sh`           | Start hotspot + firewall + portal          |
| `stop_ap.sh`            | Stop everything and clean up               |
| `iptables_rules.sh`     | Apply/clear walled garden firewall rules   |
| `server.py`             | Captive portal web server (HTTP + HTTPS)   |
| `www/index.html`        | Landing page served to clients             |
| `setup_server.sh`       | One-time setup script                      |
| `him-ap.service`        | Systemd: NetworkManager hotspot            |
| `him-firewall.service`  | Systemd: iptables rules                    |
| `him-webserver.service` | Systemd: captive portal web server         |
| `walled-garden.service` | Systemd: all-in-one start/stop             |

How It Works
------------

1. **NetworkManager** creates a Wi-Fi AP hotspot with `ipv4.method shared`,
   which automatically runs an internal dnsmasq for DHCP.

2. A config file in `/etc/NetworkManager/dnsmasq-shared.d/` adds
   `address=/#/10.42.0.1` so **all DNS queries resolve to the portal IP**.

3. **iptables** blocks FORWARD (no internet access) and redirects ports 80/443
   to the captive portal.

4. A **Python web server** (server.py) on port 80 serves the landing page.
   Clients see an "HIM Education" page with buttons for Kolibri and NextCloud.

5. **Kolibri** (port 8080) and **NextCloud** (port 8081) are accessed directly
   by clients since traffic to the AP IP is not redirected.

Testing
-------

1. On a client device, connect to Wi-Fi SSID `him-edu` with password `1234567890`
2. The device should receive an IP in the `10.42.0.x` range
3. A captive portal popup should appear with the HIM Education landing page
4. If not, open any `http://` URL in a browser — it will redirect to the portal
5. Click through to Kolibri or NextCloud

Troubleshooting
---------------

- **No captive portal popup?** Open `http://neverssl.com` in a browser manually.
- **HTTPS cert warning?** Expected — the portal uses a self-signed certificate.
  Click "Advanced" → "Proceed" to continue.
- **No DHCP address?** Check `nmcli connection show him-edu-hotspot` and
  verify the wireless interface supports AP mode.
- **Kolibri/NextCloud unreachable?** Verify they are running on ports 8080/8081.
