{ pkgs, ... }:

{
  # GitHub's SSH host key — verified against https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
  programs.ssh.knownHosts."github.com" = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C8okWNkh7M7bJE";
  };

  # Fetch secrets from private repo using the server's SSH host key.
  # Add /etc/ssh/ssh_host_ed25519_key.pub as a read-only deploy key on the repo.
  systemd.services.hetzner-secrets = {
    description = "Fetch secrets from private GitHub repository";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    before = [
      "acme-order-renew-mail.selim.one.service"
      "postfix.service"
      "dovecot2.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    environment = {
      GIT_SSH_COMMAND = "ssh -i /etc/ssh/ssh_host_ed25519_key -o StrictHostKeyChecking=yes";
    };
    path = with pkgs; [ git openssh ];
    script = ''
      REPO=/var/lib/hetzner-secrets
      if [ -d "$REPO/.git" ]; then
        git -C "$REPO" fetch --quiet origin
        git -C "$REPO" reset --hard origin/main
      else
        git clone git@github.com:selimbucher/hetzner-secrets.git "$REPO"
      fi
      chmod 700 "$REPO"
      install -Dm600 "$REPO/cloudflare-acme.env"              /etc/secrets/cloudflare-acme.env
      install -Dm600 "$REPO/mailserver/password-selim"        /etc/mailserver/password-selim
      install -Dm600 "$REPO/mailserver/password-noreply-civ6" /etc/mailserver/password-noreply-civ6
    '';
  };
}
