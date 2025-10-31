HIM Walled Garden (captive portal)
=================================

Overview
--------

This folder contains configuration and helper scripts to turn the wireless
interface `wlp3s0` into a simple captive-portal (walled garden) that:

- runs a WPA2-protected Wi‑Fi SSID `HIM-GUATE02` (via hostapd)
- serves DHCP and DNS (via dnsmasq)
- redirects DNS for all names to the portal IP and redirects HTTP/HTTPS to the local web server
- serves a landing page showing "HIM Education server"

Files
-----

- `hostapd.conf` — hostapd configuration (open SSID by default)
- `dnsmasq.conf` — dnsmasq config: DHCP range and DNS hijack to portal
- `www/index.html` — portal page
- `start_ap.sh` — script to bring up the AP, start services and apply iptables rules (must be run as root)
- `iptables_rules.sh` — helper to apply/clear iptables rules
- `walled-garden.service` — a systemd unit that runs `start_ap.sh` (optional)
- `webserver.service` — a systemd unit to run the simple Python web server (optional)

Important notes & assumptions
---------------------------

- The wireless interface is assumed to be `wlp3s0` (from `ip link` output you provided). If your interface differs, update `hostapd.conf`, `dnsmasq.conf`, and the scripts.
- This setup uses an open SSID by default. If you want WPA2, edit `hostapd.conf` and provide a passphrase.
- Redirecting HTTPS (443 -> 80) breaks TLS and will usually produce certificate errors; the script includes that redirect because captive-portal detection sometimes happens over HTTPS. Consider removing the HTTPS redirect in production and rely on DNS + HTTP intercept.
- These scripts and units must be run as root (use `sudo`). Adjust file paths if you place them elsewhere.

Quick install steps (Debian/Ubuntu)
----------------------------------

Run these commands as root or prefix with `sudo`:

```bash
apt update
apt install -y hostapd dnsmasq iptables
# Stop services if they auto-start; we'll run them with our configs
systemctl stop hostapd dnsmasq

# Copy files to system locations or run from this directory. If running from here:
chmod +x ./start_ap.sh ./iptables_rules.sh

# Start the webserver via systemd (optional):
cp webserver.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now webserver.service

# Start the walled garden (this will start hostapd/dnsmasq and apply rules):
sudo ./start_ap.sh

# Or install the walled-garden service:
cp walled-garden.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now walled-garden.service
```

How to test
-----------

1. On a client device, connect to the SSID `HIM-GUATE02` using the passphrase `1234567890`.
2. The client should receive an IP in the `192.168.50.x` range.
3. Open a browser and try visiting any site; you should be redirected to the portal page.

Next steps and hardening
------------------------

- Use `iptables-save` to persist rules or move to `nftables` if preferred.
- Use a proper web server (nginx) for production and provide a nicer portal with login/terms.
- For captive-portal detection to work on all OSes, consider returning correct HTTP status codes and headers; sometimes OSes use HTTPS-based probes which complicates interception.
