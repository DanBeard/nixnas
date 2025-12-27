#!/usr/bin/env bash
# =============================================================================
# NixNAS Homelab Installation Script
# =============================================================================
# This script installs NixOS on your homelab PC.
# Run this from the NixOS installer environment.
#
# Prerequisites:
# 1. Boot from NixOS installer ISO
# 2. Clone this repo and add your SSH key to modules/base/users.nix
# 3. Run ./prepare-usb.sh on your target drive (NVMe/SSD)
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
echo "║              NixNAS Homelab Installation                       ║"
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

HOST_NAME="homelab"

# =============================================================================
# Step 1: Mount filesystems
# =============================================================================
echo ""
echo -e "${GREEN}Step 1: Mounting filesystems...${NC}"

# Check if drive is prepared
if [ ! -b /dev/disk/by-label/NIXOS ]; then
    echo -e "${RED}Error: Boot drive not found (label: NIXOS)${NC}"
    echo "Run ./prepare-usb.sh on your target drive first"
    exit 1
fi

if [ ! -b /dev/disk/by-label/BOOT ]; then
    echo -e "${RED}Error: EFI partition not found (label: BOOT)${NC}"
    echo "Run ./prepare-usb.sh on your target drive first"
    exit 1
fi

# Unmount if already mounted (for re-runs)
if mountpoint -q /mnt/boot 2>/dev/null; then
    echo "Unmounting existing /mnt/boot..."
    umount /mnt/boot
fi
if mountpoint -q /mnt 2>/dev/null; then
    echo "Unmounting existing /mnt..."
    umount /mnt
fi

# Mount root
echo "Mounting root filesystem..."
mount /dev/disk/by-label/NIXOS /mnt

# Mount boot
echo "Mounting EFI partition..."
mkdir -p /mnt/boot
mount /dev/disk/by-label/BOOT /mnt/boot

echo -e "  ${GREEN}✓${NC} Filesystems mounted"

# =============================================================================
# Step 2: Copy configuration
# =============================================================================
echo ""
echo -e "${GREEN}Step 2: Setting up NixOS configuration...${NC}"

# Clean any previous installation attempts
if [ -d /mnt/etc/nixos ]; then
    echo "Cleaning previous configuration..."
    rm -rf /mnt/etc/nixos
fi

# Create nixos config directory
mkdir -p /mnt/etc/nixos

