---
title: "HIM Education Server — Deployment Guide"
author: "HIM Education IT"
date: "2026-03-17"
geometry: margin=2.5cm
fontsize: 11pt
colorlinks: true
linkcolor: blue
urlcolor: blue
---

# HIM Education Server — Deployment Guide

## What You Need

- The USB drive (already prepared)
- New machine: x86-64 PC, 8 GB+ RAM, 100 GB+ SSD
- Ethernet cable connected to the internet (for downloading packages during install)
- Wireless card/adapter (for the Wi-Fi hotspot)

---

## Step 1 — Boot from USB

1. Plug the USB into the new machine
2. Power on and press the boot menu key:
   - **Dell:** F12 | **HP:** F9 | **Lenovo:** F12 | **ASUS:** F8 | **Generic:** Esc / F11
3. Select the USB drive from the boot menu
4. At the Debian boot screen — press **Enter** (or wait 30 seconds, it auto-selects)

---

## Step 2 — One Prompt: Set the Hostname

The installer will ask for a **hostname** (machine name). Type it, e.g.:

```
HIM-011
```

Press **Enter**. That is the **only question**. Everything else is automatic.

---

## Step 3 — Wait for Install (~15–25 min)

The installer will automatically:

- Partition and format the disk
- Install Debian 13 base system
- Create user `him` (password: `him-edu`)
- Install SSH server and required packages
- Set up `him-provision.service` to run on first boot

The machine will **reboot automatically** when done. **Remove the USB** when it powers off.

---

## Step 4 — Wait for First-Boot Provisioning (~20–40 min)

After reboot, `provision.sh` runs automatically in the background. It installs:

- Docker, Kolibri, Tailscale
- NextCloud Docker stack (5 containers)
- NextCloud apps: Calendar, Notes, Office
- Wi-Fi hotspot, DHCP, firewall, captive portal
- All systemd services

Monitor progress over SSH once the machine is up:

```bash
ssh him@<machine-ip>
journalctl -fu him-provision.service
```

---

## Step 5 — Verify Everything Is Running

```bash
# Check all services
systemctl status him-ap him-firewall him-webserver kolibri docker

# Check Docker containers
docker ps

# Check Kolibri
curl -s http://10.42.0.1:8080/ | head -5

# Check NextCloud
curl -s http://10.42.0.1:8081/ | head -5
```

---

## Step 6 — Test with a Phone or Laptop

1. Connect to Wi-Fi: **him-edu** / password **1234567890**
2. Open any browser — the captive portal appears automatically
3. Tap **Kolibri** → learning platform loads
4. Tap **NextCloud** → file sharing loads

---

## Step 7 — Change Default Passwords

```bash
# Linux user password
passwd him
```

NextCloud admin password:

> Go to `http://10.42.0.1:8081` → log in as **admin / admin123**
> → top-right avatar → **Settings** → **Security** → Change password

---

## Step 8 — Authenticate Tailscale (Remote Access)

```bash
sudo tailscale up
# Follow the URL it prints to authenticate with your Tailscale account
```

---

## Quick Reference

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| Captive portal | `http://10.42.0.1/` | — |
| Kolibri | `http://10.42.0.1:8080/` | set on first visit |
| NextCloud | `http://10.42.0.1:8081/` | admin / admin123 |
| Nginx Proxy Manager | `http://10.42.0.1:81/` | admin@example.com / changeme |
| SSH | `ssh him@<ip>` | him / him-edu |
| Wi-Fi SSID | him-edu | 1234567890 |

---

## Troubleshooting

**Wi-Fi hotspot not visible:**
```bash
sudo systemctl restart him-ap
journalctl -u him-ap -n 30
```

**NextCloud not loading:**
```bash
docker ps          # check all 5 containers are Up
docker logs nextcloud --tail 20
```

**Kolibri not loading:**
```bash
sudo systemctl restart kolibri
sudo systemctl status kolibri
```

**Provisioning failed or incomplete:**
```bash
sudo bash /opt/him-edu/provision.sh   # safe to re-run
```

**Check provisioning log:**
```bash
cat /var/log/him-provision.log
```
