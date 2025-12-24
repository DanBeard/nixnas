#!/usr/bin/env bash
# =============================================================================
# NixNAS Installation Script
# =============================================================================
# This script installs NixOS on the prepared USB drive.
# Run this from the NixOS installer environment.
#
# Prerequisites:
# 1. Boot from NixOS installer ISO
# 2. USB boot drive prepared (./prepare-usb.sh)
# 3. ZFS pool created (./create-zfs-pool.sh)
#
# Usage: sudo ./install.sh
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    NixNAS Installation                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Check if we're in a NixOS installer environment
if [ ! -f /etc/NIXOS_LUSTRATE ] && [ ! -d /nix/store ]; then
    echo -e "${YELLOW}Warning: This doesn't look like a NixOS installer environment${NC}"
    read -p "Continue anyway? (y/n): " cont
    if [ "$cont" != "y" ]; then
        exit 1
    fi
fi

# =============================================================================
# Step 1: Mount filesystems
# =============================================================================
echo ""
echo -e "${GREEN}Step 1: Mounting filesystems...${NC}"

# Check if USB drive is prepared
if [ ! -b /dev/disk/by-label/NIXOS ]; then
    echo -e "${RED}Error: USB boot drive not found (label: NIXOS)${NC}"
    echo "Run ./prepare-usb.sh first"
    exit 1
fi

if [ ! -b /dev/disk/by-label/BOOT ]; then
    echo -e "${RED}Error: EFI partition not found (label: BOOT)${NC}"
    echo "Run ./prepare-usb.sh first"
    exit 1
fi

# Mount root
echo "Mounting root filesystem..."
mount /dev/disk/by-label/NIXOS /mnt

# Mount boot
echo "Mounting EFI partition..."
mkdir -p /mnt/boot
mount /dev/disk/by-label/BOOT /mnt/boot

# =============================================================================
# Step 2: Import ZFS pool
# =============================================================================
echo ""
echo -e "${GREEN}Step 2: Importing ZFS pool...${NC}"

# Check if pool exists
if ! zpool list tank &>/dev/null; then
    echo "Importing tank pool..."
    zpool import -f tank || {
        echo -e "${YELLOW}Warning: Could not import 'tank' pool${NC}"
        echo "If you haven't created the ZFS pool yet, run ./create-zfs-pool.sh first"
        read -p "Continue without ZFS? (y/n): " cont
        if [ "$cont" != "y" ]; then
            exit 1
        fi
    }
fi

# Mount ZFS datasets
if zpool list tank &>/dev/null; then
    echo "Setting ZFS mountpoints for installation..."
    zfs set mountpoint=/mnt/data tank/data
fi

# =============================================================================
# Step 3: Copy configuration
# =============================================================================
echo ""
echo -e "${GREEN}Step 3: Setting up NixOS configuration...${NC}"

# Create nixos config directory
mkdir -p /mnt/etc/nixos

# Check if we have a local copy of nixnas config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXNAS_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$NIXNAS_DIR/flake.nix" ]; then
    echo "Copying NixNAS configuration..."
    cp -r "$NIXNAS_DIR"/* /mnt/etc/nixos/
else
    echo -e "${YELLOW}NixNAS configuration not found in $NIXNAS_DIR${NC}"
    echo "You'll need to copy the configuration manually or clone from git."
    echo ""
    echo "Option 1: Clone from git (if you've pushed your config):"
    echo "  cd /mnt/etc/nixos && git clone https://github.com/YOUR_USER/nixnas ."
    echo ""
    echo "Option 2: Copy from another location:"
    echo "  cp -r /path/to/nixnas/* /mnt/etc/nixos/"
fi

# =============================================================================
# Step 4: Generate hardware configuration
# =============================================================================
echo ""
echo -e "${GREEN}Step 4: Generating hardware configuration...${NC}"

# Backup existing hardware config
if [ -f /mnt/etc/nixos/hosts/nixnas/hardware-configuration.nix ]; then
    cp /mnt/etc/nixos/hosts/nixnas/hardware-configuration.nix \
       /mnt/etc/nixos/hosts/nixnas/hardware-configuration.nix.template
fi

# Generate hardware config
nixos-generate-config --root /mnt

# Move generated config to hosts directory
if [ -f /mnt/etc/nixos/hardware-configuration.nix ]; then
    mv /mnt/etc/nixos/hardware-configuration.nix \
       /mnt/etc/nixos/hosts/nixnas/hardware-configuration.nix
fi

# Remove generated configuration.nix (we use our own)
rm -f /mnt/etc/nixos/configuration.nix

# =============================================================================
# Step 5: Set hostId
# =============================================================================
echo ""
echo -e "${GREEN}Step 5: Configuring hostId...${NC}"

HOST_ID=$(head -c 8 /etc/machine-id)
echo "Generated hostId: $HOST_ID"

# Update hostId in config
if [ -f /mnt/etc/nixos/hosts/nixnas/default.nix ]; then
    sed -i "s/networking.hostId = \"00000000\"/networking.hostId = \"$HOST_ID\"/" \
        /mnt/etc/nixos/hosts/nixnas/default.nix
    echo "Updated hostId in configuration"
fi

# =============================================================================
# Step 6: Important reminders
# =============================================================================
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}IMPORTANT: Before running nixos-install, please:${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "1. Add your SSH public key to users.nix:"
echo "   Edit: /mnt/etc/nixos/modules/base/users.nix"
echo "   Add your key to: openssh.authorizedKeys.keys"
echo ""
echo "2. Update disk IDs in the host configuration:"
echo "   Edit: /mnt/etc/nixos/hosts/nixnas/default.nix"
echo "   Find disk IDs with: ls -la /dev/disk/by-id/"
echo ""
echo "3. Check network interface name:"
echo "   Run: ip link"
echo "   Update 'externalInterface' in wireguard config if needed"
echo ""
echo "4. Review and customize other settings as needed"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""
read -p "Press Enter when you've made the necessary changes, or Ctrl+C to abort..."

# =============================================================================
# Step 7: Install NixOS
# =============================================================================
echo ""
echo -e "${GREEN}Step 7: Installing NixOS...${NC}"
echo "This may take a while..."
echo ""

nixos-install --flake /mnt/etc/nixos#nixnas --no-root-passwd

# =============================================================================
# Post-installation
# =============================================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 Installation Complete!                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps after reboot:"
echo ""
echo "1. Set Samba password for admin user:"
echo "   sudo smbpasswd -a admin"
echo ""
echo "2. Set up SOPS secrets (for WireGuard, Transmission, etc.):"
echo "   # Generate age key from SSH host key"
echo "   sudo ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub"
echo "   # Add the key to .sops.yaml and encrypt secrets"
echo ""
echo "3. Access services:"
echo "   - SSH: ssh admin@nixnas.local"
echo "   - Samba: \\\\nixnas.local\\media"
echo "   - Home Assistant: http://nixnas.local:8123"
echo "   - Transmission: http://nixnas.local:9091"
echo "   - Jellyfin: http://nixnas.local:8096"
echo "   - Grafana: http://nixnas.local:3000"
echo "   - Syncthing: http://nixnas.local:8384"
echo "   - Nextcloud: http://nixnas.local:8080"
echo ""
echo "4. Configure WireGuard peers in:"
echo "   /etc/nixos/hosts/nixnas/default.nix"
echo ""
echo -e "${CYAN}Reboot now with: reboot${NC}"
