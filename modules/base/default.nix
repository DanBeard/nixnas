# Base System Configuration
# Core system settings, boot, nix configuration, and user management

{ config, pkgs, lib, ... }:

{
  imports = [
    ./boot.nix
    ./nix-settings.nix
    ./users.nix
  ];

  # Essential system packages available everywhere
  environment.systemPackages = with pkgs; [
    # Editors
    vim
    nano

    # System utilities
    htop
    btop
    tmux
    tree
    file
    which

    # Network tools
    wget
    curl
    rsync
    inetutils
    dnsutils
    nmap
    iperf3

    # Filesystem tools
    parted
    gptfdisk
    ncdu

    # Compression
    gzip
    bzip2
    xz
    zstd
    unzip
    p7zip

    # Monitoring
    lsof
    iotop
    sysstat

    # Git for config management
    git
  ];

  # Enable zsh as an available shell
  programs.zsh.enable = true;

  # Basic shell aliases
  programs.bash.shellAliases = {
    ll = "ls -la";
    la = "ls -A";
    l = "ls -CF";
    ".." = "cd ..";
    "..." = "cd ../..";
  };

  # Disable documentation to save space on USB boot drive
  documentation.nixos.enable = lib.mkDefault false;
  documentation.man.enable = lib.mkDefault true;
  documentation.info.enable = lib.mkDefault false;
  documentation.doc.enable = lib.mkDefault false;
}
