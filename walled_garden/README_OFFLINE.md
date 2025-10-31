HIM Education — Offline Walled Garden
=================================

This document explains how to use and restore the offline walled garden server on a device that has no Internet connection.

Overview
--------
- AP SSID: HIM-GUATE02
- WPA2 passphrase: 1234567890
- AP IP / Gateway: 10.42.0.1/24
- DHCP range: 10.42.0.10 - 10.42.0.254
- Landing page: http://10.42.0.1/ (HTTP)
- Kolibri (learning platform): http://10.42.0.1:8080/

What this server does offline
-----------------------------
- Provides a Wi‑Fi access point and DHCP (dnsmasq).
- Answers all DNS queries with 10.42.0.1 so clients are directed to the portal.
- Redirects HTTP traffic to the portal landing page.
- Runs a local HTTPS listener using a self‑signed certificate (browser will warn).
- Hosts Kolibri on port 8080 (must be installed locally — confirmed).

Connecting a client
-------------------
1. On the client device, join the Wi‑Fi network `HIM-GUATE02` using the password `1234567890`.
2. Confirm the device got an IP in the `10.42.0.0/24` range.
3. Open a browser and visit any site using `http://` (for example: http://example.com). You should be shown the HIM landing page.
4. To open Kolibri, click the "Go to Kolibri" button on the landing page or visit: http://10.42.0.1:8080/

Handling HTTPS warnings (quick guide for end users)
--------------------------------------------------
Because this is an offline server, HTTPS sites will show a certificate warning. To reach the portal when you see the warning:

Windows / macOS / Linux (desktop browsers):
1. On the warning page click "Advanced" or "Details".
2. Click "Proceed to 10.42.0.1 (unsafe)" or similar.

Android:
1. Tap "Advanced" on the warning screen and then "Proceed".

iOS:
1. iOS may block proceeding on untrusted certs in Safari. Use the captive portal webview that opens automatically after connecting or open the landing page via http://10.42.0.1/.

Admin commands (run on the server as root)
-----------------------------------------
# Start services (systemd)
sudo systemctl start him-ap him-dnsmasq him-webserver him-firewall

# Stop services
sudo systemctl stop him-webserver him-dnsmasq him-ap him-firewall

# Check status
sudo systemctl status him-ap him-dnsmasq him-webserver him-firewall

# Inspect iptables NAT rules
sudo iptables -t nat -L -n -v

# Show listening services
sudo ss -ltnp | egrep ':80|:443|:8080|:53' || true

Restoring on another machine
----------------------------
1. Copy the `walled_garden_backup.tar.gz` archive to the new machine (e.g., via `scp` or USB).
2. Extract to the target user's home directory:

   tar -C /home/youruser -xzf /path/to/walled_garden_backup.tar.gz

3. Install the systemd service units (run as root):

   sudo cp /home/youruser/walled_garden/him-*.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable him-ap him-dnsmasq him-webserver him-firewall
   sudo systemctl start him-firewall him-ap him-dnsmasq him-webserver

4. Verify Kolibri is installed locally and listens on port 8080. If Kolibri is not installed, copy the Kolibri installer .deb into the folder and install it.

Notes and troubleshooting
-------------------------
- If clients cannot reach the landing page:
  * Confirm `wlp3s0` is up and has `10.42.0.1/24`.
  * Confirm `dnsmasq` is running and serving leases (check `/var/lib/NetworkManager/dnsmasq-wlp3s0.leases` or `/var/lib/misc/dnsmasq.leases`).
  * Confirm iptables PREROUTING DNAT rule for port 80 exists and points to 10.42.0.1.

- The system is intentionally offline. If you want valid HTTPS without browser warnings, you'll need a publicly-signed certificate and a DNS name — not possible purely offline.

Quick restore with the bundled script
-------------------------------------
A small helper is included at `restore.sh` that automates the common restore steps. It must be run as root on the target machine.

Basic dry-run (safe; shows what it would do):

```bash
sudo /home/him/walled_garden/restore.sh --dry-run
```

To perform the actual restore (default source path is `/home/him/walled_garden`):

```bash
sudo /home/him/walled_garden/restore.sh
```

If you extracted the archive somewhere else, pass `--src /path/to/walled_garden`.

Notes about iptables persistence:
- If the source `walled_garden` includes an `rules.v4` file, the script will copy it to `/etc/iptables/rules.v4`.
- This script does not install packages. On Debian/Ubuntu you can install `iptables-persistent` to ensure `/etc/iptables/rules.v4` is loaded at boot.

Client test checklist (per OS)
-----------------------------
Use these checks to validate the captive portal behavior on different client platforms.

1) Common checks (all clients)
   - Join Wi‑Fi `HIM-GUATE02` with password `1234567890`.
   - Confirm client IP is in `10.42.0.10–254`.
   - In a browser, open `http://example.com` or `http://10.42.0.1/`.
   - Landing page should appear. Click "Go to Kolibri" to reach `http://10.42.0.1:8080/`.

2) Windows 10/11
   - Connect to Wi‑Fi; the network pop-up may show a sign-in/captive prompt. If it doesn't, open Edge/Chrome to `http://example.com`.
   - If you see an HTTPS warning, click "Advanced" -> "Proceed to 10.42.0.1 (unsafe)".

3) macOS
   - After joining, macOS often opens a captive portal window automatically. If not, open Safari and visit `http://example.com`.
   - If you see a certificate warning in Safari, prefer the HTTP landing page or use the browser's "Show Details" -> "Visit this website".

4) Android
   - Android typically shows a captive portal notification after connecting; tap it to open the portal webview.
   - If the OS blocks the portal, use Chrome and visit `http://10.42.0.1/` explicitly.

5) iOS
   - iOS often opens its Captive Network Assistant automatically when it detects a captive portal. If it doesn't, open Safari and go to `http://10.42.0.1/`.
   - Note: iOS Safari can be more restrictive for proceeding past cert errors; prefer HTTP landing page.

6) Headless or CLI tests (Linux)
   - From another machine on the AP network run:

```bash
curl -v --connect-timeout 5 http://example.com || true
```

   - The response should be the landing HTML (HTTP 200) or a redirect to `10.42.0.1`.

Troubleshooting quick hits
--------------------------
- "No DHCP lease": check `ip addr` on server for `10.42.0.1/24` and `ss -ltnp` to confirm dnsmasq is listening on :53 and :67.
- "Browser keeps showing previous site": clear cache or open a private/incognito window; captive detection can be cached in the OS.
- "Can't proceed on HTTPS warnings (iOS)": use the HTTP landing page `http://10.42.0.1/` or pre-install a local CA (see Support section below).


Support
-------
If you want me to prepare a local CA and instructions to install it on all client devices (makes TLS warnings disappear but requires installing the CA on each client), I can prepare that. Otherwise, the instructions above are the recommended offline workflow.

-- HIM admin
