# Fail2ban Configuration
# Brute-force attack protection with progressive bans

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.security;
in
{
  config = mkIf cfg.enable {
    services.fail2ban = {
      enable = true;

      # Maximum retry attempts before ban
      maxretry = 5;

      # Default ban time
      bantime = "1h";

      # Time window for counting failures
      findtime = "10m";

      # Ignore local networks (won't be banned)
      ignoreIP = [
        "127.0.0.0/8"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "::1"
        "fe80::/10"
      ];

      # Progressive ban time increase for repeat offenders
      bantime-increment = {
        enable = true;
        multipliers = "1 2 4 8 16 32 64";
        maxtime = "1w"; # Maximum 1 week ban
        overalljails = true;
      };

      # Jail configurations
      jails = {
        # SSH protection (primary concern)
        sshd = {
          settings = {
            enabled = true;
            port = "ssh";
            filter = "sshd";
            maxretry = 3;
            bantime = "24h";
            findtime = "1h";
          };
        };

        # SSH with aggressive settings for persistent attackers
        sshd-aggressive = {
          settings = {
            enabled = true;
            port = "ssh";
            filter = "sshd[mode=aggressive]";
            maxretry = 2;
            bantime = "1w";
            findtime = "24h";
          };
        };

        # Nginx jail (enabled when nginx is running)
        nginx-http-auth = {
          settings = {
            enabled = config.services.nginx.enable;
            port = "http,https";
            filter = "nginx-http-auth";
            maxretry = 5;
            bantime = "1h";
          };
        };

        # Nginx bad bots
        nginx-botsearch = {
          settings = {
            enabled = config.services.nginx.enable;
            port = "http,https";
            filter = "nginx-botsearch";
            maxretry = 2;
            bantime = "1d";
          };
        };
      };
    };

    # Ensure fail2ban log directory exists
    systemd.tmpfiles.rules = [
      "d /var/log/fail2ban 0750 root root -"
    ];
  };
}
