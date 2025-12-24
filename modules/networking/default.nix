# Networking Module
# WireGuard VPN server configuration

{ config, pkgs, lib, ... }:

{
  imports = [
    ./wireguard.nix
  ];
}
