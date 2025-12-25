# Storage Module
# ZFS pool and dataset configuration

{ config, pkgs, lib, ... }:

{
  imports = [
    ./zfs.nix
    ./nfs.nix
  ];
}
