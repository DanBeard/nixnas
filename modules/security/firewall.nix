# Firewall Configuration
# nftables-based firewall with sensible defaults

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.security;
in
{
  config = mkIf cfg.enable {
    # Enable nftables (modern firewall)
    networking.nftables.enable = true;

    # Firewall configuration
    networking.firewall = {
      enable = true;

      # Allow ping for network diagnostics
      allowPing = true;

      # Default: SSH only, other services add their own ports
      allowedTCPPorts = [
        22  # SSH
      ];

      allowedUDPPorts = [
        # Services will add their own ports
      ];

      # Trusted interfaces (loopback always trusted)
      trustedInterfaces = [ "lo" ];

      # Log dropped packets for debugging
      logReversePathDrops = true;
      logRefusedConnections = true;

      # Required for WireGuard/VPN routing
      checkReversePath = "loose";

      # Extra rules can be added by services
      extraInputRules = ''
        # Allow established/related connections
        ct state established,related accept
      '';
    };

    # Enable IP forwarding for VPN routing
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
}
