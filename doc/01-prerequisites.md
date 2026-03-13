# Prerequisites

## Hardware Requirements

- **Computer**: Any x86_64 PC or laptop with a wireless network adapter
- **Wi-Fi adapter**: Must support AP (Access Point) mode — most built-in laptop adapters work
- **Storage**: At least 20 GB free disk space
- **RAM**: Minimum 4 GB (8 GB recommended for NextCloud + Kolibri together)

## Software Requirements

| Component       | Purpose                              | Installed By      |
|-----------------|--------------------------------------|-------------------|
| Debian/Ubuntu   | Base operating system                | Manual            |
| NetworkManager  | Network management                   | Pre-installed     |
| git             | Clone the project repository         | `install.sh`      |
| curl            | Download packages                    | `install.sh`      |
| hostapd         | Wi-Fi access point                   | `install.sh`      |
| dnsmasq         | DHCP server + DNS redirect           | `install.sh`      |
| iptables        | Firewall / traffic redirect          | `install.sh`      |
| python3         | Captive portal web server            | `install.sh`      |
| openssl         | Self-signed SSL certificate          | `install.sh`      |
| iw              | Wireless interface detection         | `install.sh`      |
| Docker          | Container runtime for NextCloud      | `install.sh`      |
| Docker Compose  | Multi-container orchestration        | `install.sh`      |
| Kolibri         | Offline learning platform            | `install.sh`      |

## Network Requirements

- **Internet access** is needed during installation to download packages,
  Docker images, and NextCloud apps.
- After installation, the server operates fully offline.

## Operating System

Tested on:
- Debian 12 (Bookworm)
- Ubuntu 22.04 LTS / 24.04 LTS

Other Debian-based distributions should work with minor adjustments.

## Pre-installation Checklist

1. Fresh Debian/Ubuntu installation with a user account (e.g., `him`)
2. `sudo` access configured for that user
3. Wi-Fi adapter present and recognized (`iw dev` shows an interface)
4. NetworkManager running (`systemctl status NetworkManager`)
5. Internet connection available for downloading dependencies
