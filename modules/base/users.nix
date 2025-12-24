# User Management
# Admin user and group configuration

{ config, pkgs, lib, ... }:

{
  # Primary admin user
  users.users.admin = {
    isNormalUser = true;
    description = "NAS Administrator";
    extraGroups = [
      "wheel"           # sudo access
      "networkmanager"  # network management
      "docker"          # docker access
      "transmission"    # transmission access
      "video"           # video device access (for transcoding)
      "render"          # GPU render access
    ];
    shell = pkgs.zsh;

    # SSH authorized keys
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGuS/j26YvHyjMPCAYimUW6F85hrL+MPDvmurgAzFONl deck@steamdeck"
    ];
  };

  # Root user configuration
  users.users.root = {
    # Disable root password login (use sudo instead)
    hashedPassword = "!"; # Locked password
  };

  # Mutable users disabled for declarative user management
  # Set to true if you want to manage passwords imperatively
  users.mutableUsers = true;

  # Sudo configuration
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;

    # Allow passwordless sudo for specific commands (optional)
    extraRules = [
      {
        groups = [ "wheel" ];
        commands = [
          {
            command = "${pkgs.systemd}/bin/systemctl status *";
            options = [ "NOPASSWD" ];
          }
          {
            command = "${pkgs.systemd}/bin/journalctl *";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };

  # Security settings
  security.polkit.enable = true;

  # PAM settings for better security
  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "65536";
    }
    {
      domain = "*";
      type = "hard";
      item = "nofile";
      value = "524288";
    }
  ];

  # Create common groups
  users.groups = {
    # Media group for shared access to media files
    media = {
      gid = 985;
    };
    # Samba group for file sharing access
    samba = {
      gid = 986;
    };
  };

  # Add admin to media and samba groups
  users.users.admin.extraGroups = lib.mkAfter [ "media" "samba" ];
}
