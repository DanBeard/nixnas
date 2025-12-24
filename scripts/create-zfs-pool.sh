#!/usr/bin/env bash
# =============================================================================
# NixNAS ZFS Mirror Pool Creation Script
# =============================================================================
# Creates a ZFS mirror pool with two drives for data redundancy.
#
# Usage: sudo ./create-zfs-pool.sh /dev/disk/by-id/DISK1 /dev/disk/by-id/DISK2 [pool-name]
#
# IMPORTANT: Always use /dev/disk/by-id/ paths for ZFS!
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Check arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Error: Two disk paths required${NC}"
    echo ""
    echo "Usage: sudo $0 /dev/disk/by-id/DISK1 /dev/disk/by-id/DISK2 [pool-name]"
    echo ""
    echo "Available disks by ID:"
    ls -la /dev/disk/by-id/ | grep -v part | grep -E "ata-|scsi-|nvme-" | awk '{print $9, "->", $11}'
    exit 1
fi

DISK1="$1"
DISK2="$2"
POOL_NAME="${3:-tank}"

# Validate disks exist
for disk in "$DISK1" "$DISK2"; do
    if [ ! -b "$disk" ]; then
        echo -e "${RED}Error: $disk is not a block device${NC}"
        exit 1
    fi
done

# Check if using by-id paths (recommended)
if [[ ! "$DISK1" == /dev/disk/by-id/* ]] || [[ ! "$DISK2" == /dev/disk/by-id/* ]]; then
    echo -e "${YELLOW}WARNING: It's recommended to use /dev/disk/by-id/ paths for ZFS${NC}"
    echo "This ensures consistent device identification across reboots."
    read -p "Continue anyway? (y/n): " cont
    if [ "$cont" != "y" ]; then
        echo ""
        echo "Available disks by ID:"
        ls -la /dev/disk/by-id/ | grep -v part | grep -E "ata-|scsi-|nvme-" | awk '{print $9, "->", $11}'
        exit 1
    fi
fi

# Check if disks are the same
if [ "$DISK1" == "$DISK2" ]; then
    echo -e "${RED}Error: Both disks are the same!${NC}"
    exit 1
fi

# Show disk info
echo ""
echo -e "${CYAN}Disk 1:${NC} $DISK1"
lsblk "$(readlink -f "$DISK1")" -o NAME,SIZE,TYPE,FSTYPE 2>/dev/null || true
echo ""
echo -e "${CYAN}Disk 2:${NC} $DISK2"
lsblk "$(readlink -f "$DISK2")" -o NAME,SIZE,TYPE,FSTYPE 2>/dev/null || true
echo ""

# Check for existing ZFS pools
existing=$(zpool list -H -o name 2>/dev/null | grep "^${POOL_NAME}$" || true)
if [ -n "$existing" ]; then
    echo -e "${RED}Error: Pool '$POOL_NAME' already exists!${NC}"
    echo "Use a different name or destroy the existing pool first."
    exit 1
fi

# Confirm
echo -e "${YELLOW}This will create a ZFS mirror pool named '$POOL_NAME'${NC}"
echo -e "${YELLOW}WARNING: ALL DATA on both disks will be ERASED!${NC}"
echo ""
read -p "Type 'YES' to continue: " confirm

if [ "$confirm" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo -e "${GREEN}Creating ZFS mirror pool...${NC}"

# Create the mirrored pool with optimal settings
zpool create -f \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O compression=lz4 \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=none \
    "$POOL_NAME" mirror "$DISK1" "$DISK2"

echo -e "${GREEN}Pool created. Creating datasets...${NC}"

# Create datasets with appropriate settings
create_dataset() {
    local name="$1"
    local mountpoint="$2"
    local extra_opts="${3:-}"

    echo "Creating dataset: $name -> $mountpoint"
    zfs create $extra_opts -o mountpoint="$mountpoint" "${POOL_NAME}/${name}"
}

# Main data dataset
create_dataset "data" "/data"

# Media (large files, maybe lower compression)
create_dataset "data/media" "/data/media" "-o recordsize=1M"

# Downloads (temporary, maybe no compression)
create_dataset "data/downloads" "/data/downloads" "-o compression=off"

# Documents (small files, high compression)
create_dataset "data/documents" "/data/documents" "-o compression=zstd"

# Backups
create_dataset "data/backups" "/data/backups" "-o compression=zstd"

# Docker
create_dataset "data/docker" "/data/docker"

# Home Assistant
create_dataset "data/home-assistant" "/data/home-assistant"

# Nextcloud
create_dataset "data/nextcloud" "/data/nextcloud"

# Jellyfin
create_dataset "data/jellyfin" "/data/jellyfin"

# Syncthing
create_dataset "data/syncthing" "/data/syncthing"

# Show results
echo ""
echo -e "${GREEN}ZFS pool and datasets created successfully!${NC}"
echo ""
echo "Pool status:"
zpool status "$POOL_NAME"
echo ""
echo "Datasets:"
zfs list -r "$POOL_NAME"
echo ""
echo "Pool properties:"
zpool get all "$POOL_NAME" | grep -E "size|capacity|health|ashift"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "1. Continue with NixOS installation"
echo "2. The pool will be auto-imported at boot"
echo ""
echo -e "${YELLOW}IMPORTANT: Note your hostId for NixOS config:${NC}"
head -c 8 /etc/machine-id 2>/dev/null || echo "Generate after booting NixOS"
