# NFS Client Configuration
# Mount NFS shares from OpenMediaVault or other NFS servers

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.nfsClient;
in
{
  options.nixnas.nfsClient = {
    enable = mkEnableOption "NFS client for mounting remote shares";

    nasAddress = mkOption {
      type = types.str;
      default = "192.168.1.100";
      description = "IP address or hostname of the NFS server (e.g., OMV NAS)";
      example = "192.168.1.100";
    };

    mounts = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          remotePath = mkOption {
            type = types.str;
            description = "Remote NFS export path on the server";
            example = "/srv/media";
          };
          localPath = mkOption {
            type = types.str;
            description = "Local mount point";
            example = "/mnt/nas/media";
          };
          options = mkOption {
            type = types.listOf types.str;
            default = [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" "x-systemd.idle-timeout=600" ];
            description = "NFS mount options";
          };
        };
      });
      default = {};
      description = "NFS mounts to configure";
      example = literalExpression ''
        {
          media = {
            remotePath = "/srv/media";
            localPath = "/mnt/nas/media";
          };
          downloads = {
            remotePath = "/srv/downloads";
            localPath = "/mnt/nas/downloads";
          };
        }
      '';
    };

    # Predefined mount sets for common setups
    enableDefaultMounts = mkOption {
      type = types.bool;
      default = true;
      description = "Enable default mount points for media, downloads, documents, backups, nextcloud, syncthing";
    };
  };

  config = mkIf cfg.enable {
    # Install NFS client utilities
    environment.systemPackages = with pkgs; [
      nfs-utils
    ];

    # Enable NFS client services
    services.rpcbind.enable = true;

    # Create mount directories
    systemd.tmpfiles.rules =
      let
        allMounts = if cfg.enableDefaultMounts then
          {
            media = { remotePath = "/srv/media"; localPath = "/mnt/nas/media"; options = cfg.mounts.media.options or [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" ]; };
            downloads = { remotePath = "/srv/downloads"; localPath = "/mnt/nas/downloads"; options = cfg.mounts.downloads.options or [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" ]; };
            documents = { remotePath = "/srv/documents"; localPath = "/mnt/nas/documents"; options = cfg.mounts.documents.options or [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" ]; };
            backups = { remotePath = "/srv/backups"; localPath = "/mnt/nas/backups"; options = cfg.mounts.backups.options or [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" ]; };
            nextcloud = { remotePath = "/srv/nextcloud"; localPath = "/mnt/nas/nextcloud"; options = cfg.mounts.nextcloud.options or [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" ]; };
            syncthing = { remotePath = "/srv/syncthing"; localPath = "/mnt/nas/syncthing"; options = cfg.mounts.syncthing.options or [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" ]; };
          } // cfg.mounts
        else
          cfg.mounts;
      in
        [ "d /mnt/nas 0755 root root -" ] ++
        (mapAttrsToList (name: mount: "d ${mount.localPath} 0755 root root -") allMounts);

    # Configure NFS mounts using fileSystems
    fileSystems =
      let
        defaultMounts = {
          media = { remotePath = "/srv/media"; localPath = "/mnt/nas/media"; options = [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" "x-systemd.idle-timeout=600" ]; };
          downloads = { remotePath = "/srv/downloads"; localPath = "/mnt/nas/downloads"; options = [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" "x-systemd.idle-timeout=600" ]; };
          documents = { remotePath = "/srv/documents"; localPath = "/mnt/nas/documents"; options = [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" "x-systemd.idle-timeout=600" ]; };
          backups = { remotePath = "/srv/backups"; localPath = "/mnt/nas/backups"; options = [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" "x-systemd.idle-timeout=600" ]; };
          nextcloud = { remotePath = "/srv/nextcloud"; localPath = "/mnt/nas/nextcloud"; options = [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" "x-systemd.idle-timeout=600" ]; };
          syncthing = { remotePath = "/srv/syncthing"; localPath = "/mnt/nas/syncthing"; options = [ "nfsvers=4" "soft" "timeo=100" "retrans=3" "_netdev" "x-systemd.automount" "x-systemd.idle-timeout=600" ]; };
        };
        allMounts = if cfg.enableDefaultMounts then defaultMounts // cfg.mounts else cfg.mounts;
      in
        mapAttrs' (name: mount:
          nameValuePair mount.localPath {
            device = "${cfg.nasAddress}:${mount.remotePath}";
            fsType = "nfs";
            options = mount.options;
          }
        ) allMounts;

    # Open firewall for NFS client (outbound is usually allowed, but ensure rpcbind works)
    networking.firewall = {
      allowedTCPPorts = [ 111 ]; # rpcbind (usually not needed for client-only)
      allowedUDPPorts = [ 111 ];
    };
  };
}
