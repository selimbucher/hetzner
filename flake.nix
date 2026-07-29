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
    # The Cherryblossom product (engine/api/web-backend/frontend). Pinned like any
    # other input — bumping this pin + `nixos-rebuild switch` IS how a code change
    # ships; there is no separate deploy.sh anymore. Fast local iteration against
    # uncommitted changes: `--override-input life-system path:/home/selim/life-system`.
    life-system = {
      url = "git+ssh://git@github.com/selimbucher/life-system.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # rclone WebDAV cloud drive at drive.selim.one (local-disk backend).
    cloud-drive = {
      url = "git+ssh://git@github.com/selimbucher/cloud-drive.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, civ6, mailserver, nix-minecraft, life-system, cloud-drive, ... }@inputs: {
    nixosConfigurations.hetzner = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        disko.nixosModules.disko
        civ6.nixosModules.default
        mailserver.nixosModules.default
        nix-minecraft.nixosModules.minecraft-servers
        cloud-drive.nixosModules.default
        { nixpkgs.overlays = [ nix-minecraft.overlays.default ]; }
        ./configuration.nix
        ./minecraft.nix
      ];
    };
  };
}