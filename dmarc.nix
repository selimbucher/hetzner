{ config, lib, pkgs, ... }:

# Self-hosted DMARC aggregate-report viewer.
#
# Reports are delivered to a dedicated dmarc@selim.one mailbox (see the DNS
# rua= tag) and never touch the main inbox. A daily timer runs
# dmarc-report-converter, which reads the whole mailbox over IMAP and rebuilds
# a single self-contained HTML page. Caddy serves it behind basic auth.

let
  stateDir = "/var/lib/dmarc-report-converter";
  htmlDir  = "${stateDir}/html";
  tmpDir   = "${stateDir}/tmp";

  # Password placeholder is substituted at runtime from a systemd credential so
  # the plaintext never lands in the world-readable Nix store.
  baseConfig = pkgs.writeText "dmarc-report-converter.yaml" ''
    input:
      delete: no
      dir: "${tmpDir}"
      imap:
        server: "mail.selim.one:993"
        username: "dmarc@selim.one"
        password: "@IMAP_PASSWORD@"
        mailbox: "INBOX"
        delete: no
        security: "tls"

    output:
      file: "${htmlDir}/index.html"
      format: "html_static"

    lookup_addr: yes
    merge_reports: yes
    log_datetime: yes
  '';

  # Shown until the first reports arrive (the converter overwrites index.html
  # once the mailbox has reports). Keeps the dashboard from 404ing when empty.
  placeholder = pkgs.writeText "dmarc-placeholder.html" ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>DMARC reports — selim.one</title>
    <style>
      body{font-family:system-ui,sans-serif;max-width:40rem;margin:4rem auto;padding:0 1rem;color:#222;line-height:1.5}
      h1{font-size:1.4rem} code{background:#f2f2f2;padding:.1rem .3rem;border-radius:3px}
      .muted{color:#666}
    </style>
    </head>
    <body>
    <h1>DMARC report viewer</h1>
    <p>No reports yet. Aggregate reports are sent by receiving mail servers
    (Gmail, Outlook, &hellip;) to <code>dmarc@selim.one</code> and are usually
    delivered <strong>once per day</strong>.</p>
    <p class="muted">This page rebuilds daily from the mailbox. Check back in a
    day or two and the first reports will appear here.</p>
    </body>
    </html>
  '';
in
{
  # Receive-only mailbox for the reports. Generate the hash on the server with:
  #   nix-shell -p mkpasswd --run 'mkpasswd -s -m bcrypt' > /etc/mailserver/password-dmarc
  # and put the SAME plaintext in /etc/mailserver/dmarc-imap-password.
  mailserver.accounts."dmarc@selim.one" = {
    hashedPasswordFile = "/etc/mailserver/password-dmarc";
  };

  users.users.dmarc = { isSystemUser = true; group = "dmarc"; };
  users.groups.dmarc = { };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 dmarc dmarc -"
    "d ${htmlDir}  0755 dmarc dmarc -"
    "d ${tmpDir}   0700 dmarc dmarc -"
    # Seed a placeholder only if no report has been generated yet (C skips
    # existing targets, so a real index.html is never clobbered).
    "C ${htmlDir}/index.html 0644 dmarc dmarc - ${placeholder}"
  ];

  systemd.services.dmarc-report-converter = {
    description = "Convert DMARC aggregate reports to a static HTML page";
    after = [ "network-online.target" "dovecot.service" "hetzner-secrets.service" ];
    wants = [ "network-online.target" ];
    requires = [ "hetzner-secrets.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "dmarc";
      Group = "dmarc";
      RuntimeDirectory = "dmarc-report-converter";
      RuntimeDirectoryMode = "0700";
      # Plaintext IMAP password, fetched by hetzner-secrets.service.
      LoadCredential = "imap-password:/etc/mailserver/dmarc-imap-password";
    };
    script = ''
      conf="$RUNTIME_DIRECTORY/config.yaml"
      ${pkgs.gnused}/bin/sed \
        "s|@IMAP_PASSWORD@|$(cat "$CREDENTIALS_DIRECTORY/imap-password")|" \
        ${baseConfig} > "$conf"
      out=$(${pkgs.dmarc-report-converter}/bin/dmarc-report-converter -config "$conf" 2>&1) && rc=0 || rc=$?
      printf '%s\n' "$out"
      # An empty mailbox (no reports yet) is not a real failure.
      if [ "''${rc:-0}" -ne 0 ] && printf '%s' "$out" | grep -q "no messages found in mailbox"; then
        echo "no reports in mailbox yet; nothing to do"
        exit 0
      fi
      exit "''${rc:-0}"
    '';
  };

  systemd.timers.dmarc-report-converter = {
    description = "Daily DMARC report conversion";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # Serve the report behind basic auth. The bcrypt hash comes from caddy.env
  # (DMARC_BASICAUTH_HASH=...), generated with `caddy hash-password`.
  services.caddy.environmentFile = "/etc/secrets/caddy.env";
  services.caddy.virtualHosts."dmarc.selim.one".extraConfig = ''
    basic_auth {
      selim {$DMARC_BASICAUTH_HASH}
    }
    root * ${htmlDir}
    file_server
  '';
}
