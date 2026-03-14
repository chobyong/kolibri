# Troubleshooting

## Walled Garden / Hotspot

### "802.1X supplicant took too long to authenticate"

**Cause**: NetworkManager tried to use wpa_supplicant in AP mode, which conflicts
with nl80211 drivers on many adapters.

**Fix**: The project uses hostapd directly instead of NetworkManager AP mode.
Ensure `start_ap.sh` is being used (not any NM-based hotspot command).

### No wireless interface detected

```bash
# Check for wireless interfaces
iw dev
ls /sys/class/net/ | grep wl
```

If none appear:
- Verify your Wi-Fi adapter is plugged in / enabled
- Check `lspci | grep -i wireless` or `lsusb` for adapter presence
- Install firmware: `sudo apt install firmware-iwlwifi` (Intel) or appropriate package

### Clients connect but can't reach landing page

1. **Check dnsmasq is running**: `pgrep dnsmasq`
2. **Check iptables rules**: `sudo iptables -t nat -L -n`
3. **Check server.py is running**: `pgrep -f server.py`
4. **Verify IP assignment**: `ip addr show` — the wireless interface should have `10.42.0.1/24`

### Port 80/443 already in use

```bash
# Find what's using the port
sudo ss -tlnp | grep ':80\|:443'

# Kill stale server.py processes
sudo pkill -f server.py
```

The `start_ap.sh` script automatically kills old instances before starting.

### dnsmasq won't start (port 53 conflict)

```bash
# Check for existing DNS servers
sudo ss -ulnp | grep ':53'

# Common culprit: systemd-resolved
sudo systemctl stop systemd-resolved
```

Or stop the system dnsmasq: `sudo systemctl stop dnsmasq`

---

## Kolibri

### Kolibri not accessible on port 8080

```bash
# Check if service is running
sudo systemctl status kolibri

# Restart
sudo systemctl restart kolibri

# Check logs
journalctl -u kolibri -n 50
```

### Cannot import content

- For online import: ensure iptables are cleared (`sudo ./stop_ap.sh`) so the
  server has internet access
- For USB import: mount the drive and use Kolibri's Device → Channels → Import → Local drive

---

## NextCloud

### Container won't start

```bash
cd nextcloud/
docker compose logs nextcloud
docker compose logs nextcloud-db
```

Common causes:
- Database not ready: restart with `docker compose restart nextcloud`
- Port conflict: check `sudo ss -tlnp | grep 8081`

### "Access through untrusted domain"

Add the domain/IP to trusted domains:

```bash
docker exec -u www-data nextcloud php occ config:system:set trusted_domains 1 --value="10.42.0.1:8081"
```

### Apps fail to install via App Store

**Cause**: In offline/walled-garden mode, NextCloud can't reach apps.nextcloud.com.

**Fix**: Install apps manually (see [04-nextcloud.md](04-nextcloud.md#installing-additional-apps)).

To install apps, you need internet access. Temporarily stop the walled garden:

```bash
sudo ./stop_ap.sh
# ... install apps ...
sudo ./start_ap.sh
```

### Collabora shows "Slow Kit jail setup with copying"

**Cause**: Collabora can't use bind-mount for its jail.

**Fix**: The `docker-compose.yml` includes:
```yaml
cap_add:
  - MKNOD
  - SYS_ADMIN
security_opt:
  - apparmor:unconfined
```

If this message persists, verify these settings in `nextcloud/docker-compose.yml`.

### NextCloud Office doesn't show "New document" button

Check Collabora WOPI configuration:

```bash
docker exec -u www-data nextcloud php occ config:app:get richdocuments wopi_url
docker exec -u www-data nextcloud php occ config:app:get richdocuments public_wopi_url
```

Expected values:
- `wopi_url`: `http://collabora:9980`
- `public_wopi_url`: `http://10.42.0.1:9980`

---

## Docker

### Docker requires sudo

The user must be in the `docker` group:

```bash
sudo usermod -aG docker $USER
# Log out and back in for this to take effect
```

### Containers lose networking when walled garden is active

The iptables rules intercept Docker's internal DNS. Either:
- Start Docker containers **before** the walled garden
- Or temporarily clear iptables: `sudo ./iptables_rules.sh clear`

### Docker Compose "version is obsolete" warning

This is a non-fatal warning. The `version: '3'` key in `docker-compose.yml`
is deprecated but still works. It can safely be removed.

---

## General

### Need internet while walled garden is running

```bash
# Stop the walled garden
sudo ./stop_ap.sh

# Do your tasks (apt update, etc.)

# Restart the walled garden
sudo ./start_ap.sh
```

### Checking all service status at once

```bash
echo "=== hostapd ===" && pgrep -a hostapd
echo "=== dnsmasq ===" && pgrep -a dnsmasq
echo "=== server.py ===" && pgrep -af server.py
echo "=== kolibri ===" && systemctl is-active kolibri
echo "=== docker containers ===" && docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Full reset

To completely reset and reinstall:

```bash
sudo ./stop_ap.sh
cd nextcloud && docker compose down -v && cd ..
sudo rm -rf nextcloud/{html,custom_apps,config,data,nextclouddb,redis,npm-data,letsencrypt}
cd /opt/him-edu
sudo ./install.sh
```
