#!/bin/bash

# Create backup directory
BACKUP_DIR="/home/him/walled_garden_backup"
mkdir -p "$BACKUP_DIR"

# Backup all configuration files
echo "Creating backup of walled garden configuration..."
cd /home/him/walled_garden
tar czf "$BACKUP_DIR/walled_garden.tar.gz" ./*

# Save system service status and configurations
echo "Saving service configurations..."
systemctl status him-ap him-dnsmasq him-webserver him-firewall > "$BACKUP_DIR/services_status.txt"
iptables-save > "$BACKUP_DIR/iptables_rules.txt"
ip addr show wlp3s0 > "$BACKUP_DIR/network_config.txt"
nmcli connection show HIM-GUATE02 > "$BACKUP_DIR/nmcli_config.txt"

# Create setup instructions
cat > "$BACKUP_DIR/SETUP_INSTRUCTIONS.md" << 'EOL'
# HIM Education Server Setup Instructions

## System Requirements
- Linux system with NetworkManager
- Python 3
- dnsmasq

## Files Overview
- `walled_garden.tar.gz`: All configuration files and web content
- `iptables_rules.txt`: Firewall rules backup
- `network_config.txt`: Network interface configuration
- `services_status.txt`: Systemd services status
- `nmcli_config.txt`: NetworkManager connection details

## Installation Steps

1. Extract the configuration files:
```bash
cd /home/him
tar xzf walled_garden_backup/walled_garden.tar.gz -C walled_garden/
```

2. Install required packages:
```bash
sudo apt-get update
sudo apt-get install dnsmasq python3
```

3. Install systemd services:
```bash
sudo cp walled_garden/him-*.service /etc/systemd/system/
sudo systemctl daemon-reload
```

4. Enable and start services:
```bash
sudo systemctl enable him-firewall him-ap him-dnsmasq him-webserver
sudo systemctl start him-firewall him-ap him-dnsmasq him-webserver
```

## Network Details
- SSID: HIM-GUATE02
- Password: 1234567890
- AP IP Address: 10.42.0.1
- DHCP Range: 10.42.0.10 - 10.42.0.254

## Service Information
- Web Server: Running on port 80, serving content from /home/him/walled_garden/www/
- DHCP Server: dnsmasq on wlp3s0
- Access Point: Managed by NetworkManager
- Firewall: iptables rules for captive portal

## Files Location
- Web Content: /home/him/walled_garden/www/
- Configuration Files: /home/him/walled_garden/
- Systemd Services: /etc/systemd/system/him-*.service

## Verification Steps
1. Check service status:
```bash
sudo systemctl status him-ap him-dnsmasq him-webserver him-firewall
```

2. Verify network interface:
```bash
ip addr show wlp3s0
```

3. Check firewall rules:
```bash
sudo iptables -t nat -L -n -v
```

## Troubleshooting
1. If services fail to start:
   - Check journalctl: `journalctl -u him-ap -u him-dnsmasq -u him-webserver -u him-firewall`
   - Verify NetworkManager is running: `systemctl status NetworkManager`
   - Check interface name matches wlp3s0 or update configuration accordingly

2. If web server fails:
   - Check port 80 is not in use: `sudo lsof -i :80`
   - Verify permissions: `ls -l /home/him/walled_garden/www/`

3. If DHCP not working:
   - Stop any other DHCP servers
   - Check dnsmasq logs: `journalctl -u him-dnsmasq`

## Important Files
1. him-ap.service: Access Point service
2. him-dnsmasq.service: DHCP and DNS service
3. him-webserver.service: Web server service
4. him-firewall.service: iptables rules service
5. setup_iptables.sh: Firewall configuration script
6. www/index.html: Main web page

EOL

echo "Backup created in $BACKUP_DIR"
echo "To restore on another system, copy the backup directory and follow SETUP_INSTRUCTIONS.md"