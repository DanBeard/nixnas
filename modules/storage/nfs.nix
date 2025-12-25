# NFS Server Configuration
# Export ZFS datasets for other hosts (e.g., homelab mounting storage-node)

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.nfs;
in
{
  options.nixnas.nfs = {
    enable = mkEnableOption "NFS server for sharing ZFS datasets";

    exports = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of directories to export via NFS";
      example = [ "/data/media" "/data/downloads" ];
    };

    allowedClients = mkOption {
      type = types.str;
      default = "10.0.0.0/8";
      description = "IP range allowed to mount NFS exports";
      example = "192.168.1.0/24";
    };

    options = mkOption {
      type = types.str;
      default = "rw,sync,no_subtree_check,no_root_squash";
      description = "NFS export options";
    };
  };

  config = mkIf cfg.enable {
    # Enable NFS server
    services.nfs.server = {
      enable = true;

      # Build exports string from configuration
      exports = concatStringsSep "\n" (map (dir:
        "${dir} ${cfg.allowedClients}(${cfg.options})"
      ) cfg.exports);
    };

    # Open firewall for NFS
    networking.firewall = {
      allowedTCPPorts = [
        111   # rpcbind
        2049  # nfs
        20048 # mountd
      ];
      allowedUDPPorts = [
        111   # rpcbind
        2049  # nfs
        20048 # mountd
      ];
    };

    # Ensure rpcbind is enabled
    services.rpcbind.enable = true;
  };
}
