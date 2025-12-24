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
# Step 5: Auto-configure system settings
# =============================================================================
echo ""
echo -e "${GREEN}Step 5: Auto-configuring system settings...${NC}"

CONFIG_FILE="/mnt/etc/nixos/hosts/nixnas/default.nix"

if [ -f "$CONFIG_FILE" ]; then
    # --- hostId ---
    HOST_ID=$(head -c 8 /etc/machine-id)
    if grep -q 'networking.hostId = "00000000"' "$CONFIG_FILE"; then
        sed -i "s/networking.hostId = \"00000000\"/networking.hostId = \"$HOST_ID\"/" "$CONFIG_FILE"
        echo -e "  ${GREEN}✓${NC} Set hostId to $HOST_ID"
    elif grep -q 'networking.hostId = "[0-9a-f]\{8\}"' "$CONFIG_FILE"; then
        echo -e "  ${YELLOW}⚠${NC} hostId already configured"
    fi

    # --- Network interface (for WireGuard NAT) ---
    # Find the primary ethernet interface (first non-loopback, non-virtual interface with a link)
    PRIMARY_IFACE=""
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
        # Skip virtual interfaces
        case "$iface" in
            docker*|br-*|veth*|virbr*|wg*|tun*|tap*) continue ;;
        esac
        # Check if it has a carrier (cable connected)
        if [ -f "/sys/class/net/$iface/carrier" ] && [ "$(cat /sys/class/net/$iface/carrier 2>/dev/null)" = "1" ]; then
            PRIMARY_IFACE="$iface"
            break
        fi
    done

    # Fallback: just get first ethernet-like interface
    if [ -z "$PRIMARY_IFACE" ]; then
        PRIMARY_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(en|eth)' | head -1)
    fi

    if [ -n "$PRIMARY_IFACE" ] && [ "$PRIMARY_IFACE" != "eth0" ]; then
        if grep -q 'externalInterface = "eth0"' "$CONFIG_FILE"; then
            sed -i "s/externalInterface = \"eth0\"/externalInterface = \"$PRIMARY_IFACE\"/" "$CONFIG_FILE"
            echo -e "  ${GREEN}✓${NC} Set externalInterface to $PRIMARY_IFACE"
        fi
    elif [ -n "$PRIMARY_IFACE" ]; then
        echo -e "  ${GREEN}✓${NC} externalInterface is eth0 (correct)"
    else
        echo -e "  ${YELLOW}⚠${NC} Could not detect network interface, leaving as eth0"
    fi

    # --- Check SSH key ---
    USERS_FILE="/mnt/etc/nixos/modules/base/users.nix"
    if [ -f "$USERS_FILE" ]; then
        if grep -q 'ssh-ed25519' "$USERS_FILE" || grep -q 'ssh-rsa' "$USERS_FILE"; then
            echo -e "  ${GREEN}✓${NC} SSH public key found in users.nix"
        else
            echo -e "  ${RED}✗${NC} No SSH key found in users.nix!"
            echo ""
            echo -e "  ${YELLOW}You need to add your SSH public key to log in after install.${NC}"
            echo "  Edit: $USERS_FILE"
            echo "  Add your key to: openssh.authorizedKeys.keys"
            echo ""
            read -p "  Press Enter after adding your SSH key, or Ctrl+C to abort..."
        fi
    fi

    # --- Check dataDisks ---
    if grep -q 'CHANGE-ME-DISK' "$CONFIG_FILE"; then
        echo -e "  ${RED}✗${NC} dataDisks not configured!"
        echo ""
        echo -e "  ${YELLOW}Run create-zfs-pool.sh first to auto-configure disk IDs.${NC}"
        echo ""
        read -p "  Press Enter if you want to continue anyway, or Ctrl+C to abort..."
    else
        echo -e "  ${GREEN}✓${NC} dataDisks configured"
    fi
else
    echo -e "${RED}Error: Config file not found at $CONFIG_FILE${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Configuration complete!${NC}"
echo ""

# =============================================================================
# Step 6: Install NixOS
# =============================================================================
echo ""
echo -e "${GREEN}Step 6: Installing NixOS...${NC}"
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
