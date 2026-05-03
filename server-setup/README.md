# server-setup — HIM Education Server Provisioning Tools

This folder contains tools for **building new HIM Education servers from scratch**
using a fully automated USB installer. It is **not used during normal operation** —
the live server runs from `/opt/him-edu/` directly.

Use these tools when you need to deploy a new server machine.

---

## What's in This Folder

| File | Purpose |
|------|---------|
| `build-iso.sh` | Takes a base Debian 13 ISO and bakes `preseed.cfg` + `provision.sh` into it to produce a custom bootable USB installer |
| `preseed.cfg` | Debian unattended install config — partitions disk, creates user `him`, installs packages, and sets up first-boot provisioning |
| `provision.sh` | Full server provisioning script — installs Docker, Kolibri, NextCloud, Wi-Fi hotspot, firewall, and all systemd services. Runs automatically on first boot |
| `docker-compose.yml` | Reference copy of the NextCloud Docker stack (same as `../nextcloud/docker-compose.yml`) |
| `SETUP.md` | Auto-generated system spec of the reference server (HIM-010) — hardware, network, services, and packages |
| `deployment-guide.md` | Step-by-step guide for deploying a new server using the USB installer method |
| `deployment-guide.pdf` | PDF version of the deployment guide (for printing or offline reference) |

---

## Two Ways to Deploy a New Server

### Option A — USB ISO (Recommended for multiple servers)

Creates a bootable USB that installs and configures everything automatically.
Only asks for the hostname — no other input required.

**Build the USB:**

1. Download the official Debian 13 (trixie) netinst ISO:
   ```
   https://cdimage.debian.org/cdimage/daily-builds/daily/arch-latest/amd64/iso-cd/
   ```
   Save it as `server-setup/debian-base.iso`

2. Run the ISO builder (requires `xorriso`, `isolinux`, `syslinux-utils`, `cpio`):
   ```bash
   cd /opt/him-edu/server-setup
   sudo bash build-iso.sh                # build ISO only → him-edu-debian13.iso
   sudo bash build-iso.sh /dev/sdX       # build + write directly to USB drive
   ```

3. If you built the ISO only, write it to a USB drive manually:
   ```bash
   sudo dd if=him-edu-debian13.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```
   > Replace `/dev/sdX` with your USB device (check with `lsblk`). This **wipes** the USB.

**Deploy with the USB:**

1. Plug USB into the new machine and boot from it
2. At the installer prompt, enter the hostname (e.g. `HIM-012`) — that is the only question
3. Wait ~15–25 min for Debian to install — machine reboots automatically
4. Remove USB when machine powers off
5. On first boot, `provision.sh` runs automatically in the background (~20–40 min)

Monitor provisioning progress over SSH:
```bash
ssh him@<machine-ip>
journalctl -fu him-provision.service
```

See [deployment-guide.md](deployment-guide.md) for full step-by-step instructions.

---

### Option B — Manual Provisioning (single server, already has Debian installed)

If Debian 13 is already installed and you just need to configure it:

```bash
sudo bash /opt/him-edu/server-setup/provision.sh
```

The script is **idempotent** — safe to re-run if something failed partway through.

---

## What provision.sh Installs

Runs in phases, in order:

| Phase | What it does |
|-------|-------------|
| 0 | Sets hostname |
| 1 | Installs system prerequisites (hostapd, dnsmasq, iptables, python3, etc.) |
| 2 | Installs Docker + Compose plugin, adds `him` user to `docker` group |
| 3 | Installs Kolibri from `.deb` package |
| 4 | Starts NextCloud Docker stack, runs initial setup, installs Calendar, Notes, and Office |
| 5 | Configures Wi-Fi hotspot, DHCP/DNS, iptables walled garden, captive portal |
| 6 | Installs all systemd services and enables them on boot |
| 7 | Verifies all components are running |

---

## Default Credentials (change after first deploy)

| Service | Username | Password |
|---------|----------|----------|
| Linux user | `him` | `him-edu` |
| NextCloud admin | `admin` | `admin123` |
| Wi-Fi | `him-edu` | `1234567890` |
| SSH | `him` | `him-edu` |

---

## Notes

- `build-iso.sh` requires a **Debian 13 base ISO** placed at `server-setup/debian-base.iso` — it is not included in the repo (too large for git)
- The generated `him-edu-debian13.iso` is also excluded from git (`.gitignore`)
- `SETUP.md` is a snapshot of the reference server HIM-010 as of 2026-03-17 — useful as a reference but may not reflect the current state of deployed servers
