{ modulesPath, ... }: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk.nix
    ./hetzner.nix
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking.hostName = "hetzner";

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
    settings.PasswordAuthentication = false;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEJ7wMSOe25u6BauXYT8xPjvrbWrJ6wVskOU0r/u8WsQ selim@laptop"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2hjST+3bGWZhN7UOZshtJRFEr2hRHUUUh69W8tnana selim@desktop"
  ];

  system.stateVersion = "25.05";
}





