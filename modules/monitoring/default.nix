# Monitoring Module
# Prometheus metrics and Grafana dashboards

{ config, pkgs, lib, ... }:

{
  imports = [
    ./prometheus.nix
    ./grafana.nix
  ];

  options.nixnas.monitoring = {
    enable = lib.mkEnableOption "Monitoring stack (Prometheus + Grafana)";
  };
}
