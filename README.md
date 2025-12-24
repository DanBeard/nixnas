# NixNAS - Self-Hosted NixOS Network Attached Storage

A fully self-hosted, cloud-independent NAS configuration built on NixOS with ZFS for data protection.

## Features

### Core Services
- **ZFS Mirror** - RAID1-like data protection with automatic snapshots
- **Samba** - Windows/macOS/Linux file sharing with Time Machine support
- **SFTP** - Secure file transfer via SSH
- **WireGuard VPN** - Self-hosted VPN for remote access (no cloud dependencies)

### Applications
- **Home Assistant** - Home automation (local-only, no cloud)
- **Transmission** - Torrent client with web UI
- **Jellyfin** - Media server with hardware transcoding
- **Nextcloud** - Self-hosted cloud storage, calendar, contacts
- **Syncthing** - P2P file sync (LAN + WireGuard only)

### Development Tools
- **Docker** - Container runtime with compose support
- **Python 3.12** - With pip, virtualenv, and common tools
- **Node.js 22 LTS** - With Yarn and pnpm

### Security
- **Automatic Updates** - Daily security updates at 3 AM
- **Fail2ban** - Brute-force protection
- **Hardened SSH** - Key-only authentication, strong ciphers
- **Firewall** - nftables with sensible defaults

### Monitoring
- **Prometheus** - Metrics collection with ZFS exporter
- **Grafana** - Dashboards and visualization

## Hardware Requirements

- **Boot Drive**: Fast USB drive (32GB+ recommended) - this is where NixOS lives
- **Data Drives**: 2x identical drives for ZFS mirror - this is where your files live
- **Installer USB**: Another USB to boot the NixOS installer from (can reuse after install)
- **RAM**: 8GB minimum, 16GB+ recommended (ZFS uses RAM for caching)
- **CPU**: x86_64 (Intel/AMD 64-bit)
- **Network**: Ethernet connection (for installation)

## Installation Guide (Step-by-Step)

### Before You Start: Prepare on Your Current Computer

**Step 0.1: Push this config to GitHub (so you can clone it on the NAS)**

```bash
# On your current computer (not the NAS)
cd /home/deck/Projects/nixnas

# Initialize git repo
git init
git add .
git commit -m "Initial NixNAS configuration"

# Create a repo on GitHub, then:
git remote add origin https://github.com/YOUR_USERNAME/nixnas.git
git branch -M main
git push -u origin main
```

**Step 0.2: Get your SSH public key ready**

You'll need this to log into the NAS after installation:
```bash
# If you don't have one, generate it:
ssh-keygen -t ed25519

# View your public key (copy this, you'll need it):
cat ~/.ssh/id_ed25519.pub
```

**Step 0.3: Download NixOS Installer**

1. Go to https://nixos.org/download/
2. Download "NixOS 24.11" → "Minimal ISO image (64-bit Intel/AMD)"
3. Flash it to a USB drive using Balena Etcher, Rufus, or `dd`

### On The NAS Hardware

**Step 1: Boot the NixOS Installer**

