# Security Module
# Firewall, SSH hardening, fail2ban, and automatic updates

{ config, pkgs, lib, ... }:

{
  imports = [
    ./firewall.nix
    ./ssh.nix
    ./fail2ban.nix
    ./auto-updates.nix
  ];

  options.nixnas.security = {
    enable = lib.mkEnableOption "security hardening";

    autoUpdates = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic security updates";
    };

    autoReboot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic reboot after kernel updates";
    };
  };
}
