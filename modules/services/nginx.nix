# Nginx Configuration
# Local reverse proxy for services (no SSL, local network only)

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.nginx;
in
{
  options.nixnas.nginx = {
    enable = mkEnableOption "Nginx reverse proxy";
  };

  config = mkIf cfg.enable {
    services.nginx = {
      enable = true;

      # Recommended settings
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;

      # Security headers
      commonHttpConfig = ''
        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        # Logging format
        log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$http_x_forwarded_for"';
      '';

      # Virtual hosts for each service
      virtualHosts = {
        # Default landing page
        "nixnas.local" = {
          default = true;
          listen = [{ addr = "0.0.0.0"; port = 80; }];
          locations."/" = {
            return = "200 '<html><head><title>NixNAS</title></head><body><h1>NixNAS Services</h1><ul>${
              concatStringsSep "" [
                (optionalString config.nixnas.homeAssistant.enable "<li><a href=\"/homeassistant/\">Home Assistant</a></li>")
                (optionalString config.nixnas.transmission.enable "<li><a href=\"/transmission/\">Transmission</a></li>")
                (optionalString config.nixnas.jellyfin.enable "<li><a href=\"/jellyfin/\">Jellyfin</a></li>")
                (optionalString config.nixnas.syncthing.enable "<li><a href=\":8384\">Syncthing</a></li>")
                (optionalString config.nixnas.nextcloud.enable "<li><a href=\"/\">Nextcloud</a> (port 8080)</li>")
                (optionalString config.nixnas.monitoring.enable "<li><a href=\"/grafana/\">Grafana</a></li>")
              ]
            }</ul></body></html>'";
            extraConfig = ''
              default_type text/html;
            '';
          };
        };

        # Home Assistant proxy
        "homeassistant.nixnas.local" = mkIf config.nixnas.homeAssistant.enable {
          listen = [{ addr = "0.0.0.0"; port = 80; }];
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString config.nixnas.homeAssistant.httpPort}";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
            '';
          };
        };

        # Transmission proxy
        "transmission.nixnas.local" = mkIf config.nixnas.transmission.enable {
          listen = [{ addr = "0.0.0.0"; port = 80; }];
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString config.nixnas.transmission.webUIPort}";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };
        };

        # Jellyfin proxy
        "jellyfin.nixnas.local" = mkIf config.nixnas.jellyfin.enable {
          listen = [{ addr = "0.0.0.0"; port = 80; }];
          locations."/" = {
            proxyPass = "http://127.0.0.1:8096";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_buffering off;
            '';
          };
        };

        # Grafana proxy
        "grafana.nixnas.local" = mkIf config.nixnas.monitoring.enable {
          listen = [{ addr = "0.0.0.0"; port = 80; }];
          locations."/" = {
            proxyPass = "http://127.0.0.1:3000";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };
        };
      };
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
