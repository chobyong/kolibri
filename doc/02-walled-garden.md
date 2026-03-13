# Walled Garden — Hotspot, DHCP, DNS & Captive Portal

## Overview

The walled garden creates an isolated Wi-Fi network that redirects all
connected clients to a local landing page. From there users can access
Kolibri and NextCloud without any internet connection.

### Architecture

```
Client Device
    |
    | Wi-Fi (SSID: him-edu)
    v
 hostapd          — Wi-Fi Access Point
    |
 dnsmasq          — DHCP (assigns IPs) + DNS (redirects all domains → 10.42.0.1)
    |
 iptables         — Redirects HTTP/HTTPS/DNS traffic to local server
    |
 server.py        — Captive portal (serves landing page on ports 80 & 443)
    |
 www/index.html   — Landing page with links to Kolibri & NextCloud
```

## Components

### hostapd — Wi-Fi Access Point

- Creates a WPA2-PSK access point
- SSID: `him-edu`, Password: `1234567890`
- Channel 6, 802.11g, nl80211 driver
- Configuration generated dynamically by `start_ap.sh`

### dnsmasq — DHCP & DNS

- **DHCP range**: 10.42.0.10 – 10.42.0.254 (12-hour leases)
- **DNS**: Wildcard redirect — all domain queries resolve to `10.42.0.1`
- Runs on the wireless interface only
- Configuration generated dynamically by `start_ap.sh`

### iptables — Firewall Rules

Rules applied by `iptables_rules.sh`:

| Chain      | Rule                                    | Purpose                      |
|------------|-----------------------------------------|------------------------------|
| PREROUTING | DNAT UDP :53 → 10.42.0.1:53            | Redirect DNS (UDP)           |
| PREROUTING | DNAT TCP :53 → 10.42.0.1:53            | Redirect DNS (TCP)           |
| PREROUTING | DNAT TCP :80 → 10.42.0.1:80            | Redirect HTTP                |
| PREROUTING | DNAT TCP :443 → 10.42.0.1:443          | Redirect HTTPS               |
| FORWARD    | DROP                                    | Block all forwarded traffic  |

### server.py — Captive Portal

- Python `ThreadingHTTPServer` on ports 80 (HTTP) and 443 (HTTPS)
- Auto-generates self-signed SSL certificate in `ssl/`
- Serves `www/index.html` for all requests
- `allow_reuse_address = True` set as class attribute to prevent port conflicts

## Usage

### Start the Walled Garden

```bash
sudo ./start_ap.sh
```

This will:
1. Detect the wireless interface automatically
2. Remove it from NetworkManager control
3. Assign IP 10.42.0.1/24
4. Generate and start hostapd
5. Generate and start dnsmasq
6. Apply iptables rules
7. Start the captive portal server

### Stop the Walled Garden

```bash
sudo ./stop_ap.sh
```

This will:
1. Kill server.py, hostapd, and dnsmasq
2. Clear all iptables rules
3. Return the wireless interface to NetworkManager

### Enable on Boot

```bash
sudo systemctl enable walled-garden
```

## Systemd Services

| Service                  | Description                          |
|--------------------------|--------------------------------------|
| `walled-garden.service`  | All-in-one (start_ap.sh / stop_ap.sh)|
| `him-ap.service`         | hostapd + dnsmasq only               |
| `him-firewall.service`   | iptables rules only                  |
| `him-webserver.service`  | Captive portal (server.py) only      |

## Configuration

### Changing SSID or Password

Edit the variables at the top of `start_ap.sh`:

```bash
SSID="him-edu"
PASSPHRASE="1234567890"
```

### Changing the AP IP

Edit `AP_IP` in `start_ap.sh` and update the DNAT rules in `iptables_rules.sh`.

### Customizing the Landing Page

Edit `www/index.html`. The captive portal serves this file for all HTTP/HTTPS
requests.
