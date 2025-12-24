# =============================================================================
# Pi Gateway - Base Configuration
# =============================================================================
# This is the main configuration for the Raspberry Pi Zero 2W gateway.
# It connects to the central NixNAS via WireGuard and routes local LAN traffic.
#
# CUSTOMIZATION REQUIRED:
# Before building, edit modules/wireguard-client.nix to set:
# - Your NAS's WireGuard public key
# - Your NAS's DDNS hostname or IP
# - This Pi's assigned VPN IP (e.g., 10.100.0.2)
# =============================================================================

{ config, lib, pkgs, ... }:

{
  # System basics
  system.stateVersion = "24.11";

  # Hostname - change this per Pi (e.g., pi-gateway-home1, pi-gateway-home2)
  networking.hostName = "pi-gateway";

  # Timezone - adjust as needed
  time.timeZone = "America/Los_Angeles";

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";

  # =============================================================================
  # User Configuration
  # =============================================================================

  # Admin user for SSH access
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];

    # IMPORTANT: Add your SSH public key here!
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAAC3Nz... your-key-here"
    ];
  };

  # Allow passwordless sudo for admin
  security.sudo.wheelNeedsPassword = false;

  # Disable root login
  users.users.root.hashedPassword = "!";

  # =============================================================================
  # SSH Server
  # =============================================================================

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  # =============================================================================
  # Essential Packages
  # =============================================================================

  environment.systemPackages = with pkgs; [
    vim
    htop
    git
    wireguard-tools
    tcpdump        # Network debugging
    iptables       # Firewall management
    iproute2       # ip command
    dnsutils       # dig, nslookup
  ];

  # =============================================================================
  # Nix Configuration
  # =============================================================================

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };

    # Garbage collection (Pi has limited storage)
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # =============================================================================
  # Automatic Updates (Optional)
  # =============================================================================

  # Uncomment to enable automatic security updates
  # system.autoUpgrade = {
  #   enable = true;
  #   flake = "github:YOUR_USER/nixnas#pi-gateway";
  #   dates = "04:00";
  #   allowReboot = true;
  # };
}
