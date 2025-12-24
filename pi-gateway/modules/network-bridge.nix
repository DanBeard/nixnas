# =============================================================================
# Network Bridge Configuration
# =============================================================================
# Enables the Pi to route traffic between its local LAN and the WireGuard VPN.
# Devices on the local network can access the NAS through this Pi.
#
# Supports both Ethernet (eth0) and WiFi (wlan0) connections.
# =============================================================================

{ config, lib, pkgs, ... }:

{
  # =============================================================================
  # Network Interface Configuration
  # =============================================================================

  networking = {
    # Use networkmanager for easy WiFi setup
    networkmanager.enable = true;

    # Disable the default DHCP handling (networkmanager handles it)
    useDHCP = false;

    # Enable DHCP on physical interfaces
    interfaces = {
      eth0.useDHCP = lib.mkDefault true;
      wlan0.useDHCP = lib.mkDefault true;
    };

    # Firewall configuration
    firewall = {
      enable = true;

      # Allow ping
      allowPing = true;

      # Required for WireGuard routing to work properly
      checkReversePath = "loose";

      # Allow SSH and WireGuard
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ 51820 ];

      # Allow forwarding between interfaces
      extraCommands = ''
        # Allow forwarding from local LAN to WireGuard
        iptables -A FORWARD -i eth0 -o wg0 -j ACCEPT
        iptables -A FORWARD -i wlan0 -o wg0 -j ACCEPT

        # Allow forwarding from WireGuard to local LAN
        iptables -A FORWARD -i wg0 -o eth0 -j ACCEPT
        iptables -A FORWARD -i wg0 -o wlan0 -j ACCEPT

        # Allow established/related connections
        iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
      '';

      extraStopCommands = ''
        iptables -D FORWARD -i eth0 -o wg0 -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i wlan0 -o wg0 -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i wg0 -o eth0 -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i wg0 -o wlan0 -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
      '';
    };
  };

  # =============================================================================
  # IP Forwarding (Critical for routing)
  # =============================================================================

  boot.kernel.sysctl = {
    # Enable IPv4 forwarding
    "net.ipv4.ip_forward" = 1;

    # Enable IPv6 forwarding (optional)
    "net.ipv6.conf.all.forwarding" = 1;

    # Don't accept ICMP redirects (security)
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;

    # Don't send ICMP redirects (security)
    "net.ipv4.conf.all.send_redirects" = 0;

    # Enable reverse path filtering (loose mode for VPN)
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
  };

  # =============================================================================
  # WiFi Configuration Helper
  # =============================================================================

  # Create a helper script for easy WiFi setup
  environment.systemPackages = with pkgs; [
    networkmanager
  ];

  # Instructions shown at login
  environment.etc."motd".text = ''

    ============================================
    Pi Gateway - WireGuard VPN Bridge
    ============================================

    WiFi Setup:
      nmcli device wifi list
      nmcli device wifi connect "SSID" password "PASSWORD"

    Check WireGuard status:
      sudo wg show

    Check routing:
      ip route
      ping 10.100.0.1  # Ping NAS via VPN

    View this Pi's public key:
      sudo cat /etc/wireguard/private-key | wg pubkey

    ============================================

  '';

  # =============================================================================
  # mDNS/Avahi (for .local hostname resolution)
  # =============================================================================

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # =============================================================================
  # DNS Configuration
  # =============================================================================

  # Use the NAS as DNS when connected to VPN (optional)
  # Uncomment if your NAS runs a DNS server
  # networking.nameservers = [ "10.100.0.1" ];

  # Fallback to public DNS
  networking.nameservers = lib.mkDefault [ "1.1.1.1" "8.8.8.8" ];
}
