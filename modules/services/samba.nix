# Samba Configuration
# SMB file sharing with macOS/Windows/Linux compatibility

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.samba;
in
{
  options.nixnas.samba = {
    enable = mkEnableOption "Samba file sharing";

    workgroup = mkOption {
      type = types.str;
      default = "WORKGROUP";
      description = "Windows workgroup name";
    };

    serverDescription = mkOption {
      type = types.str;
      default = "NixNAS File Server";
      description = "Server description shown in network browser";
    };

    shares = mkOption {
      type = types.attrsOf types.attrs;
      default = {
        media = {
          path = "/data/media";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "@samba";
          "create mask" = "0664";
          "directory mask" = "0775";
          "force group" = "media";
        };
        documents = {
          path = "/data/documents";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "@samba";
          "create mask" = "0660";
          "directory mask" = "0770";
        };
        downloads = {
          path = "/data/downloads";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "@samba";
          "create mask" = "0664";
          "directory mask" = "0775";
          "force group" = "media";
        };
      };
      description = "Samba share definitions";
    };

    timeMachineShare = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Time Machine backup share for macOS";
    };
  };

  config = mkIf cfg.enable {
    services.samba = {
      enable = true;
      openFirewall = true;

      # Use full Samba package for better compatibility
      package = pkgs.samba4Full;

      settings = {
        global = {
          workgroup = cfg.workgroup;
          "server string" = cfg.serverDescription;
          "netbios name" = config.networking.hostName;
          security = "user";

          # Performance tuning
          "socket options" = "TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072";
          "read raw" = "yes";
          "write raw" = "yes";
          "max xmit" = "65535";
          "dead time" = "15";
          "getwd cache" = "yes";

          # Use sendfile for better performance
          "use sendfile" = "yes";

          # Async I/O
          "aio read size" = "16384";
          "aio write size" = "16384";

          # Security - allow only local networks
          "hosts allow" = "192.168.0.0/16 172.16.0.0/12 10.0.0.0/8 127.0.0.1 localhost";
          "hosts deny" = "0.0.0.0/0";
          "guest account" = "nobody";
          "map to guest" = "never";

          # Disable printer sharing
          "load printers" = "no";
          printing = "bsd";
          "printcap name" = "/dev/null";
          "disable spoolss" = "yes";

          # macOS compatibility (Fruit VFS)
          "vfs objects" = "fruit streams_xattr";
          "fruit:metadata" = "stream";
          "fruit:model" = "MacSamba";
          "fruit:posix_rename" = "yes";
          "fruit:veto_appledouble" = "no";
          "fruit:nfs_aces" = "no";
          "fruit:wipe_intentionally_left_blank_rfork" = "yes";
          "fruit:delete_empty_adfiles" = "yes";

          # Logging
          "log file" = "/var/log/samba/log.%m";
          "max log size" = "1000";
          "log level" = "1";
        };
      } // cfg.shares // (optionalAttrs cfg.timeMachineShare {
        # Time Machine backup share
        timemachine = {
          path = "/data/backups/timemachine";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "@samba";
          "fruit:time machine" = "yes";
          "fruit:time machine max size" = "500G";
          "vfs objects" = "fruit streams_xattr";
        };
      });
    };

    # Windows Service Discovery
    services.samba-wsdd = {
      enable = true;
      openFirewall = true;
    };

    # Avahi for mDNS discovery (Bonjour)
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
        hinfo = true;
        userServices = true;
        workstation = true;
      };
      extraServiceFiles = {
        smb = ''
          <?xml version="1.0" standalone='no'?>
          <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
          <service-group>
            <name replace-wildcards="yes">%h</name>
            <service>
              <type>_smb._tcp</type>
              <port>445</port>
            </service>
          </service-group>
        '';
      } // (optionalAttrs cfg.timeMachineShare {
        timemachine = ''
          <?xml version="1.0" standalone='no'?>
          <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
          <service-group>
            <name replace-wildcards="yes">%h Time Machine</name>
            <service>
              <type>_adisk._tcp</type>
              <txt-record>sys=waMa=0,adVF=0x100</txt-record>
              <txt-record>dk0=adVN=timemachine,adVF=0x82</txt-record>
            </service>
            <service>
              <type>_smb._tcp</type>
              <port>445</port>
            </service>
          </service-group>
        '';
      });
    };

    # Create Time Machine directory
    systemd.tmpfiles.rules = mkIf cfg.timeMachineShare [
      "d /data/backups/timemachine 0770 root samba -"
    ];

    # Reminder to set samba passwords
    environment.etc."samba/README.md".text = ''
      # Samba Configuration

      ## Set User Password
      After adding a user to the samba group, set their Samba password:
      ```bash
      sudo smbpasswd -a username
      ```

      ## Add User to Samba Group
      Users must be in the 'samba' group to access shares:
      ```bash
      sudo usermod -aG samba username
      ```

      ## Test Configuration
      ```bash
      testparm
      ```

      ## List Shares
      ```bash
      smbclient -L localhost -U username
      ```
    '';
  };
}
