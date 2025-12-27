{
  description = "NixNAS - Multi-host NixOS configurations for home infrastructure";

  inputs = {
    # NixOS 24.11 stable
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    # Unstable for latest packages when needed
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, sops-nix, ... }@inputs:
    let
      system = "x86_64-linux";

      # Overlay to access unstable packages when needed
      overlay-unstable = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ overlay-unstable ];
      };

      # Base modules for all hosts (no sops)
      baseModules = [
        disko.nixosModules.disko
        ({ config, pkgs, ... }: {
          nixpkgs.overlays = [ overlay-unstable ];
        })
        ./modules
      ];

      # Modules with sops enabled (add sops-nix.nixosModules.sops when secrets are configured)
      # For now, homelab doesn't use sops until secrets.yaml is created
    in
    {
      # =============================================================================
      # HOST CONFIGURATIONS
      # =============================================================================

      nixosConfigurations = {
        # -------------------------------------------------------------------------
        # storage-node: Minimal NAS for memory-constrained hardware (QNAP, 1GB RAM)
        # Only provides: ZFS storage, Samba/NFS file sharing, SSH
        # -------------------------------------------------------------------------
        storage-node = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = baseModules ++ [
            ./hosts/storage-node
          ];
        };

        # -------------------------------------------------------------------------
        # homelab: Full-featured server with all services
        # Requires: 4GB+ RAM, decent CPU
        # Provides: Jellyfin, Home Assistant, Docker, Nextcloud, WireGuard, etc.
        # NOTE: Add sops-nix.nixosModules.sops to modules list after configuring secrets
        # -------------------------------------------------------------------------
        homelab = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = baseModules ++ [
            ./hosts/homelab
          ];
        };
      };

      # =============================================================================
      # DEVELOPMENT SHELL
      # =============================================================================

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixpkgs-fmt    # Nix formatter
          nil            # Nix LSP
          sops           # Secrets editor
          age            # Encryption
          ssh-to-age     # Convert SSH keys to age
        ];
      };
    };
}