1. Plug the installer USB into the NAS
2. Also plug in your boot USB drive (the fast one for the OS)
3. Connect ethernet cable
4. Boot from the installer USB (usually F12 or F2 for boot menu)
5. Select the NixOS installer entry
6. Wait for the command prompt (you'll see `nixos@nixos:~$`)

**Step 2: Verify Network Connection**

```bash
# Check if you have an IP address
ip addr

# Test internet connectivity
ping -c 3 google.com

# If no connection, for DHCP on ethernet:
sudo systemctl start dhcpcd
```

**Step 3: Identify Your Drives**

```bash
# List all drives - identify which is which:
lsblk

# Example output:
# sda      32G   <- This might be your boot USB
# sdb     4TB   <- Data drive 1
# sdc     4TB   <- Data drive 2
# sdd     16G   <- NixOS installer USB (you're booted from this)
```

**Note down which `/dev/sdX` is which:**
- Your **boot USB** (where NixOS will be installed) - e.g., `/dev/sda`
- Your two **data drives** (for ZFS mirror) - e.g., `/dev/sdb` and `/dev/sdc`

Don't worry about `/dev/disk/by-id/` paths - the scripts handle that automatically!

**Step 4: Clone This Repository**

```bash
# Install git (it's available in the installer)
nix-shell -p git

# Clone your config
cd ~
git clone https://github.com/YOUR_USERNAME/nixnas.git
cd nixnas
```

**Step 5: Edit Configuration Before Installing**

```bash
# Use nano (easier) or vim to edit files
nano modules/base/users.nix
```

**Add your SSH public key** (the one from Step 0.2):
```nix
# Find this section and add your key:
openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3Nz... your-key-here"
];
```

Save and exit (Ctrl+X, then Y, then Enter in nano).

**Step 6: Prepare the Boot USB Drive**

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Identify your boot USB (example: /dev/sda)
# WARNING: This erases the drive!
sudo ./scripts/prepare-usb.sh /dev/sdX   # Replace X with your boot drive letter
```

**Step 7: Create the ZFS Pool**

```bash
# Just use the simple /dev/sdX names - the script automatically finds stable IDs!
# Example: if your data drives are sdb and sdc:
sudo ./scripts/create-zfs-pool.sh /dev/sdb /dev/sdc tank

# The script will:
# - Look up the stable /dev/disk/by-id/ paths automatically
# - Show you the disk sizes and IDs for confirmation
# - Create the pool and datasets
# - Print the hostId and disk IDs to add to your config
```

**Step 8: Run the Install Script**

```bash
# This script handles everything:
# - Mounts boot USB and EFI partition
# - Imports ZFS pool and sets mountpoints
# - Copies configuration to /mnt/etc/nixos/
# - Generates hardware-configuration.nix
# - Auto-configures hostId and network interface
# - Validates SSH key and disk configuration
# - Runs nixos-install

sudo ./scripts/install.sh
```

The install takes 10-30 minutes depending on your internet speed.

**Step 9: Reboot**

```bash
# Remove the installer USB first!
sudo reboot
```

### After First Boot

**Step 10: Log In and Verify**

```bash
# From another computer on your network:
ssh admin@nixnas.local

# Or if mDNS doesn't work, find the IP:
# (check your router, or the NAS console shows it)
ssh admin@192.168.1.XXX
```

**Step 11: Set Up Samba Password**

```bash
# On the NAS:
sudo smbpasswd -a admin
# Enter a password for Samba file sharing
```

**Step 12: Set Up Secrets (Optional but Recommended)**

```bash
# Generate age key from SSH host key
sudo ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub

# Copy the output (starts with "age1...")
# Edit .sops.yaml and replace the placeholder key

# Then encrypt your secrets:
cd /etc/nixos
sops secrets/secrets.yaml

# Rebuild to apply:
sudo nixos-rebuild switch --flake /etc/nixos#nixnas
```

## You're Done!

Your NAS should now be running. Access services at:

| Service | URL |
|---------|-----|
| SSH | `ssh admin@nixnas.local` |
| Samba | `\\nixnas.local\media` (Windows) or `smb://nixnas.local/media` (Mac) |
| Home Assistant | http://nixnas.local:8123 |
| Transmission | http://nixnas.local:9091 |
| Jellyfin | http://nixnas.local:8096 |
| Grafana | http://nixnas.local:3000 |
| Syncthing | http://nixnas.local:8384 |
| Nextcloud | http://nixnas.local:8080 |

---

## WireGuard VPN Setup

### Generate Client Keys

```bash
wg genkey | tee client_private.key | wg pubkey > client_public.key
```

### Add Peer to NixOS Config

Edit `/etc/nixos/hosts/nixnas/default.nix`:

```nix
nixnas.wireguard.peers = [
  {
    name = "phone";
    publicKey = "CLIENT_PUBLIC_KEY";
    allowedIPs = [ "10.100.0.2/32" ];
  }
];
```

Then rebuild: `sudo nixos-rebuild switch --flake /etc/nixos#nixnas`

### Client Configuration

```ini
[Interface]
PrivateKey = CLIENT_PRIVATE_KEY
Address = 10.100.0.2/32
DNS = 10.100.0.1

[Peer]
PublicKey = SERVER_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = YOUR_PUBLIC_IP:51820
PersistentKeepalive = 25
```

Get server public key: `sudo cat /etc/wireguard/private | wg pubkey`

---

## Directory Structure

```
/data/
├── media/          # Movies, TV, Music
├── downloads/      # Torrent downloads
├── documents/      # Personal documents
├── backups/        # Backup storage
│   └── timemachine/  # macOS Time Machine
├── docker/         # Docker volumes
├── home-assistant/ # Home Assistant config
├── nextcloud/      # Nextcloud data
├── jellyfin/       # Jellyfin metadata
└── syncthing/      # Syncthing data
```

---

## Common Commands

### View ZFS Status
```bash
zpool status        # Pool health
zfs list            # Dataset usage
zfs list -t snap    # List snapshots
```

### Manual Snapshot
```bash
sudo zfs snapshot tank/data/documents@manual-$(date +%Y-%m-%d)
```

### Update System
```bash
cd /etc/nixos
sudo nixos-rebuild switch --flake .#nixnas
```

### View Service Logs
```bash
journalctl -u home-assistant -f    # Follow Home Assistant logs
systemctl status jellyfin          # Check Jellyfin status
```

### Rollback to Previous Config
```bash
# List available generations
sudo nix-env --list-generations -p /nix/var/nix/profiles/system

# Rollback to previous
sudo nixos-rebuild switch --rollback
```

---

## Troubleshooting

### Can't SSH after install
- Check if NAS is on network: look at console for IP
- Verify SSH key was added correctly
- Try: `ssh -v admin@IP_ADDRESS` for verbose output

### ZFS Pool Not Importing
```bash
sudo zpool import           # List available pools
sudo zpool import -f tank   # Force import
```

### Service Not Starting
```bash
systemctl status servicename
journalctl -u servicename -n 50
```

### Rebuild Fails
```bash
# Check syntax
nix flake check /etc/nixos

# Try with more output
sudo nixos-rebuild switch --flake /etc/nixos#nixnas --show-trace
```

---

## Cloud Independence

This NAS is designed to be fully self-hosted with no cloud dependencies:

- **WireGuard**: Direct P2P VPN (no coordination servers)
- **Home Assistant**: Local integrations only
- **Syncthing**: Global discovery disabled (LAN + WireGuard)
- **Nextcloud**: Self-hosted cloud storage
- **Jellyfin**: Local media server

The only external connections are:
- NixOS package updates (can set up local cache)
- NTP time sync (can use local server)

---

## License

MIT License - Feel free to use and modify for your own NAS setup.
