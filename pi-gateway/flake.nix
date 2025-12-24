{
  description = "NixOS Pi Gateway - WireGuard bridge for family network";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    # Raspberry Pi support
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }@inputs:
    let
      # Build on x86_64, target aarch64
      buildSystem = "x86_64-linux";
      targetSystem = "aarch64-linux";

      # Cross-compilation overlay
      pkgsCross = import nixpkgs {
        system = buildSystem;
        crossSystem = {
          config = "aarch64-unknown-linux-gnu";
          system = targetSystem;
        };
      };

      # Native aarch64 packages (for when building on aarch64 or with binfmt)
      pkgsNative = import nixpkgs {
        system = targetSystem;
      };

    in {
      # NixOS configuration for the Pi Gateway
      nixosConfigurations.pi-gateway = nixpkgs.lib.nixosSystem {
        system = targetSystem;

        modules = [
          # Hardware support (use Pi 3 as base, compatible with Zero 2W)
          nixos-hardware.nixosModules.raspberry-pi-4

          # Our modules
          ./configuration.nix
          ./modules/hardware.nix
          ./modules/wireguard-client.nix
          ./modules/network-bridge.nix

          # SD card image builder
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"

          # Configuration for SD image
          ({ config, lib, pkgs, ... }: {
            # Compress the image
            sdImage.compressImage = true;

            # Include firmware for Pi
            sdImage.populateFirmwareCommands = ''
              ${config.system.build.installBootLoader} ${config.system.build.toplevel} -d ./firmware
            '';

            # Ensure the image is named nicely
            sdImage.imageBaseName = "pi-gateway";
          })
        ];

        specialArgs = { inherit inputs; };
      };

      # Packages for building
      packages.${buildSystem} = {
        # Build SD image with: nix build .#sdImage
        sdImage = self.nixosConfigurations.pi-gateway.config.system.build.sdImage;

        default = self.packages.${buildSystem}.sdImage;
      };

      # Also expose for native aarch64 builds
      packages.${targetSystem} = {
        sdImage = self.nixosConfigurations.pi-gateway.config.system.build.sdImage;
        default = self.packages.${targetSystem}.sdImage;
      };
    };
}
