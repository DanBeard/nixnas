# =============================================================================
# Pi Zero 2W Hardware Configuration
# =============================================================================
# Hardware-specific settings for Raspberry Pi Zero 2W
# Based on the BCM2710A1 (same family as Pi 3)
# =============================================================================

{ config, lib, pkgs, ... }:

{
  # =============================================================================
  # Boot Configuration
  # =============================================================================

  boot = {
    # Use the Pi-specific kernel
    kernelPackages = pkgs.linuxPackages_rpi4;

    # Essential kernel modules
    initrd.availableKernelModules = [
      "usbhid"
      "usb_storage"
      "vc4"
      "bcm2835_dma"
      "i2c_bcm2835"
    ];

    # Load these at boot
    kernelModules = [ ];

    # Kernel parameters for Pi
    kernelParams = [
      "console=ttyS1,115200"
      "console=tty0"
    ];

    # Use extlinux bootloader (standard for Pi)
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };

    # Tmp on tmpfs to reduce SD card wear
    tmp.useTmpfs = true;
  };

  # =============================================================================
  # Filesystems
  # =============================================================================

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = [ "noatime" ];  # Reduce SD card writes
  };

  # No swap - Pi Zero 2W only has 512MB RAM, but swap kills SD cards
  swapDevices = [ ];

  # Use zram for compressed memory instead of swap
  zramSwap = {
    enable = true;
    memoryPercent = 50;  # Use up to 50% of RAM as compressed swap
  };

  # =============================================================================
  # Hardware Settings
  # =============================================================================

  hardware = {
    # Enable GPU firmware
    enableRedistributableFirmware = true;

    # Raspberry Pi firmware
    firmware = [ pkgs.raspberrypiWirelessFirmware ];
  };

  # =============================================================================
  # Power Management
  # =============================================================================

  # Disable due to Pi limitations
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";

  # =============================================================================
  # Workarounds for Pi Zero 2W
  # =============================================================================

  # The Pi Zero 2W uses the same SoC as Pi 3, but some device tree
  # quirks may apply. These settings ensure compatibility.

  # Ensure firmware is loaded
  boot.kernelParams = lib.mkAfter [
    "cma=256M"  # Contiguous memory allocator for GPU
  ];
}
