# Services Module
# Core NAS services and additional applications

{ config, pkgs, lib, ... }:

{
  imports = [
    ./samba.nix
    ./home-assistant.nix
    ./transmission.nix
    ./docker.nix
    ./nginx.nix
    ./jellyfin.nix
    ./syncthing.nix
    ./nextcloud.nix
  ];
}
