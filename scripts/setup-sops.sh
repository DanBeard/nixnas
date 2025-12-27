#!/usr/bin/env bash
# =============================================================================
# NixNAS SOPS Secrets Setup Script
# =============================================================================
# This script sets up encrypted secrets management using SOPS and age.
# Run this AFTER your homelab is installed and running.
#
# What this script does:
# 1. Extracts your homelab's age key from its SSH host key
# 2. Creates a .sops.yaml configuration
# 3. Creates an encrypted secrets.yaml file
# 4. Enables sops-nix in your flake.nix
# 5. Rebuilds the system with encrypted secrets
#
# Prerequisites:
# - Homelab installed and running
# - SSH access to homelab
# - sops and age tools (included in dev shell)
#
# Usage: sudo ./setup-sops.sh
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
echo "║              NixNAS SOPS Secrets Setup                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Check if we're on the installed system
if [ ! -f /etc/nixos/flake.nix ]; then
    echo -e "${RED}Error: This script should be run on the installed homelab system${NC}"
    echo "Run this after installation and first boot."
    exit 1
fi

NIXOS_DIR="/etc/nixos"
SECRETS_DIR="$NIXOS_DIR/secrets"

# =============================================================================
# Step 1: Check for required tools
# =============================================================================
echo ""
echo -e "${GREEN}Step 1: Checking for required tools...${NC}"

if ! command -v ssh-to-age &> /dev/null; then
    echo -e "${YELLOW}Installing ssh-to-age...${NC}"
    nix-env -iA nixpkgs.ssh-to-age
fi

if ! command -v sops &> /dev/null; then
    echo -e "${YELLOW}Installing sops...${NC}"
    nix-env -iA nixpkgs.sops
fi

if ! command -v age &> /dev/null; then
    echo -e "${YELLOW}Installing age...${NC}"
    nix-env -iA nixpkgs.age
fi

echo -e "  ${GREEN}✓${NC} Tools ready"

# =============================================================================
# Step 2: Extract host age key
# =============================================================================
echo ""
echo -e "${GREEN}Step 2: Extracting host age key...${NC}"

if [ ! -f /etc/ssh/ssh_host_ed25519_key.pub ]; then
    echo -e "${RED}Error: SSH host key not found${NC}"
    echo "This system may not have generated SSH keys yet."
    exit 1
fi

HOST_AGE_KEY=$(ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub)
echo -e "  ${GREEN}✓${NC} Host age key: $HOST_AGE_KEY"

# =============================================================================
# Step 3: Create .sops.yaml
# =============================================================================
echo ""
echo -e "${GREEN}Step 3: Creating .sops.yaml...${NC}"

cat > "$NIXOS_DIR/.sops.yaml" << EOF
# SOPS Configuration for NixNAS
# This file defines which age keys can decrypt secrets

keys:
  # Homelab host key (derived from SSH host key)
  - &homelab $HOST_AGE_KEY

creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *homelab
EOF

echo -e "  ${GREEN}✓${NC} Created $NIXOS_DIR/.sops.yaml"

# =============================================================================
# Step 4: Create secrets.yaml
# =============================================================================
echo ""
echo -e "${GREEN}Step 4: Creating secrets...${NC}"

mkdir -p "$SECRETS_DIR"

# Read existing passwords if they exist
TRANSMISSION_PASS=""
NEXTCLOUD_PASS=""
GRAFANA_PASS=""
WG_KEY=""

if [ -f /var/lib/nixnas-passwords.txt ]; then
    echo "Found existing generated passwords, extracting..."
    TRANSMISSION_PASS=$(grep "Transmission" /var/lib/nixnas-passwords.txt 2>/dev/null | sed 's/.*Password: //' || echo "")
    NEXTCLOUD_PASS=$(grep "Nextcloud" /var/lib/nixnas-passwords.txt 2>/dev/null | sed 's/.*Password: //' || echo "")
    GRAFANA_PASS=$(grep "Grafana" /var/lib/nixnas-passwords.txt 2>/dev/null | sed 's/.*Password: //' | sed 's/ .*//' || echo "")
fi

if [ -f /etc/wireguard/private.key ]; then
    WG_KEY=$(cat /etc/wireguard/private.key)
fi

# Generate any missing passwords
if [ -z "$TRANSMISSION_PASS" ]; then
    TRANSMISSION_PASS=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)
fi
if [ -z "$NEXTCLOUD_PASS" ]; then
    NEXTCLOUD_PASS=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)
fi
if [ -z "$GRAFANA_PASS" ]; then
    GRAFANA_PASS=$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)
fi
if [ -z "$WG_KEY" ]; then
    WG_KEY=$(wg genkey)
fi

# Create the secrets file (unencrypted first)
cat > "$SECRETS_DIR/secrets.yaml" << EOF
# NixNAS Secrets
# This file is encrypted with SOPS - only the homelab can decrypt it

# WireGuard VPN
wireguard:
  private-key: $WG_KEY

