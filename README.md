# Homelab - Docker Compose Setup

A simple, portable homelab configuration using Docker Compose. Run your media server, home automation, cloud storage, and more on any Ubuntu Server.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Home Network                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────┐         ┌────────────────────────┐   │
│  │  Homelab (Ubuntu)    │         │  OMV NAS               │   │
│  │                      │◄───────►│                        │   │
│  │  Docker Services:    │   NFS   │  Shared directories:   │   │
│  │  • Jellyfin :8096    │         │  • media               │   │
│  │  • Home Assistant    │         │  • downloads           │   │
│  │    :8123             │         │  • documents           │   │
│  │  • Transmission :9091│         │  • backups             │   │
│  │  • Nextcloud :8080   │         │  • nextcloud           │   │
│  │  • Syncthing :8384   │         │  • syncthing           │   │
│  │  • Grafana :3000     │         │                        │   │
│  │  • WireGuard :51820  │         │                        │   │
│  │  • Dashboard :80     │         │                        │   │
│  └──────────────────────┘         └────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Install Ubuntu Server

Download and install [Ubuntu Server 24.04 LTS](https://ubuntu.com/download/server).

### 2. Clone and Configure

```bash
# Clone this repo
git clone https://github.com/DanBeard/homelab.git
cd homelab

# Copy and edit the environment file
cp .env.example .env
nano .env

# Set your NAS IP, timezone, and generate passwords:
# openssl rand -base64 16
```

### 3. Run Setup Script

```bash
chmod +x scripts/setup.sh
sudo ./scripts/setup.sh
```

This will:
- Install Docker
- Install NFS client
- Mount your NAS shares
- Create config directories

### 4. Start Services

```bash
# Log out and back in first (for docker group)
docker compose up -d
```

### 5. Access Your Services

| Service | URL | Default Login |
|---------|-----|---------------|
| **Dashboard** | http://homelab | No login required |
| Jellyfin | http://homelab:8096 | Create on first visit |
| Home Assistant | http://homelab:8123 | Create on first visit |
| Transmission | http://homelab:9091 | From .env file |
| Nextcloud | http://homelab:8080 | admin / from .env |
| Syncthing | http://homelab:8384 | Create on first visit |
| Grafana | http://homelab:3000 | admin / from .env |

The Dashboard is your homelab's landing page with links to all services, system stats, and WireGuard setup guides.

---

## Configuration

### Environment Variables

All configuration is in `.env`. Key settings:

```bash
# Your NAS IP
NAS_IP=192.168.1.100

# Timezone
TZ=America/Los_Angeles

# WireGuard VPN
WG_SERVERURL=vpn.yourdomain.com
WG_PEERS=phone,laptop

# Service passwords
TRANSMISSION_PASS=...
NEXTCLOUD_ADMIN_PASS=...
GRAFANA_ADMIN_PASS=...
```

### NFS Mount

The setup script mounts a single NFS share and creates subdirectories:

```
NAS:/srv/homelab  →  /mnt/nas/
                      ├── media/
                      ├── downloads/
                      ├── documents/
                      ├── backups/
                      ├── nextcloud/
                      └── syncthing/
```

On your OMV NAS, create one shared folder (`/srv/homelab`) and export it via NFS.

### Directory Structure

```
homelab/
├── docker-compose.yml      # All services
├── .env                    # Your configuration
├── .env.example            # Template
├── dashboard/              # Dashboard Flask app
│   ├── app.py
│   ├── requirements.txt
│   ├── static/css/
│   └── templates/
├── config/                 # Container configs (auto-created)
│   ├── jellyfin/
│   ├── homeassistant/
│   ├── transmission/
│   ├── nextcloud/
│   ├── syncthing/
│   ├── prometheus/
│   │   └── prometheus.yml
│   └── wireguard/
└── scripts/
    └── setup.sh
```

---

## Services

### Dashboard (Landing Page)

Central hub for your homelab with service links and system stats.

- **Port**: 80
- **Features**:
  - Links to all services
  - Real-time system stats (CPU, RAM, Disk, Uptime)
  - WireGuard setup guides for Android, Windows, Linux, macOS
- **Config**: `./dashboard/` (Flask app)

No login required - designed for trusted LAN/VPN access.

### Jellyfin (Media Server)

Stream your movies, TV shows, and music.

- **Port**: 8096
- **Media location**: `/mnt/nas/media` (read-only)
- **Config**: `./config/jellyfin/`

For hardware transcoding (Intel Quick Sync), uncomment the `devices` section in docker-compose.yml.

### Home Assistant (Home Automation)

Control your smart home devices.

- **Port**: 8123
- **Config**: `./config/homeassistant/`

For USB devices (Zigbee/Z-Wave), uncomment the `privileged` and `devices` sections.

### Transmission (Torrents)

Download torrents with web UI.

- **Web UI**: 9091
- **Peer port**: 51413
- **Downloads**: `/mnt/nas/downloads/`
- **Watch folder**: `/mnt/nas/downloads/watch/`

### Nextcloud (Cloud Storage)

Self-hosted Dropbox alternative.

- **Port**: 8080
- **Data**: `/mnt/nas/nextcloud/`
- **Database**: SQLite (simple setup)

### Syncthing (File Sync)

Sync files between devices.

- **Web UI**: 8384
- **Sync ports**: 22000, 21027
- **Data**: `/mnt/nas/syncthing/`

### Monitoring (Prometheus + Grafana)

System monitoring and dashboards.

- **Grafana**: 3000 (dashboards)
- **Prometheus**: 9090 (metrics)
- **Node Exporter**: 9100 (system metrics)

After starting, add Prometheus as a data source in Grafana:
1. Go to Grafana → Connections → Data Sources
2. Add Prometheus with URL: `http://prometheus:9090`

### WireGuard (VPN)

Secure remote access to your homelab.

- **Port**: 51820/UDP
- **Peer configs**: `./config/wireguard/peer_*/`

After first start, find your peer configs and scan the QR codes with the WireGuard mobile app.

---

## Common Commands

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f
docker compose logs -f jellyfin

# Restart a service
docker compose restart jellyfin

# Update all containers
docker compose pull
docker compose up -d

# Check container status
docker compose ps

# Shell into a container
docker compose exec jellyfin bash
```

---

## OMV NAS Setup

On your OpenMediaVault NAS:

1. **Create a shared folder** (Storage → Shared Folders):
   - Name: `homelab`
   - Path will be `/srv/homelab`

2. **Enable NFS** (Services → NFS → Settings → Enable)

3. **Create NFS share** for the homelab folder:
   - Shared folder: `homelab`
   - Client: `192.168.1.0/24` (your network)
   - Privilege: Read/Write
   - Extra options: `subtree_check,insecure,no_root_squash`

4. Apply changes

The setup script will create subdirectories (media, downloads, etc.) inside `/mnt/nas/` after mounting.

---

## Backup

Your important data is on the NAS. The homelab just runs the services.

To backup container configs:
```bash
tar -czf homelab-config-backup.tar.gz config/
# Copy to NAS
cp homelab-config-backup.tar.gz /mnt/nas/backups/
```

---

## Troubleshooting

### NFS mounts not working

```bash
# Check if NAS is reachable
ping $NAS_IP

# Check NFS exports on NAS
showmount -e $NAS_IP

# Manually mount to test
sudo mount -t nfs $NAS_IP:/srv/media /mnt/nas/media

# Check mount status
df -h /mnt/nas/*
```

### Container not starting

```bash
# Check logs
docker compose logs servicename

# Check if ports are in use
sudo ss -tlnp | grep 8096
```

### Permission issues

Make sure PUID/PGID in `.env` match your user:
```bash
id
# Use the uid and gid values
```

---

## License

MIT License
