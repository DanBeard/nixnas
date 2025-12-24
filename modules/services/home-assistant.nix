# Home Assistant Configuration
# Native NixOS Home Assistant module (local-only, no cloud)

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.homeAssistant;
in
{
  options.nixnas.homeAssistant = {
    enable = mkEnableOption "Home Assistant";

    httpPort = mkOption {
      type = types.port;
      default = 8123;
      description = "Home Assistant web UI port";
    };

    configDir = mkOption {
      type = types.path;
      default = "/data/home-assistant";
      description = "Home Assistant configuration directory";
    };

    timeZone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      description = "Time zone for Home Assistant";
    };
  };

  config = mkIf cfg.enable {
    services.home-assistant = {
      enable = true;
      configDir = cfg.configDir;

      # Extra components to include
      extraComponents = [
        # Default/Core
        "default_config"
        "met"                 # Weather

        # Local integrations (no cloud)
        "esphome"             # ESP devices
        "mqtt"                # MQTT broker
        "zha"                 # Zigbee
        "zwave_js"            # Z-Wave

        # Network
        "mobile_app"          # Mobile app support
        "webhook"             # Webhooks
        "rest"                # REST API

        # Device types
        "light"
        "switch"
        "sensor"
        "binary_sensor"
        "climate"
        "cover"
        "fan"
        "media_player"

        # Notifications
        "notify"

        # History and logging
        "history"
        "logbook"
        "recorder"

        # Automation
        "automation"
        "script"
        "scene"

        # Local media
        "dlna_dmr"
        "cast"                # Local Chromecast

        # System monitoring
        "systemmonitor"

        # Calendar
        "local_calendar"
      ];

      # Extra packages for integrations
      extraPackages = python3Packages: with python3Packages; [
        psycopg2              # PostgreSQL support (optional)
        numpy                 # For some integrations
        pillow                # Image processing
        aiohttp-cors          # CORS support
      ];

      # Configuration
      config = {
        # Basic settings
        homeassistant = {
          name = "Home";
          unit_system = "metric";
          time_zone = cfg.timeZone;
          currency = "USD";

          # Local access only
          internal_url = "http://nixnas.local:${toString cfg.httpPort}";
        };

        # HTTP settings
        http = {
          server_port = cfg.httpPort;
          # Trust reverse proxy if using nginx
          use_x_forwarded_for = true;
          trusted_proxies = [ "127.0.0.1" "::1" ];
        };

        # Recorder with SQLite (default)
        recorder = {
          db_url = "sqlite:///${cfg.configDir}/home-assistant_v2.db";
          purge_keep_days = 10;
          commit_interval = 1;
        };

        # History
        history = {};

        # Logbook
        logbook = {};

        # Logger settings
        logger = {
          default = "info";
          logs = {
            "homeassistant.components.http" = "warning";
          };
        };

        # Default config enables common features
        default_config = {};

        # Automation and scripts from files
        automation = "!include automations.yaml";
        script = "!include scripts.yaml";
        scene = "!include scenes.yaml";
      };
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = [ cfg.httpPort ];

    # Ensure config directory exists with proper permissions
    systemd.tmpfiles.rules = [
      "d ${cfg.configDir} 0750 hass hass -"
    ];

    # Create empty automation/script/scene files if they don't exist
    system.activationScripts.home-assistant-files = ''
      mkdir -p ${cfg.configDir}
      for file in automations.yaml scripts.yaml scenes.yaml; do
        if [ ! -f ${cfg.configDir}/$file ]; then
          echo "[]" > ${cfg.configDir}/$file
          chown hass:hass ${cfg.configDir}/$file
        fi
      done
    '';

    # Avahi service for discovery
    services.avahi.extraServiceFiles.homeassistant = mkIf config.services.avahi.enable ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">Home Assistant on %h</name>
        <service>
          <type>_home-assistant._tcp</type>
          <port>${toString cfg.httpPort}</port>
        </service>
        <service>
          <type>_http._tcp</type>
          <port>${toString cfg.httpPort}</port>
        </service>
      </service-group>
    '';
  };
}
