{
  description = "Arcadia NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nvim-config = {
      url = "github:greenmushrooms/nvim-config";
      flake = false;
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, nvim-config, ... }: {
    nixosConfigurations.arcadia = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit nvim-config; };
      modules = [
        ./configuration.nix
        {
          nixpkgs.overlays = [
            (final: prev: let
              # Separate import: legacyPackages ignores allowUnfree, and claude-code is unfree.
              pkgsUnstable = import nixpkgs-unstable {
                system = prev.stdenv.hostPlatform.system;
                config.allowUnfree = true;
              };
            in {
              # Both track upstream within days on unstable; stable lags (26.05 ships
              # claude-code 2.1.223), and GitHub rejects runners a few releases old.
              claude-code = pkgsUnstable.claude-code;
              github-runner = pkgsUnstable.github-runner;
            })
          ];
        }
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit nvim-config; };
          home-manager.users.arcadia = import ./home.nix;
        }
      ];
    };
  };
}
