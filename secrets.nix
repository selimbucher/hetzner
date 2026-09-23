{ pkgs, ... }:

{
  # GitHub's SSH host key — verified against https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
  programs.ssh.knownHosts."github.com" = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
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
      "dovecot.service"
      "caddy.service"
      "dmarc-report-converter.service"
      "cloud-drive.service"
      "mail-logos.service"
      "music-sync.service"
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
      install -Dm600 "$REPO/caddy.env"                        /etc/secrets/caddy.env
      install -Dm600 "$REPO/mailserver/password-me"           /etc/mailserver/password-me
      install -Dm600 "$REPO/mailserver/password-noreply-civ6" /etc/mailserver/password-noreply-civ6
      install -Dm600 "$REPO/mailserver/password-dmarc"        /etc/mailserver/password-dmarc
      install -Dm600 "$REPO/mailserver/dmarc-imap-password"   /etc/mailserver/dmarc-imap-password
      install -Dm600 "$REPO/drive-htpasswd"                   /etc/secrets/drive-htpasswd
      install -Dm600 "$REPO/mail-logos-token"                 /etc/secrets/mail-logos-token
      # music-sync: guarded so a rebuild before the files exist changes nothing.
      if [ -d "$REPO/music-sync" ]; then
        install -Dm600 "$REPO/music-sync/apple-user-token"      /etc/secrets/music-sync/apple-user-token
        install -Dm600 "$REPO/music-sync/spotify-client-id"     /etc/secrets/music-sync/spotify-client-id
        install -Dm600 "$REPO/music-sync/spotify-client-secret" /etc/secrets/music-sync/spotify-client-secret
        # the service rewrites this one on rotation: never overwrite a live copy
        [ -e /var/lib/music-sync/spotify-refresh-token ] || \
          install -Dm600 -o music-sync -g music-sync "$REPO/music-sync/spotify-refresh-token" /var/lib/music-sync/spotify-refresh-token
      fi
    '';
  };
}
