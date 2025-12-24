#!/usr/bin/env bash
# =============================================================================
# NixNAS ZFS Mirror Pool Creation Script
# =============================================================================
# Creates a ZFS mirror pool with two drives for data redundancy.
#
# Usage: sudo ./create-zfs-pool.sh /dev/sdb /dev/sdc [pool-name]
#    or: sudo ./create-zfs-pool.sh /dev/disk/by-id/DISK1 /dev/disk/by-id/DISK2 [pool-name]
#
# The script automatically converts /dev/sdX to stable /dev/disk/by-id/ paths
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Convert /dev/sdX to /dev/disk/by-id/... path
get_disk_by_id() {
    local dev="$1"

    # If already a by-id path, just return it
    if [[ "$dev" == /dev/disk/by-id/* ]]; then
        echo "$dev"
        return 0
    fi

    # Get the base device name (e.g., sdb from /dev/sdb)
    local base_dev
    base_dev=$(basename "$dev")

    # Find the by-id link for this device
    # Prefer ata- or nvme- IDs over wwn- or scsi- for readability
    local by_id=""

    for id_path in /dev/disk/by-id/*; do
        # Skip partition entries
        [[ "$id_path" == *-part* ]] && continue

        # Check if this link points to our device
        local target
        target=$(readlink -f "$id_path" 2>/dev/null) || continue

        if [[ "$target" == "/dev/$base_dev" ]]; then
            local id_name
            id_name=$(basename "$id_path")

            # Prefer ata- or nvme- IDs (more readable)
            if [[ "$id_name" == ata-* ]] || [[ "$id_name" == nvme-* ]]; then
                by_id="$id_path"
                break
            elif [[ -z "$by_id" ]]; then
                # Use scsi- or wwn- as fallback
                by_id="$id_path"
            fi
        fi
    done

    if [[ -n "$by_id" ]]; then
        echo "$by_id"
        return 0
    else
        echo ""
        return 1
    fi
}

# Show available disks
show_available_disks() {
    echo ""
    echo -e "${CYAN}Available disks:${NC}"
    echo ""
    printf "  %-10s %-8s %-40s\n" "DEVICE" "SIZE" "DISK ID"
    echo "  --------------------------------------------------------------------------"

    for dev in /dev/sd? /dev/nvme?n?; do
        [ -b "$dev" ] || continue

        local size
        size=$(lsblk -dn -o SIZE "$dev" 2>/dev/null) || continue

        local by_id
        by_id=$(get_disk_by_id "$dev" 2>/dev/null) || by_id="(no stable ID found)"
        by_id=$(basename "$by_id" 2>/dev/null) || by_id="(no stable ID found)"

        printf "  %-10s %-8s %s\n" "$dev" "$size" "$by_id"
    done
    echo ""
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Check arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Error: Two disk paths required${NC}"
    echo ""
    echo "Usage: sudo $0 /dev/sdb /dev/sdc [pool-name]"
    echo "   or: sudo $0 /dev/disk/by-id/DISK1 /dev/disk/by-id/DISK2 [pool-name]"
    show_available_disks
    exit 1
fi

INPUT_DISK1="$1"
INPUT_DISK2="$2"
POOL_NAME="${3:-tank}"

# Validate input disks exist
for disk in "$INPUT_DISK1" "$INPUT_DISK2"; do
    if [ ! -b "$disk" ]; then
        echo -e "${RED}Error: $disk is not a block device${NC}"
        show_available_disks
        exit 1
    fi
done

# Check if disks are the same
if [ "$(readlink -f "$INPUT_DISK1")" == "$(readlink -f "$INPUT_DISK2")" ]; then
    echo -e "${RED}Error: Both disks are the same!${NC}"
    exit 1
fi

# Convert to by-id paths
echo ""
echo -e "${CYAN}Looking up stable disk IDs...${NC}"
echo ""

DISK1=$(get_disk_by_id "$INPUT_DISK1")
if [ -z "$DISK1" ]; then
    echo -e "${RED}Error: Could not find stable ID for $INPUT_DISK1${NC}"
    echo "This disk may not have a stable identifier."
    exit 1
fi

DISK2=$(get_disk_by_id "$INPUT_DISK2")
if [ -z "$DISK2" ]; then
    echo -e "${RED}Error: Could not find stable ID for $INPUT_DISK2${NC}"
    echo "This disk may not have a stable identifier."
    exit 1
fi

# Show the mapping
echo -e "${GREEN}Found stable disk IDs:${NC}"
echo ""
echo -e "  Disk 1: ${BOLD}$INPUT_DISK1${NC}"
echo -e "      ID: ${CYAN}$DISK1${NC}"
SIZE1=$(lsblk -dn -o SIZE "$(readlink -f "$DISK1")" 2>/dev/null || echo "unknown")
echo -e "    Size: $SIZE1"
echo ""
echo -e "  Disk 2: ${BOLD}$INPUT_DISK2${NC}"
echo -e "      ID: ${CYAN}$DISK2${NC}"
SIZE2=$(lsblk -dn -o SIZE "$(readlink -f "$DISK2")" 2>/dev/null || echo "unknown")
echo -e "    Size: $SIZE2"
echo ""

# Check for existing ZFS pools
existing=$(zpool list -H -o name 2>/dev/null | grep "^${POOL_NAME}$" || true)
if [ -n "$existing" ]; then
    echo -e "${RED}Error: Pool '$POOL_NAME' already exists!${NC}"
    echo "Use a different name or destroy the existing pool first."
    exit 1
fi

# Confirm
echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  WARNING: This will ERASE ALL DATA on both disks!               ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Pool name: ${BOLD}$POOL_NAME${NC}"
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

    echo "  Creating: $name -> $mountpoint"
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
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ZFS pool created successfully!                                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Pool Status:${NC}"
zpool status "$POOL_NAME"
echo ""
echo -e "${BOLD}Datasets:${NC}"
zfs list -r "$POOL_NAME"
echo ""

# Generate hostId
HOST_ID=$(head -c 8 /etc/machine-id 2>/dev/null || echo "")

echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}SAVE THESE VALUES FOR YOUR NIXOS CONFIG:${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}hostId:${NC}     ${GREEN}$HOST_ID${NC}"
echo ""
echo -e "  ${BOLD}dataDisks:${NC}"
echo -e "    ${GREEN}$DISK1${NC}"
echo -e "    ${GREEN}$DISK2${NC}"
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Add these to /mnt/etc/nixos/hosts/nixnas/default.nix:"
echo ""
echo "  networking.hostId = \"$HOST_ID\";"
echo ""
echo "  nixnas.zfs.dataDisks = ["
echo "    \"$DISK1\""
echo "    \"$DISK2\""
echo "  ];"
echo ""
