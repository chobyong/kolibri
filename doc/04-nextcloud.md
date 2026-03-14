# NextCloud — File Sharing, Calendar, Notes & Office

## Overview

NextCloud provides collaborative file storage, calendar, notes, and document
editing (via Collabora Online). It runs as a Docker Compose stack with five
containers.

- **URL**: http://10.42.0.1:8081/
- **Admin**: `him` / `ABCD_1234`

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  Docker Compose Stack (nextcloud/)                   │
│                                                      │
│  ┌──────────┐  ┌───────────┐  ┌───────────────────┐ │
│  │ NextCloud │  │  MariaDB  │  │  Collabora Online │ │
│  │  :8081    │  │  (DB)     │  │  :9980            │ │
│  └────┬─────┘  └───────────┘  └───────────────────┘ │
│       │                                              │
│  ┌────┴─────┐  ┌───────────────────────────────────┐ │
│  │  Redis   │  │  Nginx Proxy Manager  :81         │ │
│  │  (cache) │  │  (reverse proxy admin)            │ │
│  └──────────┘  └───────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

## Container Details

| Container      | Image                                | Port  | Purpose                 |
|----------------|--------------------------------------|-------|-------------------------|
| nextcloud      | nextcloud:latest                     | 8081  | NextCloud application   |
| nextcloud-db   | mariadb:latest                       | —     | MySQL database          |
| collabora      | collabora/code:latest                | 9980  | Document editing engine |
| redis          | redis:latest                         | —     | Session/file cache      |
| nginx-proxy    | jc21/nginx-proxy-manager:latest      | 81    | Reverse proxy admin     |

## Installed Apps

| App               | Version | Purpose                        |
|-------------------|---------|--------------------------------|
| Calendar          | 6.2.1   | CalDAV calendar management     |
| Notes             | 4.13.0  | Markdown note-taking           |
| Richdocuments     | 10.1.0  | NextCloud Office (Collabora)   |

## Installation

### Automatic (via install.sh)

The master `install.sh` handles the full NextCloud setup:

1. Creates volume directories under `nextcloud/`
2. Starts Docker Compose stack
3. Runs `occ maintenance:install` with MySQL backend
4. Configures trusted domains and WOPI settings
5. Downloads and installs Calendar, Notes, and Richdocuments apps
6. Configures Collabora integration

### Manual Installation

See `nextcloud/README.md` for step-by-step manual instructions.

## Configuration

### Trusted Domains

```bash
docker exec -u www-data nextcloud php occ config:system:get trusted_domains
```

Currently configured:
- `localhost` (default)
- `10.42.0.1:8081`
- `10.42.0.1`

### Collabora (NextCloud Office)

| Setting           | Value                       |
|-------------------|-----------------------------|
| `wopi_url`        | `http://collabora:9980`     |
| `public_wopi_url` | `http://10.42.0.1:9980`     |
| `wopi_allowlist`  | `10.42.0.0/24,172.18.0.0/16`|

The Collabora container runs with:
- `cap_add: [MKNOD, SYS_ADMIN]` — required for bind-mount jail
- `security_opt: [apparmor:unconfined]` — required on AppArmor systems
- SSL disabled (`extra_params: --o:ssl.enable=false`)

### Database

| Setting  | Value          |
|----------|----------------|
| Host     | `nextclouddb`  |
| Database | `nextcloud`    |
| User     | `nextcloud`    |
| Password | `dbpassword`   |
| Root PW  | `rootpassword` |

## Managing NextCloud

### Docker Commands

```bash
cd nextcloud/

# Start all containers
docker compose up -d

# Stop all containers
docker compose down

# View logs
docker compose logs -f nextcloud

# Restart a specific container
docker compose restart nextcloud
```

### OCC (NextCloud CLI)

```bash
# Run any occ command
docker exec -u www-data nextcloud php occ <command>

# List enabled apps
docker exec -u www-data nextcloud php occ app:list --enabled

# Check system status
docker exec -u www-data nextcloud php occ status

# Run maintenance
docker exec -u www-data nextcloud php occ maintenance:repair
docker exec -u www-data nextcloud php occ db:add-missing-indices
```

### Installing Additional Apps

Because the offline environment may not reach the Nextcloud App Store, apps
are installed manually:

```bash
# 1. Download tarball (while online)
curl -fsSL -o app.tar.gz https://github.com/nextcloud-releases/<app>/releases/download/v<ver>/<app>-v<ver>.tar.gz

# 2. Extract into custom_apps
docker cp app.tar.gz nextcloud:/tmp/
docker exec nextcloud bash -c "tar xzf /tmp/app.tar.gz -C /var/www/html/custom_apps/ && chown -R www-data:www-data /var/www/html/custom_apps/<app>"

# 3. Enable
docker exec -u www-data nextcloud php occ app:enable <app>
```

## Data Directories

All persistent data is stored in `nextcloud/` subdirectories (excluded from
git via `.gitignore`):

| Directory      | Contents                    |
|----------------|-----------------------------|
| `html/`        | NextCloud application files |
| `custom_apps/` | Manually installed apps     |
| `config/`      | NextCloud configuration     |
| `data/`        | User files                  |
| `nextclouddb/` | MariaDB data                |
| `redis/`       | Redis persistence           |
| `npm-data/`    | Nginx Proxy Manager data    |
| `letsencrypt/` | SSL certificates            |

## Ports Summary

| Port | Service             | Access                  |
|------|---------------------|-------------------------|
| 8081 | NextCloud           | http://10.42.0.1:8081/  |
| 9980 | Collabora Online    | http://10.42.0.1:9980/  |
| 81   | Nginx Proxy Manager | http://10.42.0.1:81/    |
