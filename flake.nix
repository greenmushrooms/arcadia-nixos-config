{
  description = "Arcadia NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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
              pkgsUnstable = nixpkgs-unstable.legacyPackages.${prev.system};
              # Separate import: legacyPackages ignores allowUnfree, and claude-code is unfree.
              pkgsUnstableUnfree = import nixpkgs-unstable {
                system = prev.stdenv.hostPlatform.system;
                config.allowUnfree = true;
              };
            in {
              # nixpkgs tracks the native-binary release within days; the old npm
              # derivation broke once the tarball stopped shipping cli.js.
              claude-code = pkgsUnstableUnfree.claude-code;
              github-runner = pkgsUnstable.github-runner.override {
                nodejs_20 = pkgsUnstable.nodejs_24;
              };
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
