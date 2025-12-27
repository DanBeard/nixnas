#!/usr/bin/env bash
# =============================================================================
# Homelab Ubuntu Server Setup Script
# =============================================================================
# This script prepares a fresh Ubuntu Server installation for the homelab.
# It installs Docker, sets up NFS mounts, and creates necessary directories.
#
# Usage: sudo ./scripts/setup.sh
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "=============================================="
echo "       Homelab Ubuntu Server Setup"
echo "=============================================="
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_DIR="$(dirname "$SCRIPT_DIR")"

# Check for .env file
if [ ! -f "$HOMELAB_DIR/.env" ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please copy .env.example to .env and configure it first:"
    echo "  cp .env.example .env"
    echo "  nano .env"
    exit 1
fi

# Load environment variables (set -a exports them automatically)
set -a
source "$HOMELAB_DIR/.env"
set +a

# Verify NAS_IP is set
if [ -z "${NAS_IP:-}" ] || [ "$NAS_IP" = "192.168.1.100" ]; then
    echo -e "${YELLOW}Warning: NAS_IP is set to default (192.168.1.100)${NC}"
    read -p "Is this correct? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Please update NAS_IP in .env and run again."
        exit 1
    fi
fi

# =============================================================================
# Step 1: Update system
# =============================================================================
echo ""
echo -e "${GREEN}Step 1: Updating system packages...${NC}"

apt-get update
apt-get upgrade -y

echo -e "  ${GREEN}✓${NC} System updated"

# =============================================================================
# Step 2: Install required packages
# =============================================================================
echo ""
echo -e "${GREEN}Step 2: Installing required packages...${NC}"

apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    nfs-common \
    git \
    htop \
    ncdu \
    tmux

echo -e "  ${GREEN}✓${NC} Packages installed"

# =============================================================================
# Step 3: Install Docker
# =============================================================================
echo ""
echo -e "${GREEN}Step 3: Installing Docker...${NC}"

if command -v docker &> /dev/null; then
    echo -e "  ${YELLOW}⚠${NC} Docker already installed, skipping"
else
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add current user to docker group
    REAL_USER="${SUDO_USER:-$USER}"
    usermod -aG docker "$REAL_USER"

    echo -e "  ${GREEN}✓${NC} Docker installed"
    echo -e "  ${YELLOW}Note: Log out and back in for docker group to take effect${NC}"
fi

# =============================================================================
# Step 4: Create NFS mount point
# =============================================================================
echo ""
echo -e "${GREEN}Step 4: Creating NFS mount directory...${NC}"

mkdir -p /mnt/nas
chmod 755 /mnt/nas

echo -e "  ${GREEN}✓${NC} Mount directory created"

# =============================================================================
# Step 5: Configure NFS mount in fstab
# =============================================================================
echo ""
echo -e "${GREEN}Step 5: Configuring NFS mount...${NC}"

# Backup fstab
cp /etc/fstab /etc/fstab.backup

# Clean up old individual NFS mounts (from previous setup versions)
echo "Cleaning up any old NFS entries..."
sed -i '/\/mnt\/nas\/media/d' /etc/fstab
sed -i '/\/mnt\/nas\/downloads/d' /etc/fstab
sed -i '/\/mnt\/nas\/documents/d' /etc/fstab
sed -i '/\/mnt\/nas\/backups/d' /etc/fstab
sed -i '/\/mnt\/nas\/nextcloud/d' /etc/fstab
sed -i '/\/mnt\/nas\/syncthing/d' /etc/fstab
# Also clean up old /srv/homelab entries
sed -i '/\/srv\/homelab.*\/mnt\/nas/d' /etc/fstab

# Check if correct mount already exists
if grep -q "${NAS_IP}:/homelab[[:space:]]*/mnt/nas" /etc/fstab; then
    echo -e "  ${YELLOW}⚠${NC} NFS mount already in fstab, skipping"
else
    # Remove any old /mnt/nas entries before adding new one
    sed -i '/^[^#].*[[:space:]]\/mnt\/nas[[:space:]]/d' /etc/fstab

    cat >> /etc/fstab << EOF

# NAS NFS Mount (added by homelab setup)
# Single share - subdirectories created after mounting
${NAS_IP}:/homelab  /mnt/nas  nfs  defaults,_netdev,soft,timeo=100  0 0
EOF
    echo -e "  ${GREEN}✓${NC} NFS mount added to /etc/fstab"
fi

# =============================================================================
# Step 6: Mount NFS share and create subdirectories
# =============================================================================
echo ""
echo -e "${GREEN}Step 6: Mounting NFS share...${NC}"

NAS_MOUNTED=false

echo "Testing connection to NAS at $NAS_IP..."
if ping -c 1 -W 3 "$NAS_IP" &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} NAS is reachable"

    # Check if NFS is actually available (quick test with timeout)
    echo "Checking if NFS is available..."
    if timeout 5 showmount -e "$NAS_IP" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} NFS service is running"
        # Try to mount with a short timeout
        if timeout 10 mount -a 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} NFS share mounted"
            NAS_MOUNTED=true
        else
            echo -e "  ${YELLOW}⚠${NC} Could not mount NFS share"
            echo "    Make sure /srv/homelab share is configured in OMV"
            echo "    You can mount manually later with: sudo mount -a"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} NFS service not available yet on NAS"
        echo "    This is fine - NFS mount is configured in /etc/fstab"
        echo "    It will auto-mount on next boot, or run: sudo mount -a"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} Cannot reach NAS at $NAS_IP"
    echo "    NFS mount is configured but not mounted"
    echo "    After NAS is ready, run: sudo mount -a"
