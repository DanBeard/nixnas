# Nix Configuration
# Flakes, garbage collection, and store optimization

{ config, pkgs, lib, ... }:

{
  # Enable flakes and nix-command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Optimize store automatically
  nix.settings.auto-optimise-store = true;

  # Garbage collection - clean up weekly
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Store optimization
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  # Allow unfree packages (for firmware, drivers, etc.)
  nixpkgs.config.allowUnfree = true;

  # Trust wheel group users for remote builds
  nix.settings.trusted-users = [ "root" "@wheel" ];

  # Use all cores for building
  nix.settings.max-jobs = "auto";
  nix.settings.cores = 0; # Use all available cores

  # Keep build dependencies for debugging
  nix.settings.keep-outputs = true;
  nix.settings.keep-derivations = true;

  # Substitute settings
  nix.settings.substituters = [
    "https://cache.nixos.org"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];

  # System version for state compatibility
  system.stateVersion = "24.11";
}
