{
  description = "NixNAS - Self-hosted NixOS-based Network Attached Storage";

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
    in
    {
      nixosConfigurations.nixnas = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          # Disk partitioning (optional, for fresh installs)
          disko.nixosModules.disko

          # Secrets management
          sops-nix.nixosModules.sops

          # Custom overlays
          ({ config, pkgs, ... }: {
            nixpkgs.overlays = [ overlay-unstable ];
          })

          # Host configuration
          ./hosts/nixnas

          # All custom modules
          ./modules
        ];
      };

      # Development shell for working on the configuration
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
