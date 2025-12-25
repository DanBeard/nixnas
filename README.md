# NixNAS - Multi-Host NixOS Home Infrastructure

A modular NixOS configuration for home infrastructure with multiple host types.

## Host Configurations

### storage-node (Minimal NAS)
**For memory-constrained hardware (1GB RAM, Intel Atom, QNAP, etc.)**

- ZFS mirror with automatic snapshots
- Samba file sharing
- NFS exports for other hosts
- SSH access (key-only)
- Firewall + fail2ban
- Auto-updates

### homelab (Full Server)
**For powerful hardware (4GB+ RAM, decent CPU)**

- Everything from storage-node, plus:
- WireGuard VPN (self-hosted, no cloud)
- Home Assistant
- Jellyfin media server
- Transmission torrent client
- Nextcloud cloud storage
- Syncthing file sync
- Docker
- Prometheus + Grafana monitoring
- Python 3.12 + Node.js 22

### pi-gateway (Raspberry Pi Bridge)
**For Raspberry Pi Zero 2W at remote locations**

- WireGuard client connecting to homelab
- Routes local LAN to VPN
- Enables family members to access NAS services

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    WireGuard VPN (10.100.0.0/24)                    │
└─────────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  homelab        │  │  pi-gateway     │  │  pi-gateway     │
│  10.100.0.1     │  │  10.100.0.2     │  │  10.100.0.3     │
│  (powerful box) │  │  (family home 1)│  │  (family home 2)│
│                 │  │                 │  │                 │
│  • WireGuard    │  │  • Routes LAN   │  │  • Routes LAN   │
│  • Jellyfin     │  │    to VPN       │  │    to VPN       │
│  • Home Asst.   │  │                 │  │                 │
│  • Docker       │  └─────────────────┘  └─────────────────┘
│  • Nextcloud    │
│  • Transmission │           ┌─────────────────┐
│  • etc.         │◄──────────│  storage-node   │
│                 │    NFS    │  (QNAP, 1GB RAM)│
└─────────────────┘           │                 │
                              │  • ZFS Storage  │
                              │  • Samba/NFS    │
                              │  • SSH only     │
                              └─────────────────┘
```

## Quick Start

### For storage-node (Minimal NAS)

```bash
# Boot NixOS installer, then:
git clone https://github.com/YOUR_USERNAME/nixnas.git
cd nixnas
chmod +x scripts/*.sh

# Prepare boot USB and ZFS pool
sudo ./scripts/prepare-usb.sh /dev/sdX      # Boot USB
sudo ./scripts/create-zfs-pool.sh /dev/sda /dev/sdb

# Install (select option 1: storage-node)
sudo ./scripts/install.sh
```

### For homelab (Full Server)

```bash
# Same as above, but select option 2: homelab
sudo ./scripts/install.sh
```

### For pi-gateway

```bash
# On a machine with Nix and binfmt enabled:
cd pi-gateway
nix build .#sdImage

# Flash to SD card
sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress
```

## Directory Structure

```
nixnas/
├── flake.nix                    # Main flake with all hosts
├── hosts/
│   ├── storage-node/            # Minimal NAS config
│   │   └── default.nix
│   └── homelab/                 # Full server config
│       └── default.nix
├── modules/                     # Shared NixOS modules
│   ├── base/                    # Users, boot, nix settings
│   ├── storage/                 # ZFS, NFS
│   ├── security/                # SSH, firewall, fail2ban
│   ├── networking/              # WireGuard
│   ├── services/                # Samba, Jellyfin, etc.
│   ├── monitoring/              # Prometheus, Grafana
│   ├── backup/                  # ZFS snapshots
│   └── development/             # Python, Node.js
├── pi-gateway/                  # Separate flake for Pi images
│   ├── flake.nix
│   └── modules/
├── scripts/                     # Installation helpers
│   ├── install.sh
│   ├── prepare-usb.sh
│   └── create-zfs-pool.sh
└── secrets/                     # SOPS-encrypted secrets
```

## Hardware Requirements

### storage-node
- **RAM**: 1GB minimum (512MB for ZFS ARC)
- **CPU**: Any x86_64 (Intel Atom works)
- **Drives**: 2x for ZFS mirror + 1 USB for boot

### homelab
- **RAM**: 4GB+ (more = better ZFS caching)
- **CPU**: Multi-core recommended
- **Drives**: 2x for ZFS mirror + 1 USB/SSD for boot

### pi-gateway
- **Device**: Raspberry Pi Zero 2W (or Pi 3/4)
- **SD Card**: 8GB+
- **Network**: WiFi or Ethernet

## Build Commands

```bash
# Build storage-node
nix build .#nixosConfigurations.storage-node.config.system.build.toplevel

# Build homelab
nix build .#nixosConfigurations.homelab.config.system.build.toplevel

# Build pi-gateway SD image
cd pi-gateway && nix build .#sdImage
```

## Install Commands

```bash
# Install storage-node
sudo nixos-install --flake /mnt/etc/nixos#storage-node --no-root-passwd

# Install homelab
sudo nixos-install --flake /mnt/etc/nixos#homelab --no-root-passwd
```

## Post-Install

### Set Samba Password
```bash
sudo smbpasswd -a admin
```

### Access Services

**storage-node:**
| Service | URL |
|---------|-----|
| SSH | `ssh admin@storage-node.local` |
| Samba | `\\storage-node.local\media` |

**homelab:**
| Service | URL |
|---------|-----|
| SSH | `ssh admin@homelab.local` |
| Samba | `\\homelab.local\media` |
| Home Assistant | http://homelab.local:8123 |
| Jellyfin | http://homelab.local:8096 |
| Transmission | http://homelab.local:9091 |
| Grafana | http://homelab.local:3000 |
| Syncthing | http://homelab.local:8384 |
| Nextcloud | http://homelab.local:8080 |

## Common Commands

```bash
# ZFS status
zpool status
zfs list

# Update system
sudo nixos-rebuild switch --flake /etc/nixos#storage-node  # or #homelab

# View logs
journalctl -u home-assistant -f
```

## License

MIT License