# Transmission torrent client
transmission:
  credentials: |
    {
      "rpc-password": "$TRANSMISSION_PASS"
    }

# Grafana monitoring
grafana:
  admin-password: $GRAFANA_PASS

# Nextcloud
nextcloud:
  admin-password: $NEXTCLOUD_PASS
EOF

echo -e "  ${GREEN}✓${NC} Created secrets file"

# =============================================================================
# Step 5: Encrypt secrets
# =============================================================================
echo ""
echo -e "${GREEN}Step 5: Encrypting secrets...${NC}"

# Need to set up the age key for decryption
mkdir -p /root/.config/sops/age
ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /root/.config/sops/age/keys.txt
chmod 600 /root/.config/sops/age/keys.txt

# Encrypt the secrets file in-place
cd "$NIXOS_DIR"
sops -e -i "$SECRETS_DIR/secrets.yaml"

echo -e "  ${GREEN}✓${NC} Secrets encrypted"

# =============================================================================
# Step 6: Update flake.nix to enable sops
# =============================================================================
echo ""
echo -e "${GREEN}Step 6: Enabling sops-nix in flake.nix...${NC}"

# First, uncomment the sops-nix input if it's commented out
if grep -q "# sops-nix = {" "$NIXOS_DIR/flake.nix"; then
    sed -i 's/# sops-nix = {/sops-nix = {/' "$NIXOS_DIR/flake.nix"
    sed -i 's/#   url = "github:Mic92\/sops-nix";/  url = "github:Mic92\/sops-nix";/' "$NIXOS_DIR/flake.nix"
    sed -i 's/#   inputs.nixpkgs.follows = "nixpkgs";/  inputs.nixpkgs.follows = "nixpkgs";/' "$NIXOS_DIR/flake.nix"
    sed -i 's/# };/};/' "$NIXOS_DIR/flake.nix"
    # Also need to add sops-nix to outputs
    sed -i 's/outputs = { self, nixpkgs, nixpkgs-unstable, disko, \.\.\. }@inputs:/outputs = { self, nixpkgs, nixpkgs-unstable, disko, sops-nix, ... }@inputs:/' "$NIXOS_DIR/flake.nix"
    echo -e "  ${GREEN}✓${NC} Uncommented sops-nix input"
fi

# Check if sops module is already enabled
if grep -q "sops-nix.nixosModules.sops" "$NIXOS_DIR/flake.nix"; then
    echo -e "  ${YELLOW}⚠${NC} sops-nix module already enabled in flake.nix"
else
    # Add sops module to homelab
    sed -i 's/modules = baseModules ++ \[/modules = baseModules ++ [\n            sops-nix.nixosModules.sops/' "$NIXOS_DIR/flake.nix"
    echo -e "  ${GREEN}✓${NC} Added sops-nix module to flake.nix"
fi

# =============================================================================
# Step 7: Update host config to use sops secrets
# =============================================================================
echo ""
echo -e "${GREEN}Step 7: Updating host configuration...${NC}"

HOST_CONFIG="$NIXOS_DIR/hosts/homelab/default.nix"

# Uncomment sops configuration if it's commented out
if grep -q "# sops = {" "$HOST_CONFIG"; then
    sed -i 's/# sops = {/sops = {/' "$HOST_CONFIG"
    sed -i 's/#   defaultSopsFile/  defaultSopsFile/' "$HOST_CONFIG"
    sed -i 's/#   age = {/  age = {/' "$HOST_CONFIG"
    sed -i 's/#     sshKeyPaths/    sshKeyPaths/' "$HOST_CONFIG"
    sed -i 's/#   };/  };/g' "$HOST_CONFIG"
    sed -i 's/# };/};/' "$HOST_CONFIG"
    echo -e "  ${GREEN}✓${NC} Uncommented sops configuration"
else
    echo -e "  ${YELLOW}⚠${NC} sops configuration may need manual review"
fi

# =============================================================================
# Step 8: Rebuild system
# =============================================================================
echo ""
echo -e "${GREEN}Step 8: Rebuilding system with encrypted secrets...${NC}"
echo ""

cd "$NIXOS_DIR"
nixos-rebuild switch --flake .#homelab

# =============================================================================
# Complete
# =============================================================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 SOPS Setup Complete!                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Your secrets are now encrypted and managed by SOPS."
echo ""
echo -e "${CYAN}Encrypted secrets:${NC}"
echo "  • WireGuard private key"
echo "  • Transmission RPC password"
echo "  • Grafana admin password"
echo "  • Nextcloud admin password"
echo ""
echo -e "${CYAN}To edit secrets:${NC}"
echo "  cd /etc/nixos && sops secrets/secrets.yaml"
echo ""
echo -e "${CYAN}To add this to your git repo:${NC}"
echo "  cd /etc/nixos"
echo "  git add .sops.yaml secrets/secrets.yaml"
echo "  git commit -m 'Add encrypted secrets'"
echo "  git push"
echo ""
echo -e "${YELLOW}NOTE: The encrypted secrets.yaml is safe to commit to git.${NC}"
echo ""
