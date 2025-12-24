# ZFS Snapshots Configuration
# Automatic snapshot management and replication helpers

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.backup;
  zfsCfg = config.nixnas.zfs;
in
{
  config = mkIf (cfg.enable && zfsCfg.enable) {
    # ZFS auto-snapshot is enabled in storage/zfs.nix
    # This module provides additional backup utilities

    environment.systemPackages = with pkgs; [
      # Snapshot management
      sanoid           # Policy-driven snapshot management
      lzop             # Fast compression for ZFS send
      mbuffer          # Buffer for network transfers
      pv               # Progress viewer
    ];

    # Helper scripts for manual operations
    environment.etc."backup/README.md".text = ''
      # NixNAS Backup Guide

      ## Automatic Snapshots
      ZFS auto-snapshots are enabled with the following retention:
      - Frequent (15-min): 4 snapshots
      - Hourly: 24 snapshots
      - Daily: 7 snapshots
      - Weekly: 4 snapshots
      - Monthly: 12 snapshots

      ## List Snapshots
      ```bash
      zfs list -t snapshot
      zfs list -t snapshot -o name,creation,used,refer -s creation
      ```

      ## Rollback to Snapshot
      ```bash
      # Rollback dataset to snapshot (destroys newer snapshots!)
      sudo zfs rollback tank/data/documents@autosnap_2024-01-01_00:00:00_daily
      ```

      ## Clone Snapshot (non-destructive)
      ```bash
      # Create a writable copy from snapshot
      sudo zfs clone tank/data/documents@snapshot_name tank/data/documents-restored
      ```

      ## Manual Snapshot
      ```bash
      sudo zfs snapshot tank/data/documents@manual-$(date +%Y-%m-%d)
      ```

      ## Send Snapshot to External Drive
      ```bash
      # Full send (initial backup)
      sudo zfs send tank/data@snapshot | sudo zfs receive backup-pool/data

      # Incremental send (subsequent backups)
      sudo zfs send -i tank/data@old-snapshot tank/data@new-snapshot | sudo zfs receive backup-pool/data
      ```

      ## Send Snapshot to Remote Server (via SSH)
      ```bash
      # Using mbuffer for better performance
      sudo zfs send tank/data@snapshot | mbuffer -s 128k -m 1G | ssh user@remote "mbuffer -s 128k -m 1G | sudo zfs receive backup-pool/data"

      # Using pv for progress
      sudo zfs send -v tank/data@snapshot | pv | ssh user@remote "sudo zfs receive backup-pool/data"
      ```

      ## Destroy Old Snapshots
      ```bash
      # Destroy single snapshot
      sudo zfs destroy tank/data/documents@snapshot_name

      # Destroy range of snapshots
      sudo zfs destroy tank/data/documents@snap1%snap5
      ```

      ## Check Snapshot Space Usage
      ```bash
      zfs list -o space -r tank
      ```
    '';

    # Script to send ZFS snapshots to external drive
    environment.etc."backup/send-to-external.sh" = {
      mode = "0755";
      text = ''
        #!/usr/bin/env bash
        # Send ZFS snapshots to external backup drive
        # Usage: send-to-external.sh <source-dataset> <target-pool>

        set -euo pipefail

        SOURCE="''${1:-tank/data}"
        TARGET="''${2:-backup}"

        echo "Sending $SOURCE to $TARGET..."

        # Get latest snapshot
        LATEST=$(zfs list -t snapshot -o name -s creation -r "$SOURCE" | tail -1)

        if [ -z "$LATEST" ]; then
          echo "No snapshots found for $SOURCE"
          exit 1
        fi

        echo "Latest snapshot: $LATEST"

        # Check if target has any snapshots from this source
        TARGET_LATEST=$(zfs list -t snapshot -o name -s creation -r "$TARGET" 2>/dev/null | tail -1 || true)

        if [ -z "$TARGET_LATEST" ]; then
          echo "Initial full send..."
          zfs send -v "$LATEST" | pv | zfs receive -F "$TARGET"
        else
          echo "Incremental send from $TARGET_LATEST..."
          # Extract just the snapshot name
          TARGET_SNAP=$(echo "$TARGET_LATEST" | cut -d@ -f2)
          SOURCE_BASE=$(echo "$SOURCE" | cut -d/ -f1-)
          zfs send -v -i "$SOURCE_BASE@$TARGET_SNAP" "$LATEST" | pv | zfs receive -F "$TARGET"
        fi

        echo "Done!"
      '';
    };
  };
}
