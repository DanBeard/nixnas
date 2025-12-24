# Grafana Configuration
# Dashboards and visualization for Prometheus metrics

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.monitoring;
in
{
  config = mkIf cfg.enable {
    services.grafana = {
      enable = true;

      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = 3000;
          domain = "grafana.nixnas.local";
          root_url = "http://grafana.nixnas.local";
        };

        security = {
          admin_user = "admin";
          # Password from sops secret
          admin_password = "$__file{${config.sops.secrets."grafana/admin-password".path}}";
        };

        # Disable analytics/telemetry
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
        };

        # Anonymous access (optional - for dashboard viewing)
        "auth.anonymous" = {
          enabled = false;
        };
      };

      # Provision data sources automatically
      provision = {
        enable = true;

        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://localhost:${toString config.services.prometheus.port}";
            isDefault = true;
            editable = false;
          }
        ];

        # Pre-configured dashboards
        dashboards.settings.providers = [
          {
            name = "NixNAS Dashboards";
            options.path = "/etc/grafana/dashboards";
            allowUiUpdates = false;
          }
        ];
      };
    };

    # Grafana admin password secret
    sops.secrets."grafana/admin-password" = {
      owner = "grafana";
      group = "grafana";
      mode = "0400";
    };

    # Pre-built dashboard for NAS monitoring
    environment.etc."grafana/dashboards/nixnas-overview.json".text = builtins.toJSON {
      annotations = { list = []; };
      editable = false;
      fiscalYearStartMonth = 0;
      graphTooltip = 0;
      id = null;
      links = [];
      liveNow = false;
      panels = [
        {
          title = "CPU Usage";
          type = "gauge";
          gridPos = { h = 8; w = 6; x = 0; y = 0; };
          targets = [{
            expr = "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)";
            refId = "A";
          }];
          fieldConfig = {
            defaults = {
              max = 100;
              min = 0;
              unit = "percent";
              thresholds = {
                mode = "absolute";
                steps = [
                  { color = "green"; value = null; }
                  { color = "yellow"; value = 60; }
                  { color = "red"; value = 80; }
                ];
              };
            };
          };
        }
        {
          title = "Memory Usage";
          type = "gauge";
          gridPos = { h = 8; w = 6; x = 6; y = 0; };
          targets = [{
            expr = "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100";
            refId = "A";
          }];
          fieldConfig = {
            defaults = {
              max = 100;
              min = 0;
              unit = "percent";
              thresholds = {
                mode = "absolute";
                steps = [
                  { color = "green"; value = null; }
                  { color = "yellow"; value = 70; }
                  { color = "red"; value = 85; }
                ];
              };
            };
          };
        }
        {
          title = "Disk Usage (Root)";
          type = "gauge";
          gridPos = { h = 8; w = 6; x = 12; y = 0; };
          targets = [{
            expr = "(1 - (node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"})) * 100";
            refId = "A";
          }];
          fieldConfig = {
            defaults = {
              max = 100;
              min = 0;
              unit = "percent";
              thresholds = {
                mode = "absolute";
                steps = [
                  { color = "green"; value = null; }
                  { color = "yellow"; value = 70; }
                  { color = "red"; value = 90; }
                ];
              };
            };
          };
        }
        {
          title = "System Load";
          type = "stat";
          gridPos = { h = 8; w = 6; x = 18; y = 0; };
          targets = [{
            expr = "node_load1";
            legendFormat = "1m";
            refId = "A";
          }];
        }
        {
          title = "Network Traffic";
          type = "timeseries";
          gridPos = { h = 8; w = 12; x = 0; y = 8; };
          targets = [
            {
              expr = "rate(node_network_receive_bytes_total{device!~\"lo|veth.*\"}[5m]) * 8";
              legendFormat = "{{device}} RX";
              refId = "A";
            }
            {
              expr = "rate(node_network_transmit_bytes_total{device!~\"lo|veth.*\"}[5m]) * 8";
              legendFormat = "{{device}} TX";
              refId = "B";
            }
          ];
          fieldConfig = {
            defaults = { unit = "bps"; };
          };
        }
        {
          title = "Disk I/O";
          type = "timeseries";
          gridPos = { h = 8; w = 12; x = 12; y = 8; };
          targets = [
            {
              expr = "rate(node_disk_read_bytes_total[5m])";
              legendFormat = "{{device}} read";
              refId = "A";
            }
            {
              expr = "rate(node_disk_written_bytes_total[5m])";
              legendFormat = "{{device}} write";
              refId = "B";
            }
          ];
          fieldConfig = {
            defaults = { unit = "Bps"; };
          };
        }
      ];
      refresh = "30s";
      schemaVersion = 38;
      style = "dark";
      tags = [ "nixnas" ];
      templating = { list = []; };
      time = { from = "now-1h"; to = "now"; };
      timepicker = {};
      timezone = "browser";
      title = "NixNAS Overview";
      uid = "nixnas-overview";
      version = 1;
      weekStart = "";
    };
  };
}
