# NixNAS Host Configuration
# Main configuration file with feature toggles

{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "nixnas";

  # IMPORTANT: Required for ZFS - generate with: head -c 8 /etc/machine-id
  # Run this on the target machine and replace the value below
  networking.hostId = "00000000";  # CHANGE THIS!

  # =============================================================================
  # LOCALE AND TIMEZONE
  # =============================================================================

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  # =============================================================================
  # FEATURE TOGGLES
  # =============================================================================

  nixnas = {
    # ------------------------
    # STORAGE (Required)
    # ------------------------
    zfs = {
      enable = true;
      poolName = "tank";
      arcMaxGB = 4;  # Adjust based on available RAM
      # Disk IDs - update these with your actual disk IDs
      # Find with: ls -la /dev/disk/by-id/ | grep -v part
      dataDisks = [
        "/dev/disk/by-id/CHANGE-ME-DISK1"
        "/dev/disk/by-id/CHANGE-ME-DISK2"
      ];
    };

    # ------------------------
    # SECURITY (Recommended)
    # ------------------------
    security = {
      enable = true;
      autoUpdates = true;
      autoReboot = true;  # Reboot between 3-5 AM if needed
    };

    # ------------------------
    # VPN
    # ------------------------
    wireguard = {
      enable = true;
      port = 51820;
      serverIP = "10.100.0.1/24";
      externalInterface = "eth0";  # Change to your interface (check with: ip link)
      # Add peers after installation - example:
      # peers = [
      #   {
      #     name = "phone";
      #     publicKey = "PEER_PUBLIC_KEY_HERE";
      #     allowedIPs = [ "10.100.0.2/32" ];
      #   }
      #   {
      #     name = "laptop";
      #     publicKey = "PEER_PUBLIC_KEY_HERE";
      #     allowedIPs = [ "10.100.0.3/32" ];
      #   }
      # ];
      peers = [];
    };

    # ------------------------
    # FILE SHARING
    # ------------------------
    samba = {
      enable = true;
      workgroup = "WORKGROUP";
      timeMachineShare = true;  # Enable macOS Time Machine backup
    };

    # ------------------------
    # HOME AUTOMATION
    # ------------------------
    homeAssistant = {
      enable = true;
      httpPort = 8123;
      configDir = "/data/home-assistant";
    };

    # ------------------------
    # TORRENTS
    # ------------------------
    transmission = {
      enable = true;
      downloadDir = "/data/downloads";
      webUIPort = 9091;
      peerPort = 51413;
      uploadLimitKB = 1000;  # 1 MB/s upload limit
      ratioLimit = 2.0;
    };

    # ------------------------
    # MEDIA SERVER
    # ------------------------
    jellyfin = {
      enable = true;
      dataDir = "/data/jellyfin";
      mediaDir = "/data/media";
    };

    # ------------------------
    # FILE SYNC
    # ------------------------
    syncthing = {
      enable = true;
      user = "admin";
      dataDir = "/data/syncthing";
      guiPort = 8384;
    };

    # ------------------------
    # CLOUD STORAGE
    # ------------------------
    nextcloud = {
      enable = true;
      hostName = "nextcloud.nixnas.local";
      dataDir = "/data/nextcloud";
      httpPort = 8080;
    };

    # ------------------------
    # CONTAINERS
    # ------------------------
    docker = {
      enable = true;
      dataRoot = "/data/docker";
    };

    # ------------------------
    # REVERSE PROXY
    # ------------------------
    nginx = {
      enable = true;
    };

    # ------------------------
    # MONITORING
    # ------------------------
    monitoring = {
      enable = true;
    };

    # ------------------------
    # BACKUP
    # ------------------------
    backup = {
      enable = true;
    };

    # ------------------------
    # DEVELOPMENT TOOLS
    # ------------------------
    python = {
      enable = true;
    };

    nodejs = {
      enable = true;
    };
  };

  # =============================================================================
  # SOPS SECRETS CONFIGURATION
  # =============================================================================

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age = {
      # Use SSH host key for decryption
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      # Or use a dedicated age key
      # keyFile = "/root/.config/sops/age/keys.txt";
    };
  };

  # =============================================================================
  # ADDITIONAL PACKAGES
  # =============================================================================

  environment.systemPackages = with pkgs; [
    # Add any additional packages here
  ];

  # =============================================================================
  # STATE VERSION
  # =============================================================================

  # Don't change this unless you know what you're doing
  system.stateVersion = "24.11";
}
