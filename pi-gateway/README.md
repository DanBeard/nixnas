# Pi Gateway - WireGuard Bridge for Family Network

A NixOS-based Raspberry Pi Zero 2W image that acts as a WireGuard VPN bridge, allowing devices on a remote LAN to access your central NixNAS.

## Architecture

```
Remote Home                           Your Home
┌─────────────────┐                  ┌─────────────────┐
│  Family devices │                  │    NixNAS       │
│  (phones, PCs)  │                  │  10.100.0.1     │
│       │         │                  │                 │
│       ▼         │                  │  Samba, Jellyfin│
│  ┌─────────┐    │    WireGuard     │  Home Assistant │
│  │Pi Gateway│◄──┼──────────────────┼►│  Nextcloud     │
│  │10.100.0.2│   │    Encrypted     │                 │
│  └─────────┘    │     Tunnel       └─────────────────┘
│  192.168.1.0/24 │
└─────────────────┘
```

## Prerequisites

1. **NixNAS running** with WireGuard enabled
2. **DDNS hostname** for your NAS (e.g., DuckDNS)
3. **Raspberry Pi Zero 2W** with SD card (8GB+)
4. **Build machine** with NixOS (or Nix with binfmt enabled)

## Quick Start

### Step 1: Configure the Pi Image

Edit `modules/wireguard-client.nix` and set:

```nix
# Your NAS's WireGuard public key
nasPublicKey = "your-nas-public-key-here";

# Your NAS's DDNS hostname
nasEndpoint = "your-nas.duckdns.org:51820";

# This Pi's VPN IP (unique per Pi)
piVpnIP = "10.100.0.2";  # Use .3 for second Pi, .4 for third, etc.
```

Also edit `configuration.nix` to add your SSH key:

```nix
openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3Nz... your-key-here"
];
```

### Step 2: Build the SD Image

**Option A: Native aarch64 build** (if on ARM or with binfmt):
```bash
cd pi-gateway
nix build .#sdImage
```

**Option B: Cross-compilation from x86_64**:
```bash
# First, enable binfmt on your NixOS machine:
# Add to /etc/nixos/configuration.nix:
#   boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
# Then rebuild: sudo nixos-rebuild switch

cd pi-gateway
nix build .#sdImage
```

### Step 3: Flash the SD Card

```bash
# Find your SD card device
lsblk

# Flash the image (replace /dev/sdX with your SD card)
sudo dd if=result/sd-image/pi-gateway-*.img of=/dev/sdX bs=4M status=progress
sync
```

### Step 4: Boot the Pi

1. Insert SD card into Pi Zero 2W
2. Connect Ethernet or power on for WiFi setup
3. Boot the Pi

### Step 5: Get the Pi's Public Key

SSH into the Pi (or check the console):

```bash
ssh admin@pi-gateway.local
# or if mDNS doesn't work, find the IP from your router

# The public key is displayed at login, or run:
sudo cat /etc/wireguard/private-key | wg pubkey
```

### Step 6: Add Pi as Peer on NAS

On your NixNAS, edit `/etc/nixos/hosts/nixnas/default.nix`:

```nix
nixnas.wireguard.peers = [
  {
    name = "pi-gateway-home1";
    publicKey = "THE_PI_PUBLIC_KEY_FROM_STEP_5";
    allowedIPs = [ "10.100.0.2/32" ];
  }
];
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake /etc/nixos#nixnas
```

### Step 7: Configure WiFi (if not using Ethernet)

On the Pi:
```bash
# List available networks
nmcli device wifi list

# Connect to WiFi
nmcli device wifi connect "YourSSID" password "YourPassword"
```

### Step 8: Test the Connection

On the Pi:
```bash
# Check WireGuard status
sudo wg show

# Should show handshake with NAS
# Ping the NAS
ping 10.100.0.1

# Access NAS services
curl http://10.100.0.1:8096  # Jellyfin
```

## Deploying Multiple Pis

For each family member's home:

1. **Copy** the `pi-gateway` directory
2. **Change** in `modules/wireguard-client.nix`:
   - `piVpnIP` - Use a unique IP (10.100.0.3, 10.100.0.4, etc.)
3. **Change** in `configuration.nix`:
   - `networking.hostName` - e.g., "pi-gateway-grandma"
4. **Build and flash** a new SD card
5. **Add as peer** on NAS with the new IP

## Troubleshooting

### Pi can't reach NAS

```bash
# Check WireGuard interface
ip addr show wg0

# Check if endpoint is reachable
ping your-nas.duckdns.org

# Check WireGuard handshake
sudo wg show
# "latest handshake" should be recent (< 2 minutes ago)
```

### No handshake on WireGuard

- Verify NAS has the Pi's public key as a peer
- Check that port 51820 is forwarded on your NAS's router
- Ensure DDNS hostname is correct

### WiFi not connecting

```bash
# Check NetworkManager status
nmcli device status

# Check for WiFi networks
nmcli device wifi list

# View detailed connection info
journalctl -u NetworkManager -f
```

### Devices on LAN can't reach NAS

```bash
# Check IP forwarding is enabled
cat /proc/sys/net/ipv4/ip_forward  # Should be 1

# Check iptables rules
sudo iptables -L FORWARD -v

# Check routing table
ip route
```

## Advanced: Site-to-Site Routing

If you want devices on the Pi's LAN to access the NAS directly (not just the Pi):

1. On the **Pi**, the routing is already configured
2. On the **NAS**, add the remote LAN to the peer's allowedIPs:

```nix
{
  name = "pi-gateway-home1";
  publicKey = "...";
  allowedIPs = [
    "10.100.0.2/32"      # Pi's VPN IP
    "192.168.1.0/24"     # Remote home's LAN
  ];
}
```

3. On **devices in the remote home**, add a route to the NAS's network via the Pi:
```bash
# On a Linux device at the remote home:
sudo ip route add 10.100.0.0/24 via 192.168.1.X  # X = Pi's local IP
```

Or configure the route on the home router for all devices.

## Security Notes

- The Pi generates its own WireGuard private key on first boot
- SSH is key-only (no password authentication)
- Root login is disabled
- The Pi only routes traffic, it doesn't NAT (preserves source IPs)
