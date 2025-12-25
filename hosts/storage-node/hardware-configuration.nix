# Hardware Configuration for Storage Node (QNAP TS-269 Pro)
# Intel Atom D2700, 1GB RAM (expandable to 3GB)

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # =============================================================================
  # BOOT CONFIGURATION
  # =============================================================================

  boot.initrd.availableKernelModules = [
    "xhci_pci"      # USB 3.0
    "ahci"          # SATA
    "usbhid"        # USB keyboard/mouse
    "usb_storage"   # USB drives
    "sd_mod"        # SCSI disks
  ];

  # Intel Atom D2700 uses kvm-intel
  boot.kernelModules = [ "kvm-intel" ];

  # =============================================================================
  # FILESYSTEM CONFIGURATION
  # =============================================================================

  # USB Boot Drive
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "ext4";
    options = [ "noatime" "discard" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
  };

  # ZFS datasets are mounted automatically via zfs.nix

  # =============================================================================
  # HARDWARE SETTINGS
  # =============================================================================

  hardware.enableRedistributableFirmware = lib.mkDefault true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
