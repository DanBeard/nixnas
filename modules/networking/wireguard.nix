# WireGuard VPN Configuration
# Self-hosted VPN server for road warrior and site-to-site connections

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.wireguard;
  # Check if sops is available
  hasSops = config ? sops && config.sops ? secrets;
in
{
  options.nixnas.wireguard = {
    enable = mkEnableOption "WireGuard VPN server";

    privateKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to WireGuard private key file.
        If null, a key will be generated at /etc/wireguard/private.key on first boot.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 51820;
      description = "WireGuard listen port";
    };

    interface = mkOption {
      type = types.str;
      default = "wg0";
      description = "WireGuard interface name";
    };

    serverIP = mkOption {
      type = types.str;
      default = "10.100.0.1/24";
      description = "Server's IP address in the VPN network";
    };

    serverIPv6 = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Server's IPv6 address in the VPN (optional)";
      example = "fd00:vpn::1/64";
    };

    externalInterface = mkOption {
      type = types.str;
      default = "eth0";
      description = "External network interface for NAT (check with 'ip link')";
    };

    # Peers are defined via sops secrets or added here
    # Supports both road-warrior (phones/laptops) and site-to-site (Pi gateways)
    peers = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Peer name for identification";
          };
          publicKey = mkOption {
            type = types.str;
            description = "Peer's public key";
          };
          allowedIPs = mkOption {
            type = types.listOf types.str;
            description = ''
              IP addresses allowed for this peer.
              - Road warrior: just VPN IP, e.g., [ "10.100.0.2/32" ]
              - Site-to-site: include remote LAN, e.g., [ "10.100.0.2/32" "192.168.1.0/24" ]
            '';
            example = [ "10.100.0.2/32" ];
          };
          endpoint = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Peer's endpoint (for site-to-site with static IP/DDNS)";
            example = "remote.example.com:51820";
          };
          persistentKeepalive = mkOption {
            type = types.nullOr types.int;
            default = 25;
            description = "Keepalive interval in seconds (for NAT traversal, set to 25 for most cases)";
            example = 25;
          };
          presharedKeyFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Optional preshared key file for additional security";
          };
        };
      });
      default = [];
      description = "List of WireGuard peers (road warriors and site-to-site gateways)";
    };
  };

  config = mkIf cfg.enable {
    # WireGuard kernel module
    boot.kernelModules = [ "wireguard" ];

    # Generate WireGuard key on first boot if not using sops or explicit file
    system.activationScripts.wireguard-keygen = mkIf (cfg.privateKeyFile == null) ''
      if [ ! -f /etc/wireguard/private.key ]; then
        mkdir -p /etc/wireguard
        ${pkgs.wireguard-tools}/bin/wg genkey > /etc/wireguard/private.key
        chmod 600 /etc/wireguard/private.key
        ${pkgs.wireguard-tools}/bin/wg pubkey < /etc/wireguard/private.key > /etc/wireguard/public.key
        chmod 644 /etc/wireguard/public.key
        echo "WireGuard keys generated. Public key:"
        cat /etc/wireguard/public.key
      fi
    '';

    # WireGuard interface configuration
    networking.wireguard.interfaces.${cfg.interface} = {
      # Server's VPN IP
      ips = [ cfg.serverIP ] ++ (optional (cfg.serverIPv6 != null) cfg.serverIPv6);

      # Listen port
      listenPort = cfg.port;

      # Private key file - use explicit path, or generated key
      privateKeyFile = if cfg.privateKeyFile != null
        then cfg.privateKeyFile
        else "/etc/wireguard/private.key";

      # NAT for road warriors (allow them to access internet through NAS)
      postSetup = ''
        # Enable NAT for VPN clients
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${cfg.serverIP} -o ${cfg.externalInterface} -j MASQUERADE
        ${pkgs.iptables}/bin/iptables -A FORWARD -i ${cfg.interface} -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A FORWARD -o ${cfg.interface} -j ACCEPT
      '';

      postShutdown = ''
        # Clean up NAT rules
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${cfg.serverIP} -o ${cfg.externalInterface} -j MASQUERADE || true
        ${pkgs.iptables}/bin/iptables -D FORWARD -i ${cfg.interface} -j ACCEPT || true
        ${pkgs.iptables}/bin/iptables -D FORWARD -o ${cfg.interface} -j ACCEPT || true
      '';

      # Peer configurations
      peers = map (peer: {
        inherit (peer) publicKey allowedIPs;
        endpoint = peer.endpoint;
        persistentKeepalive = peer.persistentKeepalive;
        presharedKeyFile = peer.presharedKeyFile;
      }) cfg.peers;
    };

    # Open firewall port for WireGuard
    networking.firewall.allowedUDPPorts = [ cfg.port ];

    # WireGuard tools
    environment.systemPackages = with pkgs; [
      wireguard-tools
    ];

    # Helper script to generate peer configs
    environment.etc."wireguard/README.md".text = ''
      # WireGuard Configuration

      ## Server Public Key
      Run: cat /etc/wireguard/public.key

      ## Generate New Peer Keys
      ```bash
      wg genkey | tee peer_private.key | wg pubkey > peer_public.key
      ```

      ## Client Config Template (Road Warrior - Phone/Laptop)
      ```ini
      [Interface]
      PrivateKey = <peer_private_key>
      Address = 10.100.0.X/32
      DNS = 10.100.0.1

      [Peer]
      PublicKey = <server_public_key>
      AllowedIPs = 0.0.0.0/0  # Route all traffic through VPN
      Endpoint = <your_public_ip>:${toString cfg.port}
      PersistentKeepalive = 25
      ```

      ## Add Road Warrior Peer
      ```nix
      nixnas.wireguard.peers = [
        {
          name = "phone";
          publicKey = "<peer_public_key>";
          allowedIPs = [ "10.100.0.2/32" ];
        }
      ];
      ```

      ## Add Pi Gateway Peer (Site-to-Site)
      For a Pi Gateway at a family member's home:
      ```nix
      nixnas.wireguard.peers = [
        {
          name = "pi-gateway-home1";
          publicKey = "<pi_public_key>";
          allowedIPs = [
            "10.100.0.3/32"       # Pi's VPN IP
            # "192.168.1.0/24"    # Uncomment to route to their LAN
          ];
        }
      ];
      ```

      ## Check Connection Status
      ```bash
      sudo wg show
      ```
    '';
  };
}
