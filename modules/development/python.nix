# Python Configuration
# Python 3.12 with common development tools

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.python;
in
{
  options.nixnas.python = {
    enable = mkEnableOption "Python 3.12 development environment";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # Python 3.12
      python312
      python312Packages.pip
      python312Packages.virtualenv

      # Package management
      pipx
      uv  # Fast Python package installer

      # Development tools
      python312Packages.pytest
      python312Packages.black
      python312Packages.ruff
      python312Packages.mypy

      # Common libraries useful for NAS scripts
      python312Packages.requests
      python312Packages.pyyaml
      python312Packages.python-dotenv
      python312Packages.click

      # System/file utilities
      python312Packages.psutil
      python312Packages.watchdog
    ];

    # Set Python 3.12 as default python3
    environment.variables = {
      PYTHON = "${pkgs.python312}/bin/python3";
    };

    # Shell alias
    programs.bash.shellAliases = {
      python = "python3";
      pip = "pip3";
    };
  };
}
