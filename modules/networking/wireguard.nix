# WireGuard VPN Configuration
# Self-hosted VPN server for road warrior and site-to-site connections

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.wireguard;
in
{
  options.nixnas.wireguard = {
    enable = mkEnableOption "WireGuard VPN server";

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
            description = "IP addresses allowed for this peer";
            example = [ "10.100.0.2/32" ];
          };
          endpoint = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Peer's endpoint (for site-to-site)";
            example = "remote.example.com:51820";
          };
          persistentKeepalive = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "Keepalive interval (for NAT traversal)";
            example = 25;
          };
        };
      });
      default = [];
      description = "List of WireGuard peers";
    };
  };

  config = mkIf cfg.enable {
    # WireGuard kernel module
    boot.kernelModules = [ "wireguard" ];

    # WireGuard interface configuration
    networking.wireguard.interfaces.${cfg.interface} = {
      # Server's VPN IP
      ips = [ cfg.serverIP ] ++ (optional (cfg.serverIPv6 != null) cfg.serverIPv6);

      # Listen port
      listenPort = cfg.port;

      # Private key from sops secret
      privateKeyFile = config.sops.secrets."wireguard/private-key".path;

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
      }) cfg.peers;
    };

    # Open firewall port for WireGuard
    networking.firewall.allowedUDPPorts = [ cfg.port ];

    # Sops secret for WireGuard private key
    sops.secrets."wireguard/private-key" = {
      owner = "root";
      group = "root";
      mode = "0400";
    };

    # WireGuard tools
    environment.systemPackages = with pkgs; [
      wireguard-tools
    ];

    # Helper script to generate peer configs
    environment.etc."wireguard/README.md".text = ''
      # WireGuard Configuration

      ## Server Public Key
      Run: sudo cat ${config.sops.secrets."wireguard/private-key".path} | wg pubkey

      ## Generate New Peer Keys
      ```bash
      wg genkey | tee peer_private.key | wg pubkey > peer_public.key
      ```

      ## Client Config Template
      ```ini
      [Interface]
      PrivateKey = <peer_private_key>
      Address = 10.100.0.X/32
      DNS = 10.100.0.1  # Use NAS as DNS if running resolver

      [Peer]
      PublicKey = <server_public_key>
      AllowedIPs = 0.0.0.0/0  # Route all traffic (road warrior)
      # Or: AllowedIPs = 10.100.0.0/24, 192.168.1.0/24  # Only specific networks
      Endpoint = <your_public_ip>:${toString cfg.port}
      PersistentKeepalive = 25
      ```

      ## Add Peer to NixOS Config
      Add to hosts/nixnas/default.nix:
      ```nix
      nixnas.wireguard.peers = [
        {
          name = "phone";
          publicKey = "<peer_public_key>";
          allowedIPs = [ "10.100.0.2/32" ];
        }
      ];
      ```
    '';
  };
}
