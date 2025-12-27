# NixNAS - Homelab NixOS Configuration

A modular NixOS configuration for a homelab server using OpenMediaVault NAS for storage.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Home Network                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────┐         ┌────────────────────────┐    │
│  │  Homelab PC (NixOS)  │         │  OMV NAS               │    │
│  │  i5, 16GB RAM, 256GB │◄───────►│  ext4 RAID             │    │
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

## Quick Start

### Phase 1: Install NixOS

**Requirements**: PC with 4GB+ RAM, 64GB+ SSD/NVMe, NixOS installer USB

```bash
# 1. Boot from NixOS installer ISO

# 2. Get networking (usually automatic with ethernet)

# 3. Clone this repo
nix-shell -p git
git clone https://github.com/DanBeard/nixnas.git
cd nixnas

# 4. Add your SSH public key
nano modules/base/users.nix
# Find openssh.authorizedKeys.keys and add your key

# 5. Set your OMV NAS IP address
nano hosts/homelab/default.nix
# Find nasAddress = "192.168.1.100" and change it

# 6. Prepare your target drive (replace nvme0n1 with your drive)
chmod +x scripts/*.sh
sudo ./scripts/prepare-usb.sh /dev/nvme0n1

# 7. Install
sudo ./scripts/install.sh

# 8. Reboot (remove installer USB first!)
reboot
```

### Phase 2: First Login

```bash
# 1. SSH into your new homelab
ssh admin@homelab.local

# 2. View generated service passwords
sudo cat /var/lib/nixnas-passwords.txt

# 3. If your NAS IP isn't 192.168.1.100, update it:
sudo nano /etc/nixos/hosts/homelab/default.nix
sudo nixos-rebuild switch --flake /etc/nixos#homelab
```

### Phase 3: Configure OMV NAS

On your OpenMediaVault NAS web UI:

1. **Create shared folders** (Storage → Shared Folders):
   - `media`, `downloads`, `documents`, `backups`, `nextcloud`, `syncthing`

2. **Enable NFS** (Services → NFS → Settings)

3. **Add NFS shares** for each folder:
   - Client: `192.168.1.0/24` (your network range)
   - Privilege: Read/Write
   - Extra options: `subtree_check,insecure`

4. Click Save and Apply

### Phase 4: Set Up Encrypted Secrets (Optional)

After your homelab is working, you can encrypt your service passwords:

```bash
sudo /etc/nixos/scripts/setup-sops.sh
```

This encrypts your passwords so you can safely commit them to git.

---

## Services

| Service | URL | Description |
|---------|-----|-------------|
| SSH | `ssh admin@homelab.local` | Remote access |
| Home Assistant | http://homelab.local:8123 | Home automation |
| Jellyfin | http://homelab.local:8096 | Media server |
| Transmission | http://homelab.local:9091 | Torrent client |
| Grafana | http://homelab.local:3000 | Monitoring dashboards |
| Syncthing | http://homelab.local:8384 | File sync |
| Nextcloud | http://homelab.local:8080 | Cloud storage |

**Note**: Samba file sharing is on your OMV NAS, not the homelab.

---

## Directory Structure

```
nixnas/
├── flake.nix                    # Main flake configuration
├── hosts/
│   └── homelab/                 # Homelab host config
│       ├── default.nix          # Main config (services, storage)
│       └── hardware-configuration.nix
├── modules/                     # Shared NixOS modules
│   ├── base/                    # Users, boot, nix settings
│   ├── storage/                 # NFS client configuration
│   ├── security/                # SSH, firewall, fail2ban
│   ├── networking/              # WireGuard VPN
│   ├── services/                # Jellyfin, Home Assistant, etc.
│   ├── monitoring/              # Prometheus, Grafana
│   └── development/             # Python, Node.js
├── pi-gateway/                  # Raspberry Pi VPN gateway (separate)
├── scripts/
│   ├── install.sh               # Main installation script
│   ├── prepare-usb.sh           # Partition target drive
│   └── setup-sops.sh            # Set up encrypted secrets
└── secrets/                     # SOPS-encrypted secrets (after setup)
```

---

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

# View generated passwords
sudo cat /var/lib/nixnas-passwords.txt

# Edit secrets (after SOPS setup)
cd /etc/nixos && sops secrets/secrets.yaml
```

---

## WireGuard VPN

WireGuard keys are automatically generated on first boot.

```bash
# View your server's public key
cat /etc/wireguard/public.key

# Add peers in /etc/nixos/hosts/homelab/default.nix:
nixnas.wireguard.peers = [
  {
    name = "phone";
    publicKey = "PEER_PUBLIC_KEY";
    allowedIPs = [ "10.100.0.2/32" ];
  }
];

# Then rebuild
sudo nixos-rebuild switch --flake /etc/nixos#homelab
```

---

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

- Verify SSH key was added to `modules/base/users.nix`
- Check homelab IP on console/monitor
- Try: `ssh -v admin@IP_ADDRESS`

### Service not starting

```bash
systemctl status servicename
journalctl -u servicename -n 50
```

### View generated passwords

```bash
sudo cat /var/lib/nixnas-passwords.txt
```

---

## License

MIT License
