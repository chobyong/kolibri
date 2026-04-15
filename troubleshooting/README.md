# Troubleshooting — HIM Education

Quick reference for common problems. For detailed fixes see [guide.md](guide.md).

---

## Quick Diagnostics

Run the status check script to see the state of all components at once:

```bash
sudo bash /opt/him-edu/troubleshooting/check-status.sh
```

---

## Common Problems

| Problem | First thing to try |
|---------|-------------------|
| No captive portal popup | Open `http://neverssl.com` manually in a browser |
| HTTPS certificate warning | Expected — click "Advanced" → "Proceed" (self-signed cert) |
| No IP address on client device | `pgrep dnsmasq` — restart with `sudo systemctl restart him-ap` |
| hostapd fails to start | `sudo iw list` — verify "AP" is in supported interface modes |
| dnsmasq "address in use" | `sudo pkill dnsmasq` then `sudo systemctl restart him-ap` |
| Wi-Fi interface not found | `ls /sys/class/net/ \| grep wl` — may need a USB Wi-Fi adapter |
| Kolibri unreachable (port 8080) | `sudo systemctl restart kolibri` then `journalctl -u kolibri -n 30` |
| NextCloud unreachable (port 8081) | `docker ps` — check all 5 containers are Up |
| DNS not redirecting | `sudo iptables -t nat -L -n` — should show port 53 DNAT rules |
| Need internet while AP is running | `sudo ./stop_ap.sh`, do your work, then `sudo ./start_ap.sh` |

---

## Restart Everything

```bash
sudo systemctl restart him-ap him-firewall him-webserver
sudo systemctl restart kolibri
cd /opt/him-edu/nextcloud && docker compose restart
```

## Full Reset

```bash
sudo ./stop_ap.sh
cd /opt/him-edu/nextcloud && docker compose down -v && cd ..
sudo rm -rf nextcloud/{html,custom_apps,config,data,nextclouddb,redis,npm-data,letsencrypt}
sudo ./install.sh
```

---

See [guide.md](guide.md) for in-depth troubleshooting of each component.
