# Development Tools Module
# Python and Node.js for NAS scripts and automation

{ config, pkgs, lib, ... }:

{
  imports = [
    ./python.nix
    ./nodejs.nix
  ];
}
