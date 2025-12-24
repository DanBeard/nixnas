# Docker Configuration
# Docker and docker-compose for containerized services

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.docker;
in
{
  options.nixnas.docker = {
    enable = mkEnableOption "Docker and docker-compose";

    dataRoot = mkOption {
      type = types.path;
      default = "/data/docker";
      description = "Docker data directory (on ZFS for better performance)";
    };

    enableBuildkit = mkOption {
      type = types.bool;
      default = true;
      description = "Enable BuildKit for better build performance";
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;

      # Start on boot
      enableOnBoot = true;

      # Automatic cleanup
      autoPrune = {
        enable = true;
        dates = "weekly";
        flags = [ "--all" "--volumes" ];
      };

      # Daemon settings
      daemon.settings = {
        # Store data on ZFS
        data-root = cfg.dataRoot;

        # Logging configuration
        log-driver = "json-file";
        log-opts = {
          max-size = "10m";
          max-file = "3";
        };

        # DNS settings
        dns = [ "1.1.1.1" "8.8.8.8" ];

        # Enable BuildKit
        features = mkIf cfg.enableBuildkit {
          buildkit = true;
        };

        # Default address pools for networks
        default-address-pools = [
          {
            base = "172.17.0.0/16";
            size = 24;
          }
        ];

        # Storage driver (overlay2 is default and works well with ZFS)
        storage-driver = "overlay2";

        # Live restore (keep containers running during daemon restart)
        live-restore = true;

        # Limit concurrent downloads
        max-concurrent-downloads = 3;
        max-concurrent-uploads = 5;
      };
    };

    # Docker compose and related tools
    environment.systemPackages = with pkgs; [
      docker-compose
      lazydocker     # TUI for Docker
      dive           # Analyze Docker images
      ctop           # Container metrics
    ];

    # Create docker data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataRoot} 0711 root root -"
    ];

    # Docker group is auto-created, users in this group can use docker
    # admin is already added via users.nix
  };
}
