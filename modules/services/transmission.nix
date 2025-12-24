# Transmission Configuration
# Torrent client with web UI

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.transmission;
in
{
  options.nixnas.transmission = {
    enable = mkEnableOption "Transmission torrent client";

    downloadDir = mkOption {
      type = types.path;
      default = "/data/downloads";
      description = "Download directory";
    };

    webUIPort = mkOption {
      type = types.port;
      default = 9091;
      description = "Web UI port";
    };

    peerPort = mkOption {
      type = types.port;
      default = 51413;
      description = "Peer connection port";
    };

    uploadLimitKB = mkOption {
      type = types.int;
      default = 1000;
      description = "Upload speed limit in KB/s (0 = unlimited)";
    };

    ratioLimit = mkOption {
      type = types.float;
      default = 2.0;
      description = "Stop seeding at this ratio";
    };
  };

  config = mkIf cfg.enable {
    services.transmission = {
      enable = true;
      package = pkgs.transmission_4;

      # Open firewall for RPC and peer connections
      openRPCPort = true;
      openPeerPorts = true;

      settings = {
        # Download locations
        download-dir = cfg.downloadDir;
        incomplete-dir = "${cfg.downloadDir}/.incomplete";
        incomplete-dir-enabled = true;

        # Watch directory for .torrent files
        watch-dir = "${cfg.downloadDir}/.watch";
        watch-dir-enabled = true;

        # Web UI
        rpc-enabled = true;
        rpc-port = cfg.webUIPort;
        rpc-bind-address = "0.0.0.0";
        rpc-whitelist-enabled = true;
        rpc-whitelist = "127.0.0.1,192.168.*.*,10.*.*.*,172.16.*.*";
        rpc-host-whitelist-enabled = false;

        # Authentication
        rpc-authentication-required = true;
        rpc-username = "transmission";
        # Password is set via credentialsFile

        # Peer settings
        peer-port = cfg.peerPort;
        peer-port-random-on-start = false;

        # Encryption (prefer encryption)
        encryption = 2;

        # Speed limits
        speed-limit-down-enabled = false;
        speed-limit-up-enabled = cfg.uploadLimitKB > 0;
        speed-limit-up = cfg.uploadLimitKB;

        # Alt speed (scheduled limits - optional)
        alt-speed-enabled = false;
        alt-speed-down = 500;
        alt-speed-up = 100;

        # Queue settings
        download-queue-enabled = true;
        download-queue-size = 5;
        seed-queue-enabled = true;
        seed-queue-size = 10;

        # Ratio limits
        ratio-limit-enabled = true;
        ratio-limit = cfg.ratioLimit;

        # Idle seeding limit (stop after 30 min idle)
        idle-seeding-limit-enabled = true;
        idle-seeding-limit = 30;

        # Protocol settings
        dht-enabled = true;
        pex-enabled = true;
        lpd-enabled = true;
        utp-enabled = true;

        # Performance
        cache-size-mb = 64;
        prefetch-enabled = true;

        # Connection limits
        peer-limit-global = 500;
        peer-limit-per-torrent = 50;

        # File settings
        rename-partial-files = true;
        start-added-torrents = true;
        trash-original-torrent-files = false;

        # Misc
        scrape-paused-torrents-enabled = true;
      };

      # Credentials file for RPC password
      credentialsFile = config.sops.secrets."transmission/credentials".path;
    };

    # Sops secret for credentials
    sops.secrets."transmission/credentials" = {
      owner = "transmission";
      group = "transmission";
      mode = "0400";
    };

    # Add admin to transmission group for file access
    users.users.admin.extraGroups = mkAfter [ "transmission" ];

    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.downloadDir} 0775 transmission transmission -"
      "d ${cfg.downloadDir}/.incomplete 0775 transmission transmission -"
      "d ${cfg.downloadDir}/.watch 0775 transmission transmission -"
    ];

    # Avahi service for discovery
    services.avahi.extraServiceFiles.transmission = mkIf config.services.avahi.enable ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">Transmission on %h</name>
        <service>
          <type>_http._tcp</type>
          <port>${toString cfg.webUIPort}</port>
          <txt-record>path=/transmission/web/</txt-record>
        </service>
      </service-group>
    '';
  };
}
