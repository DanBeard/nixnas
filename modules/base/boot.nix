# Boot Configuration
# Bootloader, kernel, and ZFS support for USB boot drive

{ config, pkgs, lib, ... }:

{
  # UEFI boot loader (systemd-boot)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Limit boot menu entries to save space
  boot.loader.systemd-boot.configurationLimit = 10;

  # Use latest compatible kernel for ZFS
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  # ZFS filesystem support
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  # Enable ZFS in initrd for early pool import
  boot.initrd.supportedFilesystems = [ "zfs" ];

  # Kernel parameters optimized for USB boot
  boot.kernelParams = [
    # Reduce writes to USB drive
    "noatime"
  ];

  # Common kernel modules for NAS hardware
  boot.initrd.availableKernelModules = [
    "xhci_pci"      # USB 3.0
    "ahci"          # SATA
    "usbhid"        # USB HID
    "usb_storage"   # USB storage
    "sd_mod"        # SCSI disk
    "nvme"          # NVMe drives
    "sr_mod"        # SCSI CD-ROM (for install media)
  ];

  # Intel/AMD microcode updates
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Enable firmware for hardware support
  hardware.enableRedistributableFirmware = true;

  # Kernel sysctl settings for server workload
  boot.kernel.sysctl = {
    # Network performance
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";

    # File system performance
    "vm.swappiness" = 10;
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;

    # Increase max file handles for NAS workloads
    "fs.file-max" = 2097152;
  };
}
