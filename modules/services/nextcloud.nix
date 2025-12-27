# Nextcloud Configuration
# Self-hosted cloud storage, calendar, and contacts

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.nextcloud;
in
{
  options.nixnas.nextcloud = {
    enable = mkEnableOption "Nextcloud";

    hostName = mkOption {
      type = types.str;
      default = "nextcloud.nixnas.local";
      description = "Nextcloud hostname";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/data/nextcloud";
      description = "Nextcloud data directory";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8080;
      description = "HTTP port for Nextcloud";
    };

    maxUploadSize = mkOption {
      type = types.str;
      default = "16G";
      description = "Maximum upload size";
    };
  };

  config = mkIf cfg.enable {
    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud30;
      hostName = cfg.hostName;
      datadir = cfg.dataDir;

      # Use HTTPS = false for local network (reverse proxy can add HTTPS)
      https = false;

      # Auto-update apps
      autoUpdateApps.enable = true;
      autoUpdateApps.startAt = "05:00:00";

      # Configuration
      config = {
        # Database - use SQLite for simplicity
        # For larger installations, consider PostgreSQL
        dbtype = "sqlite";

        # Admin user
        adminuser = "admin";
        adminpassFile = "/var/lib/nextcloud-admin-pass";
      };

      # PHP settings
      phpOptions = {
        "opcache.interned_strings_buffer" = "16";
        "opcache.max_accelerated_files" = "10000";
        "opcache.memory_consumption" = "128";
        "opcache.save_comments" = "1";
        "opcache.revalidate_freq" = "1";
      };

      # Settings
      settings = {
        # Trusted domains
        trusted_domains = [
          cfg.hostName
          "nixnas.local"
          "localhost"
        ];

        # Default phone region
        default_phone_region = "US";

        # Maintenance window (for background jobs)
        maintenance_window_start = 1;  # 1 AM

        # Log level
        loglevel = 2;  # 0=Debug, 1=Info, 2=Warning, 3=Error

        # Preview settings
        enabledPreviewProviders = [
          "OC\\Preview\\BMP"
          "OC\\Preview\\GIF"
          "OC\\Preview\\JPEG"
          "OC\\Preview\\PNG"
          "OC\\Preview\\HEIC"
          "OC\\Preview\\Movie"
          "OC\\Preview\\MP3"
          "OC\\Preview\\TXT"
          "OC\\Preview\\MarkDown"
        ];
      };

      # Max upload size
      maxUploadSize = cfg.maxUploadSize;

      # Enable caching with APCu
      configureRedis = false;
      caching.apcu = true;
    };

    # Nginx configuration for Nextcloud
    services.nginx.virtualHosts.${cfg.hostName} = {
      listen = [{ addr = "0.0.0.0"; port = cfg.httpPort; }];
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = [ cfg.httpPort ];

    # Generate admin password on first boot if it doesn't exist
    system.activationScripts.nextcloud-admin-pass = ''
      PASS_FILE="/var/lib/nextcloud-admin-pass"
      if [ ! -f "$PASS_FILE" ]; then
        echo "Generating Nextcloud admin password..."
        PASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 16 | tr -d '/+=' | head -c 16)
        echo -n "$PASSWORD" > "$PASS_FILE"
        chmod 600 "$PASS_FILE"
        chown nextcloud:nextcloud "$PASS_FILE" 2>/dev/null || true

        # Save password to summary file
        echo "Nextcloud - User: admin, Password: $PASSWORD" >> /var/lib/nixnas-passwords.txt
        chmod 600 /var/lib/nixnas-passwords.txt
      fi
    '';

    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 nextcloud nextcloud -"
    ];

    # Avahi service for discovery
    services.avahi.extraServiceFiles.nextcloud = mkIf config.services.avahi.enable ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">Nextcloud on %h</name>
        <service>
          <type>_http._tcp</type>
          <port>${toString cfg.httpPort}</port>
        </service>
        <service>
          <type>_webdav._tcp</type>
          <port>${toString cfg.httpPort}</port>
          <txt-record>path=/remote.php/dav</txt-record>
        </service>
      </service-group>
    '';
  };
}
