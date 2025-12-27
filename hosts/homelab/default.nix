# Homelab Host Configuration
# Full-featured server with all services (for powerful hardware)
# Uses NFS to mount storage from OpenMediaVault NAS
# Requires: 4GB+ RAM, decent CPU

{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "homelab";

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
    # STORAGE - NFS Client
    # ------------------------
    # No local ZFS - using OpenMediaVault NAS for bulk storage
    zfs.enable = false;

    # NFS client to mount OMV NAS shares
    nfsClient = {
      enable = true;
      nasAddress = "192.168.1.100";  # CHANGE THIS to your OMV NAS IP!
      enableDefaultMounts = true;    # Mounts: media, downloads, documents, backups, nextcloud, syncthing
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
      # ];
      peers = [];
    };

    # ------------------------
    # FILE SHARING
    # ------------------------
    # Samba DISABLED - clients access OMV NAS directly for file sharing
    samba.enable = false;

    # ------------------------
    # HOME AUTOMATION
    # ------------------------
    homeAssistant = {
      enable = true;
      httpPort = 8123;
      configDir = "/var/lib/hass";  # Local SSD for low latency
    };

    # ------------------------
    # TORRENTS
    # ------------------------
    transmission = {
      enable = true;
      downloadDir = "/mnt/nas/downloads";  # NFS mount
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
      dataDir = "/var/lib/jellyfin";   # Local SSD for metadata/cache
      mediaDir = "/mnt/nas/media";     # NFS mount for media files
    };

    # ------------------------
    # FILE SYNC
    # ------------------------
    syncthing = {
      enable = true;
      user = "admin";
      dataDir = "/mnt/nas/syncthing";  # NFS mount
      guiPort = 8384;
    };

    # ------------------------
    # CLOUD STORAGE
    # ------------------------
    nextcloud = {
      enable = true;
      hostName = "nextcloud.homelab.local";
      dataDir = "/mnt/nas/nextcloud";  # NFS mount
      httpPort = 8080;
    };

    # ------------------------
    # CONTAINERS
    # ------------------------
    docker = {
      enable = true;
      dataRoot = "/var/lib/docker";  # Local SSD for performance
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
    # ZFS snapshots disabled (no local ZFS)
    backup.enable = false;

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
  # LOCAL DIRECTORIES
  # =============================================================================

  # Create local directories for services that need SSD performance
  systemd.tmpfiles.rules = [
    "d /var/lib/hass 0755 hass hass -"
    "d /var/lib/jellyfin 0755 jellyfin jellyfin -"
  ];

  # =============================================================================
  # SOPS SECRETS CONFIGURATION
  # =============================================================================

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age = {
      # Use SSH host key for decryption
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
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

  system.stateVersion = "24.11";
}
