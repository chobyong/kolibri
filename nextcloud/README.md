NextCloud Docker Stack — HIM Education
=======================================

NextCloud server running as part of the HIM Education walled garden.
Provides file sharing, document editing (Collabora), calendar, and notes
for offline use on the local network.

| Service | Container | Port |
|---------|-----------|------|
| NextCloud | nextcloud | 8081 |
| MariaDB | nextcloud-db | 3306 (internal) |
| Collabora (Office) | collabora | 9980 |
| Redis | redis | 6379 (internal) |
| Nginx Proxy Manager | nginx-proxy | 81 (admin UI) |

---

Setup on a New Host
--------------------

### Prerequisites

- Docker and Docker Compose installed
- Walled garden repo cloned to `/opt/him-edu`

```bash
sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker him
```

### 1. Create volume directories

```bash
cd /opt/him-edu/nextcloud
chmod +x nextcloud-setup.sh
sudo ./nextcloud-setup.sh
```

Or manually:
```bash
mkdir -p html custom_apps config data nextclouddb redis npm-data letsencrypt
```

### 2. Start the stack

```bash
cd /opt/him-edu/nextcloud
sudo docker compose up -d
```

### 3. Run initial NextCloud setup

```bash
sudo docker exec -u www-data nextcloud php occ maintenance:install \
  --database "mysql" \
  --database-host "nextclouddb" \
  --database-name "nextcloud" \
  --database-user "nextcloud" \
  --database-pass "dbpassword" \
  --admin-user "admin" \
  --admin-pass "admin123"
```

### 4. Configure trusted domains

```bash
sudo docker exec -u www-data nextcloud php occ config:system:set trusted_domains 1 --value="10.42.0.1:8081"
sudo docker exec -u www-data nextcloud php occ config:system:set trusted_domains 2 --value="10.42.0.1"
sudo docker exec -u www-data nextcloud php occ config:system:set overwrite.cli.url --value="http://10.42.0.1:8081"
sudo docker exec -u www-data nextcloud php occ config:system:set overwriteprotocol --value="http"
sudo docker exec -u www-data nextcloud php occ config:system:set allow_local_remote_servers --type boolean --value true
```

### 5. Install apps (Calendar, Notes, NextCloud Office)

The container needs internet access to download apps. If the walled garden
iptables are active, temporarily clear them first:

```bash
sudo /opt/him-edu/iptables_rules.sh clear
sudo systemctl restart docker
cd /opt/him-edu/nextcloud && sudo docker compose up -d
```

Then download and install each app manually:

```bash
# Calendar
sudo docker exec nextcloud bash -c "cd /tmp && \
  curl -L -o calendar.tar.gz https://github.com/nextcloud-releases/calendar/releases/download/v6.2.1/calendar-v6.2.1.tar.gz && \
  tar xzf calendar.tar.gz -C /var/www/html/custom_apps/ && \
  chown -R www-data:www-data /var/www/html/custom_apps/calendar"
sudo docker exec -u www-data nextcloud php occ app:enable calendar

# Notes
sudo docker exec nextcloud bash -c "cd /tmp && \
  curl -L -o notes.tar.gz https://github.com/nextcloud-releases/notes/releases/download/v4.13.0/notes-v4.13.0.tar.gz && \
  tar xzf notes.tar.gz -C /var/www/html/custom_apps/ && \
  chown -R www-data:www-data /var/www/html/custom_apps/notes"
sudo docker exec -u www-data nextcloud php occ app:enable notes

# NextCloud Office (richdocuments)
sudo docker exec nextcloud bash -c "cd /tmp && \
  curl -L -o richdocuments.tar.gz https://github.com/nextcloud-releases/richdocuments/releases/download/v10.1.0/richdocuments-v10.1.0.tar.gz && \
  tar xzf richdocuments.tar.gz -C /var/www/html/custom_apps/ && \
  chown -R www-data:www-data /var/www/html/custom_apps/richdocuments"
sudo docker exec -u www-data nextcloud php occ app:enable richdocuments
```

### 6. Configure Collabora (NextCloud Office)

```bash
sudo docker exec -u www-data nextcloud php occ config:app:set richdocuments wopi_url --value="http://collabora:9980"
sudo docker exec -u www-data nextcloud php occ config:app:set richdocuments public_wopi_url --value="http://10.42.0.1:9980"
sudo docker exec -u www-data nextcloud php occ config:app:set richdocuments wopi_allowlist --value="10.42.0.0/24,172.18.0.0/16"
```

### 7. Re-enable walled garden

```bash
sudo /opt/him-edu/start_ap.sh
```

---

Default Credentials
-------------------

| Service | Username | Password |
|---------|----------|----------|
| NextCloud | admin | admin123 |
| Collabora | nextcloud | password |
| Nginx Proxy Manager | admin@example.com | changeme |

**Change these passwords after first login.**

---

Useful Commands
---------------

```bash
# Check container status
sudo docker compose ps

# View NextCloud logs
sudo docker logs nextcloud

# View Collabora logs
sudo docker logs collabora

# Restart the stack
sudo docker compose restart

# Stop the stack
sudo docker compose down

# List enabled apps
sudo docker exec -u www-data nextcloud php occ app:list --enabled

# Run NextCloud maintenance
sudo docker exec -u www-data nextcloud php occ maintenance:repair
```
