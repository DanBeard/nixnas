# Automatic Updates Configuration
# Daily security updates with controlled reboot window

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.security;
in
{
  config = mkIf (cfg.enable && cfg.autoUpdates) {
    # Automatic system upgrades
    system.autoUpgrade = {
      enable = true;

      # Update from the flake (update this path after installation)
      # For local flake: flake = "/etc/nixos";
      # For git repo: flake = "github:YOUR_USER/nixnas";
      flake = "/etc/nixos";

      # Additional flags
      flags = [
        "--update-input"
        "nixpkgs"
        "-L" # Print build logs
      ];

      # Update daily at 3 AM
      dates = "03:00";

      # Random delay to prevent thundering herd (if multiple machines)
      randomizedDelaySec = "45min";

      # Allow automatic reboot if kernel changes
      allowReboot = cfg.autoReboot;

      # Reboot window (only reboot during these hours)
      rebootWindow = {
        lower = "03:00";
        upper = "05:00";
      };

      # Only upgrade if no users are logged in (optional, disabled by default)
      # operation = "switch"; # or "boot" to only activate on next boot
    };

    # Keep system clean
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # Optimize store weekly
    nix.optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };

    # Notify about pending updates (via systemd journal)
    systemd.services.upgrade-notify = {
      description = "Notify about NixOS upgrade results";
      after = [ "nixos-upgrade.service" ];
      wantedBy = [ "nixos-upgrade.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "upgrade-notify" ''
          if systemctl is-failed nixos-upgrade.service; then
            echo "NixOS upgrade FAILED - check journal for details" | systemd-cat -t nixos-upgrade -p err
          else
            echo "NixOS upgrade completed successfully" | systemd-cat -t nixos-upgrade -p info
          fi
        '';
      };
    };
  };
}
