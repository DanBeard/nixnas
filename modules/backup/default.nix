# Backup Module
# ZFS snapshot management

{ config, pkgs, lib, ... }:

{
  imports = [
    ./zfs-snapshots.nix
  ];

  options.nixnas.backup = {
    enable = lib.mkEnableOption "Backup configuration";
  };
}
