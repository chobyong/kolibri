# Kolibri — Offline Learning Platform

## Overview

[Kolibri](https://learningequality.org/kolibri/) is an offline-first learning
platform by Learning Equality. It provides access to curated educational
content (Khan Academy, CK-12, etc.) without an internet connection.

- **URL**: http://10.42.0.1:8080/
- **Runs as**: systemd service (`kolibri`)

## Installation

### Automatic (via install.sh)

The master `install.sh` script handles Kolibri installation:

1. Checks if Kolibri is already installed (`command -v kolibri`)
2. Looks for a `kolibri*.deb` file in the project directory
3. If no local `.deb`, tries downloading from https://learningequality.org
4. Installs the `.deb` and enables the systemd service

### Manual Installation

```bash
# Download the latest .deb
curl -fsSL -o kolibri-latest.deb https://learningequality.org/r/kolibri-deb-latest

# Install
sudo dpkg -i kolibri-latest.deb
sudo apt-get install -f -y

# Enable and start
sudo systemctl enable --now kolibri
```

## Managing Kolibri

### Service Commands

```bash
# Check status
sudo systemctl status kolibri

# Start / Stop / Restart
sudo systemctl start kolibri
sudo systemctl stop kolibri
sudo systemctl restart kolibri

# View logs
journalctl -u kolibri -f
```

### Importing Content

Kolibri content must be pre-loaded while internet is available, or imported
from a USB drive.

**From the web (while online):**
1. Open http://localhost:8080 in a browser
2. Go to **Device** → **Channels**
3. Click **Import** → **Kolibri Studio**
4. Select channels and topics to download

**From a USB drive (offline):**
1. On an internet-connected machine, use Kolibri to download channels
2. Export the channels to a USB drive from **Device** → **Channels** → **Export**
3. On the offline server, import from **Device** → **Channels** → **Import** → **Local drive**

### Default Ports

| Port | Protocol | Purpose          |
|------|----------|------------------|
| 8080 | HTTP     | Kolibri web UI   |

## Configuration

Kolibri's configuration is stored in:
- `~/.kolibri/` (user data and settings)
- Content database and files are in subdirectories of `.kolibri/`

### Changing the Port

```bash
kolibri manage --port 8080
```

Or edit the Kolibri options file in `~/.kolibri/options.ini`.
