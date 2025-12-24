# =============================================================================
# WireGuard Client Configuration
# =============================================================================
# Connects this Pi gateway to the central NixNAS via WireGuard.
#
# REQUIRED: Before building, you must set:
# 1. nasPublicKey - Your NAS's WireGuard public key
# 2. nasEndpoint  - Your NAS's DDNS hostname or public IP
# 3. piVpnIP      - This Pi's assigned VPN IP (unique per Pi)
#
# The private key is generated on first boot and stored in /etc/wireguard/
# =============================================================================

{ config, lib, pkgs, ... }:

let
  # =============================================================================
  # CONFIGURATION - EDIT THESE VALUES
  # =============================================================================

  # Your NixNAS WireGuard public key
  # Get this from your NAS with: sudo cat /etc/wireguard/private | wg pubkey
  nasPublicKey = "REPLACE_WITH_NAS_PUBLIC_KEY";

  # Your NixNAS endpoint (DDNS hostname or static IP)
  # Example: "mynas.duckdns.org:51820" or "123.45.67.89:51820"
  nasEndpoint = "your-nas.example.com:51820";

  # This Pi's VPN IP address (must be unique per Pi)
  # Use 10.100.0.2 for first Pi, 10.100.0.3 for second, etc.
  piVpnIP = "10.100.0.2";

  # VPN subnet - should match your NAS configuration
  vpnSubnet = "10.100.0.0/24";

  # NAS's VPN IP - for routing
  nasVpnIP = "10.100.0.1";

  # =============================================================================
  # END CONFIGURATION
  # =============================================================================

in {
  # WireGuard interface configuration
  networking.wireguard.interfaces.wg0 = {
    # This Pi's VPN IP
    ips = [ "${piVpnIP}/32" ];

    # Listen port (for incoming connections, though usually not needed for client)
    listenPort = 51820;

    # Private key file - generated on first boot
    privateKeyFile = "/etc/wireguard/private-key";

    # Generate keys on first boot if they don't exist
    generatePrivateKeyFile = true;

    # Peer: Central NAS
    peers = [{
      # NAS's public key
      publicKey = nasPublicKey;

      # Route these IPs through the VPN:
      # - VPN subnet (to reach NAS and other VPN clients)
      # - NAS's local network (if you want to reach devices on NAS's LAN)
      allowedIPs = [
        vpnSubnet            # 10.100.0.0/24 - VPN subnet
        # "192.168.0.0/24"   # Uncomment to also route to NAS's local LAN
      ];

      # NAS's public endpoint
      endpoint = nasEndpoint;

      # Keep connection alive (important for NAT traversal)
      persistentKeepalive = 25;
    }];

    # Post-up script: Add routing and print public key for easy setup
    postSetup = ''
      # Print this Pi's public key (needed to add as peer on NAS)
      echo "=========================================="
      echo "Pi Gateway WireGuard Public Key:"
      ${pkgs.wireguard-tools}/bin/wg pubkey < /etc/wireguard/private-key
      echo "=========================================="
      echo "Add this key as a peer on your NAS!"
      echo ""
    '';
  };

  # Firewall: Allow WireGuard traffic
  networking.firewall = {
    allowedUDPPorts = [ 51820 ];
  };

  # =============================================================================
  # First Boot Helper: Display public key
  # =============================================================================

  # Create a service that displays the public key on first boot
  systemd.services.wireguard-show-pubkey = {
    description = "Display WireGuard public key for NAS configuration";
    wantedBy = [ "multi-user.target" ];
    after = [ "wireguard-wg0.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      if [ -f /etc/wireguard/private-key ]; then
        PUBKEY=$(${pkgs.wireguard-tools}/bin/wg pubkey < /etc/wireguard/private-key)
        echo ""
        echo "============================================"
        echo "Pi Gateway is ready!"
        echo ""
        echo "WireGuard Public Key:"
        echo "$PUBKEY"
        echo ""
        echo "Add this peer to your NixNAS configuration:"
        echo ""
        echo "  {"
        echo "    name = \"$(hostname)\";"
        echo "    publicKey = \"$PUBKEY\";"
        echo "    allowedIPs = [ \"${piVpnIP}/32\" ];"
        echo "  }"
        echo ""
        echo "Then rebuild NixNAS: sudo nixos-rebuild switch"
        echo "============================================"
        echo ""
      fi
    '';
  };
}
