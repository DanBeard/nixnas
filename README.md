# NixNAS - Multi-Host NixOS Home Infrastructure

A modular NixOS configuration for home infrastructure with multiple host types.

## Quick Start: Homelab with OMV NAS

**Your setup**: Homelab PC (i5, 16GB RAM, 256GB SSD) + OpenMediaVault NAS for storage

### Step 1: Identify Your Drives

```bash
# In the NixOS installer, find your SSD
lsblk

# Example output - identify your 256GB SSD (e.g., /dev/sda)
# NAME   SIZE
# sda    256G   <- Your SSD for NixOS
# sdb    16G    <- Your installer USB (ignore this)
```

### Step 2: Clone This Repository

```bash
# Get git
nix-shell -p git

# Clone the config
cd ~
git clone https://github.com/DanBeard/nixnas.git
cd nixnas
```

### Step 3: Add Your SSH Public Key

```bash
nano modules/base/users.nix

# Find the openssh.authorizedKeys.keys section and add your key:
# openssh.authorizedKeys.keys = [
#   "ssh-ed25519 AAAAC3Nz... your-key-here"
# ];
```

Save with Ctrl+X, Y, Enter.

### Step 4: Set Your OMV NAS IP Address

```bash
nano hosts/homelab/default.nix

# Find this line (around line 40):
#   nasAddress = "192.168.1.100";
# Change it to your OMV NAS's actual IP address
```

Save with Ctrl+X, Y, Enter.

### Step 5: Prepare the SSD

```bash
chmod +x scripts/*.sh

# Replace /dev/sda with YOUR SSD device!
# WARNING: This erases the drive!
sudo ./scripts/prepare-usb.sh /dev/sda
```

### Step 6: Run the Installer

```bash
sudo ./scripts/install.sh

# When prompted, select:
#   2) homelab - Full server (4GB+ RAM, NFS client, all services)
```

Wait for installation to complete (10-30 minutes).

### Step 7: Reboot

```bash
# Remove the installer USB first!
reboot
```

### Step 8: After First Boot - Configure OMV NAS

**On your OpenMediaVault NAS web UI:**

1. Go to **Storage → Shared Folders** and create:
   - `media`
   - `downloads`
   - `documents`
   - `backups`
   - `nextcloud`
   - `syncthing`

2. Go to **Services → NFS → Settings** and enable NFS

3. Go to **Services → NFS → Shares** and add each folder:
   - Shared folder: (select each one)
   - Client: `192.168.1.0/24` (or your network range)
   - Privilege: Read/Write
   - Extra options: `subtree_check,insecure`

4. Click Save and Apply

### Step 9: Verify NFS Mounts

```bash
# SSH into your homelab
ssh admin@homelab.local

# Check if NFS is mounted
ls /mnt/nas/media

# If empty, the NAS might not be configured yet or IP is wrong
# Check/update the NAS IP:
sudo nano /etc/nixos/hosts/homelab/default.nix
sudo nixos-rebuild switch --flake /etc/nixos#homelab
```

### You're Done!

Access your services:

| Service | URL |
|---------|-----|
| SSH | `ssh admin@homelab.local` |
| Home Assistant | http://homelab.local:8123 |
| Jellyfin | http://homelab.local:8096 |
| Transmission | http://homelab.local:9091 |
| Grafana | http://homelab.local:3000 |
| Syncthing | http://homelab.local:8384 |
| Nextcloud | http://homelab.local:8080 |

**Note**: File sharing (Samba) is on your OMV NAS, not the homelab.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Home Network                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────┐         ┌────────────────────────┐    │
│  │  Homelab PC (NixOS)  │         │  OMV NAS               │    │
│  │  i5, 16GB RAM, 256GB │◄───────►│  ext4 RAID1            │    │
│  │                      │  NFS    │                        │    │
│  │  LOCAL (SSD):        │         │  Shared directories:   │    │
│  │  • NixOS system      │         │  • media               │    │
│  │  • Docker volumes    │         │  • downloads           │    │
│  │  • Home Assistant    │         │  • documents           │    │
│  │  • Jellyfin cache    │         │  • backups             │    │
│  │                      │         │  • nextcloud           │    │
│  │  NETWORK (/mnt/nas): │         │  • syncthing           │    │
│  │  • Media library     │         │                        │    │
│  │  • Downloads         │         │  Also provides:        │    │
│  │  • Documents         │         │  • Samba file sharing  │    │
│  │  • Backups           │         │                        │    │
│  └──────────────────────┘         └────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Host Configurations

### homelab (Full Server)
**For powerful hardware (4GB+ RAM, decent CPU) with external NAS storage**

- WireGuard VPN (self-hosted, no cloud)
- Home Assistant
- Jellyfin media server
- Transmission torrent client
- Nextcloud cloud storage
- Syncthing file sync
- Docker
- Prometheus + Grafana monitoring
- Python 3.12 + Node.js 22
- NFS client (mounts storage from OMV NAS)

### storage-node (Minimal NAS)
**For memory-constrained hardware (1GB RAM, Intel Atom, QNAP, etc.)**

- ZFS mirror with automatic snapshots
- Samba file sharing
- NFS exports for other hosts
- SSH access (key-only)
- Firewall + fail2ban
- Auto-updates

### pi-gateway (Raspberry Pi Bridge)
**For Raspberry Pi Zero 2W at remote locations**

- WireGuard client connecting to homelab
- Routes local LAN to VPN
- Enables family members to access services

## Directory Structure

```
nixnas/
├── flake.nix                    # Main flake with all hosts
├── hosts/
│   ├── storage-node/            # Minimal NAS config (ZFS)
│   │   └── default.nix
│   └── homelab/                 # Full server config (NFS client)
│       └── default.nix
├── modules/                     # Shared NixOS modules
│   ├── base/                    # Users, boot, nix settings
│   ├── storage/                 # ZFS, NFS server, NFS client
│   ├── security/                # SSH, firewall, fail2ban
│   ├── networking/              # WireGuard
│   ├── services/                # Jellyfin, Home Assistant, etc.
│   ├── monitoring/              # Prometheus, Grafana
│   └── development/             # Python, Node.js
├── pi-gateway/                  # Separate flake for Pi images
├── scripts/                     # Installation helpers
│   ├── install.sh
│   ├── prepare-usb.sh
│   └── create-zfs-pool.sh
└── secrets/                     # SOPS-encrypted secrets
```

## Common Commands

```bash
# Update system after config changes
sudo nixos-rebuild switch --flake /etc/nixos#homelab

# View service logs
journalctl -u home-assistant -f
journalctl -u jellyfin -f

# Check NFS mounts
mount | grep nfs
df -h /mnt/nas/*

# Restart a service
sudo systemctl restart jellyfin
```

## Troubleshooting

### NFS mounts not working
```bash
# Check if NAS is reachable
ping 192.168.1.100  # your NAS IP

# Check NFS exports on NAS
showmount -e 192.168.1.100

# Manually test mount
sudo mount -t nfs 192.168.1.100:/srv/media /mnt/test
```

### Can't SSH after install
- Check if homelab is on network (look at console for IP)
- Verify SSH key was added correctly to `modules/base/users.nix`
- Try: `ssh -v admin@IP_ADDRESS` for verbose output

### Service not starting
```bash
systemctl status servicename
journalctl -u servicename -n 50
```

## License

MIT License
