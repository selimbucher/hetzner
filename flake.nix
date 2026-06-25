{
  description = "Hetzner server NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    civ6 = {
      url = "github:selimbucher/civ6.ch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mailserver = {
      url = "github:selimbucher/mailserver";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, civ6, mailserver, nix-minecraft, ... }@inputs: {
    nixosConfigurations.hetzner = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        disko.nixosModules.disko
        civ6.nixosModules.default
        mailserver.nixosModules.default
        nix-minecraft.nixosModules.minecraft-servers
        { nixpkgs.overlays = [ nix-minecraft.overlays.default ]; }
        ./configuration.nix
        ./minecraft.nix
      ];
    };
  };
}