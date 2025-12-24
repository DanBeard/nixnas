# Syncthing Configuration
# P2P file synchronization (LAN + WireGuard only, no cloud relays)

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.syncthing;
in
{
  options.nixnas.syncthing = {
    enable = mkEnableOption "Syncthing file synchronization";

    user = mkOption {
      type = types.str;
      default = "admin";
      description = "User to run Syncthing as";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/data/syncthing";
      description = "Syncthing data directory";
    };

    guiPort = mkOption {
      type = types.port;
      default = 8384;
      description = "Syncthing GUI port";
    };
  };

  config = mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = cfg.user;
      dataDir = cfg.dataDir;
      configDir = "${cfg.dataDir}/.config/syncthing";

      # Open standard ports
      openDefaultPorts = true;

      # GUI settings
      guiAddress = "0.0.0.0:${toString cfg.guiPort}";

      settings = {
        gui = {
          theme = "dark";
          # Insecure admin access on local network only
          # Set password via GUI after first access
        };

        options = {
          # Disable telemetry
          urAccepted = -1;

          # Local discovery (LAN)
          localAnnounceEnabled = true;
          localAnnouncePort = 21027;
          localAnnounceMCAddr = "[ff12::8384]:21027";

          # DISABLE global discovery (no cloud relays)
          globalAnnounceEnabled = false;

          # DISABLE relays (direct connections only via LAN/WireGuard)
          relaysEnabled = false;

          # NAT traversal (useful for WireGuard peers)
          natEnabled = true;

          # Rate limits (0 = unlimited)
          maxSendKbps = 0;
          maxRecvKbps = 0;

          # Connection limits
          limitBandwidthInLan = false;

          # Keep N versions of files
          maxFolderConcurrency = 2;
        };

        # Folders and devices can be configured via GUI
        # or declaratively here - leaving empty for GUI config
      };

      # Don't override device/folder configs (allow GUI changes)
      overrideDevices = false;
      overrideFolders = false;
    };

    # Open GUI port
    networking.firewall.allowedTCPPorts = [ cfg.guiPort ];

    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.user} -"
    ];

    # Avahi service for local discovery
    services.avahi.extraServiceFiles.syncthing = mkIf config.services.avahi.enable ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">Syncthing on %h</name>
        <service>
          <type>_syncthing._tcp</type>
          <port>22000</port>
        </service>
        <service>
          <type>_http._tcp</type>
          <port>${toString cfg.guiPort}</port>
        </service>
      </service-group>
    '';
  };
}