# Check if we have a local copy of nixnas config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXNAS_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$NIXNAS_DIR/flake.nix" ]; then
    echo "Copying NixNAS configuration..."
    cp -r "$NIXNAS_DIR"/* /mnt/etc/nixos/

    # Remove any stray generated files that might cause conflicts
    rm -f /mnt/etc/nixos/configuration.nix
    rm -f /mnt/etc/nixos/hardware-configuration.nix
    echo -e "  ${GREEN}✓${NC} Configuration copied"
else
    echo -e "${RED}Error: NixNAS configuration not found in $NIXNAS_DIR${NC}"
    echo "Make sure you're running this from inside the nixnas directory."
    exit 1
fi

# =============================================================================
# Step 3: Generate hardware configuration
# =============================================================================
echo ""
echo -e "${GREEN}Step 3: Generating hardware configuration...${NC}"

# Backup existing hardware config template (for reference)
if [ -f "/mnt/etc/nixos/hosts/homelab/hardware-configuration.nix" ]; then
    cp "/mnt/etc/nixos/hosts/homelab/hardware-configuration.nix" \
       "/mnt/etc/nixos/hosts/homelab/hardware-configuration.nix.template"
fi

# Generate hardware config to a temporary location first
mkdir -p /mnt/etc/nixos/generated
nixos-generate-config --root /mnt --dir /mnt/etc/nixos/generated

# Move generated hardware config to the correct hosts directory
if [ -f /mnt/etc/nixos/generated/hardware-configuration.nix ]; then
    mv /mnt/etc/nixos/generated/hardware-configuration.nix \
       "/mnt/etc/nixos/hosts/homelab/hardware-configuration.nix"
    echo -e "  ${GREEN}✓${NC} Generated hardware-configuration.nix"
fi

# Clean up generated files we don't need
rm -rf /mnt/etc/nixos/generated
rm -f /mnt/etc/nixos/configuration.nix
rm -f /mnt/etc/nixos/hardware-configuration.nix

# =============================================================================
# Step 4: Auto-configure system settings
# =============================================================================
echo ""
echo -e "${GREEN}Step 4: Auto-configuring system settings...${NC}"

CONFIG_FILE="/mnt/etc/nixos/hosts/homelab/default.nix"

if [ -f "$CONFIG_FILE" ]; then
    # --- Network interface (for WireGuard NAT) ---
    PRIMARY_IFACE=""
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do
        case "$iface" in
            docker*|br-*|veth*|virbr*|wg*|tun*|tap*) continue ;;
        esac
        if [ -f "/sys/class/net/$iface/carrier" ] && [ "$(cat /sys/class/net/$iface/carrier 2>/dev/null)" = "1" ]; then
            PRIMARY_IFACE="$iface"
            break
        fi
    done

    if [ -z "$PRIMARY_IFACE" ]; then
        PRIMARY_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(en|eth)' | head -1)
    fi

    if [ -n "$PRIMARY_IFACE" ] && [ "$PRIMARY_IFACE" != "eth0" ]; then
        if grep -q 'externalInterface = "eth0"' "$CONFIG_FILE"; then
            sed -i "s/externalInterface = \"eth0\"/externalInterface = \"$PRIMARY_IFACE\"/" "$CONFIG_FILE"
            echo -e "  ${GREEN}✓${NC} Set network interface to $PRIMARY_IFACE"
        fi
    else
        echo -e "  ${GREEN}✓${NC} Network interface: ${PRIMARY_IFACE:-eth0}"
    fi

    # --- Check SSH key ---
    USERS_FILE="/mnt/etc/nixos/modules/base/users.nix"
    if [ -f "$USERS_FILE" ]; then
        if grep -q 'ssh-ed25519' "$USERS_FILE" || grep -q 'ssh-rsa' "$USERS_FILE"; then
            echo -e "  ${GREEN}✓${NC} SSH public key found"
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

    # --- Check NFS server address ---
    if grep -q 'nasAddress = "192.168.1.100"' "$CONFIG_FILE"; then
        echo -e "  ${YELLOW}⚠${NC} NAS IP is default (192.168.1.100)"
        echo "     Update after install if different."
    else
        echo -e "  ${GREEN}✓${NC} NAS address configured"
    fi
else
    echo -e "${RED}Error: Config file not found at $CONFIG_FILE${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Configuration complete!${NC}"

# =============================================================================
# Step 5: Install NixOS
# =============================================================================
echo ""
echo -e "${GREEN}Step 5: Installing NixOS...${NC}"
echo "This may take 10-30 minutes depending on your internet speed..."
echo ""

nixos-install --flake "/mnt/etc/nixos#${HOST_NAME}" --no-root-passwd

# =============================================================================
# Post-installation
# =============================================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 Installation Complete!                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Your homelab is ready! After reboot:"
echo ""
echo -e "${CYAN}1. SSH in:${NC}"
echo "   ssh admin@homelab.local"
echo ""
echo -e "${CYAN}2. View generated service passwords:${NC}"
echo "   sudo cat /var/lib/nixnas-passwords.txt"
echo ""
echo -e "${CYAN}3. Configure your OMV NAS IP (if not 192.168.1.100):${NC}"
echo "   sudo nano /etc/nixos/hosts/homelab/default.nix"
echo "   # Change: nasAddress = \"YOUR_NAS_IP\";"
echo "   sudo nixos-rebuild switch --flake /etc/nixos#homelab"
echo ""
echo -e "${CYAN}4. Access your services:${NC}"
echo "   • Home Assistant:  http://homelab.local:8123"
echo "   • Jellyfin:        http://homelab.local:8096"
echo "   • Transmission:    http://homelab.local:9091"
echo "   • Grafana:         http://homelab.local:3000"
echo "   • Syncthing:       http://homelab.local:8384"
echo "   • Nextcloud:       http://homelab.local:8080"
echo ""
echo -e "${CYAN}5. Optional - Set up encrypted secrets:${NC}"
echo "   sudo /etc/nixos/scripts/setup-sops.sh"
echo ""
echo -e "${YELLOW}NOTE: File sharing (Samba) is on your OMV NAS, not this homelab.${NC}"
echo ""
echo -e "${GREEN}Reboot now with: reboot${NC}"
echo ""
