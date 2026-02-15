{
  description = "Arcadia NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nvim-config = {
      url = "github:greenmushrooms/nvim-config";
      flake = false;
    };
  };

  outputs = { nixpkgs, home-manager, nvim-config, ... }: {
    nixosConfigurations.arcadia = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit nvim-config; };
      modules = [
        ./configuration.nix
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
