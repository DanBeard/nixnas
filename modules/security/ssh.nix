# SSH Configuration
# Hardened SSH server with key-only authentication

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.security;
in
{
  config = mkIf cfg.enable {
    services.openssh = {
      enable = true;

      settings = {
        # Disable root login
        PermitRootLogin = "no";

        # Key-only authentication (no passwords)
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;

        # Disable empty passwords
        PermitEmptyPasswords = false;

        # Use strong ciphers only
        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
          "aes256-ctr"
          "aes192-ctr"
          "aes128-ctr"
        ];

        # Strong key exchange algorithms
        KexAlgorithms = [
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
          "diffie-hellman-group16-sha512"
          "diffie-hellman-group18-sha512"
        ];

        # Strong MACs
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
          "umac-128-etm@openssh.com"
        ];

        # Limit authentication attempts
        MaxAuthTries = 3;

        # Client alive settings (disconnect idle clients)
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;

        # Disable X11 forwarding (not needed for NAS)
        X11Forwarding = false;

        # Disable agent forwarding
        AllowAgentForwarding = false;

        # Allow TCP forwarding for tunnels (needed for some services)
        AllowTcpForwarding = true;

        # Log level
        LogLevel = "VERBOSE";

        # Restrict to specific users (optional)
        # AllowUsers = [ "admin" ];
      };

      # Host keys - prefer ed25519, also have RSA for compatibility
      hostKeys = [
        {
          path = "/etc/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
        {
          path = "/etc/ssh/ssh_host_rsa_key";
          type = "rsa";
          bits = 4096;
        }
      ];
    };

    # Enable SFTP via SSH
    services.openssh.allowSFTP = true;

    # SSH is already opened in firewall.nix (port 22)
  };
}
