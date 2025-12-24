#!/usr/bin/env bash
# =============================================================================
# NixNAS USB Boot Drive Preparation Script
# =============================================================================
# This script prepares a USB drive for NixOS installation.
# The USB drive will hold the NixOS operating system.
#
# Usage: sudo ./prepare-usb.sh /dev/sdX
#
# WARNING: This will ERASE ALL DATA on the target drive!
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo $0 /dev/sdX"
    exit 1
fi

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: No device specified${NC}"
    echo "Usage: sudo $0 /dev/sdX"
    echo ""
    echo "Available devices:"
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk
    exit 1
fi

USB_DEVICE="$1"

# Validate device exists
if [ ! -b "$USB_DEVICE" ]; then
    echo -e "${RED}Error: $USB_DEVICE is not a block device${NC}"
    exit 1
fi

# Warn if it looks like a system disk
if echo "$USB_DEVICE" | grep -qE "^/dev/(sda|nvme0n1)$"; then
    echo -e "${YELLOW}WARNING: $USB_DEVICE looks like it might be your system disk!${NC}"
    echo "Please verify this is the correct device."
fi

# Show device info
echo ""
echo "Device information for $USB_DEVICE:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$USB_DEVICE"
echo ""

# Confirm
echo -e "${YELLOW}WARNING: This will ERASE ALL DATA on $USB_DEVICE${NC}"
read -p "Are you absolutely sure? Type 'YES' to continue: " confirm

if [ "$confirm" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo -e "${GREEN}Preparing USB drive...${NC}"

# Unmount any mounted partitions
echo "Unmounting any mounted partitions..."
for part in $(lsblk -ln -o NAME "$USB_DEVICE" | tail -n +2); do
    umount "/dev/$part" 2>/dev/null || true
done

# Create GPT partition table
echo "Creating GPT partition table..."
parted -s "$USB_DEVICE" mklabel gpt

# Create EFI System Partition (512MB)
echo "Creating EFI partition (512MB)..."
parted -s "$USB_DEVICE" mkpart ESP fat32 1MiB 513MiB
parted -s "$USB_DEVICE" set 1 esp on

# Create root partition (rest of disk)
echo "Creating root partition..."
parted -s "$USB_DEVICE" mkpart primary ext4 513MiB 100%

# Wait for kernel to recognize partitions
sleep 2
partprobe "$USB_DEVICE"
sleep 2

# Determine partition names (handle both sdX and nvmeXnYpZ naming)
if [[ "$USB_DEVICE" == *"nvme"* ]]; then
    PART1="${USB_DEVICE}p1"
    PART2="${USB_DEVICE}p2"
else
    PART1="${USB_DEVICE}1"
    PART2="${USB_DEVICE}2"
fi

# Format partitions
echo "Formatting EFI partition as FAT32..."
mkfs.fat -F 32 -n BOOT "$PART1"

echo "Formatting root partition as ext4..."
mkfs.ext4 -L NIXOS "$PART2"

# Show results
echo ""
echo -e "${GREEN}USB drive prepared successfully!${NC}"
echo ""
echo "Partition layout:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL "$USB_DEVICE"
echo ""
echo "Next steps:"
echo "1. Boot from NixOS installer ISO"
echo "2. Mount the USB drive:"
echo "   mount /dev/disk/by-label/NIXOS /mnt"
echo "   mkdir -p /mnt/boot"
echo "   mount /dev/disk/by-label/BOOT /mnt/boot"
echo "3. Create ZFS pool on data drives"
echo "4. Run the NixOS installation"