fi

# Create subdirectories if NAS is mounted
if [ "$NAS_MOUNTED" = true ]; then
    echo ""
    echo -e "${GREEN}Creating NAS subdirectories...${NC}"
    mkdir -p /mnt/nas/{media,downloads,documents,backups,nextcloud,syncthing}
    # Set ownership to match PUID/PGID from .env
    chown -R "${PUID}:${PGID}" /mnt/nas/
    echo -e "  ${GREEN}✓${NC} Subdirectories created: media, downloads, documents, backups, nextcloud, syncthing"
else
    echo -e "  ${CYAN}ℹ${NC}  Subdirectories will be created when NAS is mounted"
    echo "    After mounting, run: sudo mkdir -p /mnt/nas/{media,downloads,documents,backups,nextcloud,syncthing}"
fi

echo -e "  ${CYAN}ℹ${NC}  Skipping NFS mount is OK - you can connect later"

# =============================================================================
# Step 7: Create config directories
# =============================================================================
echo ""
echo -e "${GREEN}Step 7: Creating config directories...${NC}"

cd "$HOMELAB_DIR"
mkdir -p config/{jellyfin,homeassistant,transmission,nextcloud,syncthing,grafana,wireguard}

# Set ownership to the user
REAL_USER="${SUDO_USER:-$USER}"
chown -R "$REAL_USER:$REAL_USER" config/

echo -e "  ${GREEN}✓${NC} Config directories created"

# =============================================================================
# Step 8: Set hostname (optional)
# =============================================================================
echo ""
echo -e "${GREEN}Step 8: Hostname configuration...${NC}"

CURRENT_HOSTNAME=$(hostname)
if [ "$CURRENT_HOSTNAME" != "homelab" ]; then
    read -p "Set hostname to 'homelab'? (y/n): " set_hostname
    if [ "$set_hostname" = "y" ]; then
        hostnamectl set-hostname homelab
        echo "127.0.1.1 homelab" >> /etc/hosts
        echo -e "  ${GREEN}✓${NC} Hostname set to 'homelab'"
    else
        echo -e "  ${YELLOW}⚠${NC} Keeping hostname as '$CURRENT_HOSTNAME'"
    fi
else
    echo -e "  ${GREEN}✓${NC} Hostname already set to 'homelab'"
fi

# =============================================================================
# Complete
# =============================================================================
echo ""
echo -e "${GREEN}=============================================="
echo "          Setup Complete!"
echo "==============================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo -e "${CYAN}1. Log out and back in${NC} (for docker group)"
echo ""
echo -e "${CYAN}2. Verify NFS mounts:${NC}"
echo "   df -h /mnt/nas/*"
echo ""
echo -e "${CYAN}3. Start the services:${NC}"
echo "   cd $HOMELAB_DIR"
echo "   docker compose up -d"
echo ""
echo -e "${CYAN}4. Access your services:${NC}"
echo "   Jellyfin:        http://homelab:8096"
echo "   Home Assistant:  http://homelab:8123"
echo "   Transmission:    http://homelab:9091"
echo "   Nextcloud:       http://homelab:8080"
echo "   Syncthing:       http://homelab:8384"
echo "   Grafana:         http://homelab:3000"
echo ""
echo -e "${CYAN}5. WireGuard peer configs:${NC}"
echo "   After starting containers, find them in:"
echo "   ./config/wireguard/peer_*/peer_*.conf"
echo ""
