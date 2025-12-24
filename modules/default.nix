# NixNAS Module Aggregator
# This file imports all modules and defines the nixnas option namespace

{ config, pkgs, lib, ... }:

{
  imports = [
    ./base
    ./storage
    ./security
    ./networking
    ./services
    ./monitoring
    ./backup
    ./development
  ];

  # Define the nixnas namespace for all our options
  options.nixnas = {
    # This will be populated by individual modules
  };
}
