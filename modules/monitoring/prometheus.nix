# Prometheus Configuration
# Metrics collection with node and ZFS exporters

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.monitoring;
in
{
  config = mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = 9090;

      # Retention settings
      retentionTime = "30d";

      # Global scrape configuration
      globalConfig = {
        scrape_interval = "15s";
        evaluation_interval = "15s";
      };

      # Scrape configurations
      scrapeConfigs = [
        # Prometheus self-monitoring
        {
          job_name = "prometheus";
          static_configs = [{
            targets = [ "localhost:9090" ];
          }];
        }

        # Node exporter (system metrics)
        {
          job_name = "node";
          static_configs = [{
            targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
          }];
        }

        # ZFS exporter
        {
          job_name = "zfs";
          static_configs = [{
            targets = [ "localhost:${toString config.services.prometheus.exporters.zfs.port}" ];
          }];
        }
      ];

      # Alerting rules (optional)
      rules = [
        ''
          groups:
            - name: system_alerts
              rules:
                - alert: HighCPUUsage
                  expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
                  for: 5m
                  labels:
                    severity: warning
                  annotations:
                    summary: "High CPU usage detected"
                    description: "CPU usage is above 80% for more than 5 minutes"

                - alert: HighMemoryUsage
                  expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
                  for: 5m
                  labels:
                    severity: warning
                  annotations:
                    summary: "High memory usage detected"
                    description: "Memory usage is above 85%"

                - alert: DiskSpaceLow
                  expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
                  for: 5m
                  labels:
                    severity: critical
                  annotations:
                    summary: "Low disk space on root filesystem"
                    description: "Less than 10% disk space remaining"

                - alert: ZFSPoolDegraded
                  expr: zfs_pool_health != 0
                  for: 1m
                  labels:
                    severity: critical
                  annotations:
                    summary: "ZFS pool is not healthy"
                    description: "ZFS pool health check failed"
        ''
      ];
    };

    # Node exporter for system metrics
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
      enabledCollectors = [
        "systemd"
        "processes"
        "filesystem"
        "diskstats"
        "netdev"
        "meminfo"
        "loadavg"
        "cpu"
        "vmstat"
        "textfile"
        "time"
      ];
      # Exclude certain filesystems
      extraFlags = [
        "--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|run)($|/)"
      ];
    };

    # ZFS exporter for pool metrics
    services.prometheus.exporters.zfs = {
      enable = true;
      port = 9134;
    };
  };
}
