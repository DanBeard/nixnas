# ZFS Storage Configuration
# Pool management, datasets, scrubbing, snapshots, and TRIM

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.zfs;
in
{
  options.nixnas.zfs = {
    enable = mkEnableOption "ZFS storage configuration";

    poolName = mkOption {
      type = types.str;
      default = "tank";
      description = "Name of the ZFS pool";
    };

    # Note: Pool creation is done manually via script before installation
    # This option is for documentation/reference
    dataDisks = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of disk paths for the mirror (use /dev/disk/by-id/). Used by installation script.";
      example = [ "/dev/disk/by-id/ata-WDC_WD40EFRX-1" "/dev/disk/by-id/ata-WDC_WD40EFRX-2" ];
    };

    arcMaxGB = mkOption {
      type = types.int;
      default = 4;
      description = "Maximum ARC (cache) size in GB";
    };
  };

  config = mkIf cfg.enable {
    # ZFS services
    services.zfs = {
      # Weekly scrub to check data integrity
      autoScrub = {
        enable = true;
        interval = "Sun, 02:00";
        pools = [ cfg.poolName ];
      };

      # Automatic snapshots for data protection
      autoSnapshot = {
        enable = true;
        frequent = 4;    # Keep 4 15-minute snapshots
        hourly = 24;     # Keep 24 hourly snapshots
        daily = 7;       # Keep 7 daily snapshots
        weekly = 4;      # Keep 4 weekly snapshots
        monthly = 12;    # Keep 12 monthly snapshots
      };

      # TRIM for SSDs (safe for HDDs too, just no-op)
      trim = {
        enable = true;
        interval = "weekly";
      };
    };

    # ZFS Event Daemon for notifications
    services.zfs.zed = {
      enable = true;
      settings = {
        ZED_DEBUG_LOG = "/tmp/zed.debug.log";
        ZED_EMAIL_ADDR = [ "root" ];
        ZED_EMAIL_PROG = "${pkgs.mailutils}/bin/mail";
        ZED_NOTIFY_INTERVAL_SECS = 3600;
        ZED_NOTIFY_VERBOSE = true;

        # Scrub notifications
        ZED_SCRUB_AFTER_RESILVER = true;
      };
    };

    # Import pool at boot
    boot.zfs.extraPools = [ cfg.poolName ];

    # ZFS kernel parameters
    boot.kernelParams = [
      # Limit ARC size (in bytes)
      "zfs.zfs_arc_max=${toString (cfg.arcMaxGB * 1024 * 1024 * 1024)}"
    ];

    # ZFS utilities
    environment.systemPackages = with pkgs; [
      zfs               # ZFS tools
      sanoid            # Snapshot management (optional alternative)
      lzop              # Fast compression for ZFS send
      mbuffer           # Buffer for ZFS send/receive
      pv                # Progress viewer for transfers
    ];

    # Create standard mount points
    systemd.tmpfiles.rules = [
      "d /data 0755 root root -"
      "d /data/media 0775 root media -"
      "d /data/downloads 0775 root media -"
      "d /data/documents 0750 admin admin -"
      "d /data/backups 0750 root root -"
      "d /data/docker 0750 root docker -"
      "d /data/home-assistant 0750 hass hass -"
      "d /data/nextcloud 0750 nextcloud nextcloud -"
      "d /data/jellyfin 0750 jellyfin jellyfin -"
      "d /data/syncthing 0750 admin admin -"
    ];

    # Reminder about hostId requirement
    assertions = [
      {
        assertion = config.networking.hostId != null;
        message = "ZFS requires networking.hostId to be set. Generate with: head -c 8 /etc/machine-id";
      }
    ];
  };
}
