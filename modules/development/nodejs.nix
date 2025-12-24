# Node.js Configuration
# Node.js LTS with Yarn and common tools

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.nodejs;
in
{
  options.nixnas.nodejs = {
    enable = mkEnableOption "Node.js development environment";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # Node.js 22 LTS (latest stable as of 2024)
      nodejs_22

      # Package managers
      yarn
      nodePackages.pnpm

      # Development tools
      nodePackages.typescript
      nodePackages.ts-node
      nodePackages.eslint
      nodePackages.prettier

      # Common utilities
      nodePackages.npm-check-updates
      nodePackages.nodemon
    ];

    # NPM global packages directory (per-user)
    environment.variables = {
      NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    };

    # Add npm global bin to path
    environment.shellInit = ''
      export PATH="$HOME/.npm-global/bin:$PATH"
    '';
  };
}
