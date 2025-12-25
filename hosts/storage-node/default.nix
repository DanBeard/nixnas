# Storage Node Configuration
# Minimal NAS for memory-constrained hardware (QNAP TS-269 Pro, 1GB RAM)
# Only provides: ZFS storage, Samba/NFS file sharing, SSH access

{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # =============================================================================
  # SYSTEM IDENTIFICATION
  # =============================================================================

  networking.hostName = "storage-node";

  # IMPORTANT: Required for ZFS - generate with: head -c 8 /etc/machine-id
  # Run this on the target machine and replace the value below
  networking.hostId = "00000000";  # CHANGE THIS!

  # =============================================================================
  # LOCALE AND TIMEZONE
  # =============================================================================

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  # =============================================================================
  # MINIMAL FEATURE SET
  # =============================================================================

  nixnas = {
    # ------------------------
    # STORAGE (Required)
    # ------------------------
    zfs = {
      enable = true;
      poolName = "tank";
      arcMaxGB = 0.5;  # Only 512MB for ARC cache (1GB RAM system)
      dataDisks = [
        "/dev/disk/by-id/CHANGE-ME-DISK1"
        "/dev/disk/by-id/CHANGE-ME-DISK2"
      ];
    };

    # ------------------------
    # SECURITY (Required)
    # ------------------------
    security = {
      enable = true;
      autoUpdates = true;
      autoReboot = true;
    };

    # ------------------------
    # FILE SHARING (Required)
    # ------------------------
    samba = {
      enable = true;
      workgroup = "WORKGROUP";
      timeMachineShare = false;  # Disable to save memory
    };

    # ------------------------
    # NFS SERVER (For homelab)
    # ------------------------
    nfs = {
      enable = true;
      exports = [
        "/data/media"
        "/data/downloads"
        "/data/documents"
        "/data/backups"
      ];
      # Allow homelab to mount (update with homelab's IP)
      allowedClients = "10.0.0.0/8";
    };

    # ------------------------
    # EVERYTHING ELSE: DISABLED
    # ------------------------
    wireguard.enable = false;
    homeAssistant.enable = false;
    transmission.enable = false;
    jellyfin.enable = false;
    syncthing.enable = false;
    nextcloud.enable = false;
    docker.enable = false;
    nginx.enable = false;
    monitoring.enable = false;
    backup.enable = false;
    python.enable = false;
    nodejs.enable = false;
  };

  # =============================================================================
  # SOPS SECRETS CONFIGURATION
  # =============================================================================

  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    age = {
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };

  # =============================================================================
  # MEMORY OPTIMIZATIONS FOR 1GB RAM
  # =============================================================================

  # Disable documentation to save memory during builds
  documentation.enable = false;
  documentation.man.enable = false;
  documentation.nixos.enable = false;

  # More aggressive swap settings
  boot.kernel.sysctl = {
    "vm.swappiness" = 60;
    "vm.vfs_cache_pressure" = 100;
  };

  # Use zram for compressed swap
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # =============================================================================
  # STATE VERSION
  # =============================================================================

  system.stateVersion = "24.11";
}
