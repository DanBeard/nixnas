{
  description = "NixNAS - Homelab NixOS configuration with OpenMediaVault NAS storage";

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

    # Secrets management - uncomment after running setup-sops.sh (Phase 2)
    # sops-nix = {
    #   url = "github:Mic92/sops-nix";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, disko, ... }@inputs:
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

      # Note: sops-nix is disabled by default for initial install
      # Run setup-sops.sh after first boot to enable encrypted secrets
    in
    {
      # =============================================================================
      # HOST CONFIGURATIONS
      # =============================================================================

      nixosConfigurations = {
        # -------------------------------------------------------------------------
        # homelab: Full-featured server with all services
        # Requires: 4GB+ RAM, decent CPU
        # Provides: Jellyfin, Home Assistant, Docker, Nextcloud, WireGuard, etc.
        # Uses NFS to mount storage from OpenMediaVault NAS
        #
        # To enable SOPS secrets (after running setup-sops.sh):
        #   Add sops-nix.nixosModules.sops to modules list below
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
