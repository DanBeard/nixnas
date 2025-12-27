# Storage Module
# ZFS, NFS server, and NFS client configuration

{ config, pkgs, lib, ... }:

{
  imports = [
    ./zfs.nix
    ./nfs.nix        # NFS server (for storage-node)
    ./nfs-client.nix # NFS client (for homelab mounting remote storage)
  ];
}
