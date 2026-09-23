{ modulesPath, ... }: {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk.nix
    ./secrets.nix
    ./dmarc.nix
    # Cherryblossom, off for now: its frontend check needs playwright-driver.browsers,
    # whose WebKit fails to build on nixpkgs 2026-09-16 (libmanette missing).
    # ./life.nix
    ./firefly.nix
    ./music.nix
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking.hostName = "hetzner";
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
  };

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;  # close the last password-style path
  };

  # Ban repeat SSH brute-forcers (thousands of failed attempts seen). Keys can't be
  # brute-forced, but this cuts log noise + attack surface. Never bans an established
  # session, so it cannot lock out the current connection.
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    ignoreIP = [ "127.0.0.0/8" "::1" ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEJ7wMSOe25u6BauXYT8xPjvrbWrJ6wVskOU0r/u8WsQ selim@laptop"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK2hjST+3bGWZhN7UOZshtJRFEr2hRHUUUh69W8tnana selim@desktop"
  ];

  services.caddy.enable = true;
  services.civ6.enable = true;
  services.cloud-drive.enable = true;
  services.mail-logos = {
    enable = true;
    # only /<token>/<domain> is served; the token comes from hetzner-secrets
    tokenFile = "/etc/secrets/mail-logos-token";
  };

  system.stateVersion = "25.05";
}