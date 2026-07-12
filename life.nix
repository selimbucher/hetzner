{ lib, pkgs, inputs, ... }:
let
  # The product's code comes from the life-system flake input, not a rsync-deployed
  # checkout — a pinned, content-addressed store path (2026-07-10: retired the
  # rsync + deploy.sh model entirely; bumping this input's lock + `nixos-rebuild
  # switch` IS the deploy now). `src` is the input's own source tree; `engineEnv`/
  # `apiEnv` are the Python environments life-system's own flake declares its code
  # needs, so this file doesn't have to reconstruct them.
  cb = inputs.life-system;
  src = "${cb}/src";
  py = "${cb.packages.${pkgs.system}.engineEnv}/bin/python3";
  eng = "${src}/engine";
  envCommon = {
    HOME = "/root"; # claude CLI reads ~/.claude
    LIFE_CLAUDE_BIN = "${pkgs.claude-code}/bin/claude";
    LIFE_V2_DATA = "/root/life-data-v2";
    LIFE_V1_FEEDS = "/root/life-data";
  };

  # The engine's heartbeat (DESIGN §4 cadences). Costs are subscription-quota, not
  # dollars: absorb is a free no-op unless web answers are pending; ingest ≈ $0.04;
  # prepare ≈ $0.30 only while events sit in their lead windows; stress/touchpoint
  # weekly. Plan mode is deliberately NOT on a timer — re-planning is a human-in-
  # the-loop event.
  loops = {
    absorb = {
      cal = "*-*-* *:07:00";
      desc = "consume web answers/tells, then respond to open episodes";
      cmds = [
        "${py} ${eng}/absorb.py --mode real"
        # user-initiated requests; zero model calls when nothing is open
        "${py} ${eng}/episode.py --mode real"
        # user-started heavy decision analysis; one stage per run, idle = free
        "${py} ${eng}/decision.py --mode real"
      ];
    };
    apply = {
      cal = "*-*-* *:12:00";
      desc = "apply CONFIRMED proposals to Todoist (propose->confirm->apply, R6)";
      cmds = [
        "${py} ${eng}/organize.py --mode real --apply"
        "${py} ${eng}/prepare.py --mode real --apply"
      ];
    };
    ingest = {
      # every 3h, not daily: the v1 mail sync (root's systemd --user) is HOURLY, and
      # urgent mail must ping the phone within hours, not tomorrow morning. Classify
      # only runs when there are new deltas, so idle runs cost $0.
      cal = "*-*-* 00/3:25:00";
      desc = "feed liveness, mail/calendar deltas, anomaly signals, urgent pushes";
      cmds = [ "${py} ${eng}/ingest.py --mode real" ];
    };
    prepare = {
      cal = "*-*-* 07:45:00";
      desc = "event readiness within lead windows (exams months, dates days)";
      cmds = [ "${py} ${eng}/prepare.py --mode real" ];
    };
    organize = {
      cal = "Sun *-*-* 18:00:00";
      desc = "reconcile committed plans against Todoist";
      cmds = [ "${py} ${eng}/organize.py --mode real" ];
    };
    stress = {
      cal = "Wed *-*-* 12:30:00";
      desc = "stress-test audit, one domain by rotation";
      cmds = [ "${py} ${eng}/stress.py --mode real" ];
    };
    touchpoint = {
      cal = "Sat *-*-* 09:00:00";
      desc = "weekly touchpoint email (backfills one unknown when queue is light)";
      cmds = [ "${py} ${eng}/touchpoint.py --mode real" ];
    };
    selftest = {
      # regression heartbeat ("make sure it doesn't get worse"): both suites run on
      # the box weekly, before the touchpoint; a red suite = failed unit, visible in
      # `systemctl --failed`. Zero model cost — the engine suite uses fakes.
      cal = "Sat *-*-* 08:30:00";
      desc = "run engine + web test suites against the deployed tree";
      cmds = [
        "${py} ${eng}/test_loops.py"
        "${py} ${src}/web/test_app.py"
      ];
    };
  };

  loopServices = lib.mapAttrs' (name: l:
    lib.nameValuePair "life-${name}" {
      description = "Life engine — ${name}: ${l.desc}";
      environment = envCommon;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = l.cmds;
      };
    }) loops;

  loopTimers = lib.mapAttrs' (name: l:
    lib.nameValuePair "life-${name}" {
      description = "Life engine timer — ${name}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = l.cal;
        Persistent = true; # box reboots must not eat a cycle
        RandomizedDelaySec = 120;
      };
    }) loops;
in
{
  # claude-code is unfree; life-web/loops/cherryblossom-api all shell out to it
  # (LIFE_CLAUDE_BIN above).
  nixpkgs.config.allowUnfree = true;

  # The engine's schedule speaks SELIM's clock, not UTC — found 2026-07-03 when the
  # "Sat 09:00" touchpoint would have fired at 11:01 his time. Affects all timers and
  # log timestamps box-wide (mail/caddy logs shift too; nothing depends on UTC).
  time.timeZone = "Europe/Zurich";

  # Life System: /ingest/* stays on the v1 health-ingest service (:8787, bearer-token
  # auth — devices can't send basic-auth); everything else goes to the web touchpoint
  # (:8788, app-level auth; /cv is deliberately public). TLS via Caddy's automatic
  # HTTP-01 (port 80 is open); DNS record life.selim.one already exists.

  # Cherryblossom portal — the product frontend, served directly from the
  # life-system flake input's built `frontend` package (a Nix store path, not an
  # rsynced /var/www copy) — sharing an origin with /api/* (cookie samesite).
  services.caddy.virtualHosts."app.selim.one".extraConfig = ''
    log {
      output file /var/log/caddy/access-app.selim.one.log
    }
    handle /ingest/* {
      # v1 telemetry (iOS Health Auto Export, activitywatch) — moved here from the
      # life.selim.one vhost so devices can repoint before that vhost retires;
      # both routes stay live during the transition.
      reverse_proxy 127.0.0.1:8787
    }
    handle /api/* {
      reverse_proxy 127.0.0.1:8790
    }
    handle {
      root * ${cb.packages.${pkgs.system}.frontend}
      @assets path /_app/*
      header @assets Cache-Control "public, max-age=31536000, immutable"
      @pages not path /_app/*
      header @pages Cache-Control "no-cache"
      try_files {path} /index.html
      file_server
    }
  '';

  services.caddy.virtualHosts."life.selim.one".extraConfig = ''
    log {
      output file /var/log/caddy/access-life.selim.one.log
    }
    handle /ingest/* {
      reverse_proxy 127.0.0.1:8787
    }
    handle /api/* {
      reverse_proxy 127.0.0.1:8790
    }
    handle {
      reverse_proxy 127.0.0.1:8788
    }
  '';

  # Product code is built by the life-system flake input (see `cb`/`src`/`py`
  # above) — a pinned, reproducible store path, not an rsynced checkout. Secrets
  # and data deliberately stay OUTSIDE the store, at fixed absolute paths on the
  # box (runtime/secrets/*.env, life-data*, life-users) — the flake input packages
  # code only, never touches those.
  systemd.services = loopServices // {
    cherryblossom-api = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      description = "Cherryblossom API — product surface over the life engine";
      environment = {
        LIFE_V2_DATA = "/root/life-data-v2";
        LIFE_API_USERS_DIR = "/root/life-users";
        LIFE_API_DB = "/root/life-users/api.db";
        LIFE_API_BASE_URL = "https://app.selim.one";
        LIFE_MAIL_ENV = "/root/life-system/runtime/secrets/mail.env";
        # the phone widget's Basic-auth creds — same file the retired personal
        # surface used, so the Scriptable script only changed its URL
        LIFE_API_WIDGET_BASIC_ENV = "/root/life-system/runtime/secrets/web.env";
        LIFE_API_SELIM_EMAIL = "me@selim.one";
        LIFE_API_KICK = "1";
        LIFE_CLAUDE_BIN = "${pkgs.claude-code}/bin/claude";
        HOME = "/root";
        PYTHONPATH = src;
      };
      serviceConfig = {
        ExecStart = "${cb.packages.${pkgs.system}.apiEnv}/bin/uvicorn api.main:app --host 127.0.0.1 --port 8790";
        WorkingDirectory = src;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
    life-web = {
      description = "Life System — web touchpoint backend for life.selim.one (127.0.0.1:8788)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        LIFE_V2_DATA = "/root/life-data-v2";
        LIFE_V1_FEEDS = "/root/life-data";
        LIFE_WEB_ENV = "/root/life-system/runtime/secrets/web.env";
        LIFE_WEB_PORT = "8788";
        # the walkthrough feature calls the model synchronously (plan/unblock)
        HOME = "/root";
        LIFE_CLAUDE_BIN = "${pkgs.claude-code}/bin/claude";
        # typed calendar actions from coach/chat shell out to the caldav env
        LIFE_SYSTEM_SECRETS = "/root/life-system/runtime/secrets/icloud.env";
      };
      serviceConfig = {
        ExecStart = "${py} ${src}/web/app.py";
        Restart = "always";
        RestartSec = 5;
        # parses untrusted network input as root (code+secrets live under /root, so a
        # full user-split is backlog) — cheap blast-radius limits meanwhile:
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RestrictRealtime = true;
      };
    };
  };

  systemd.timers = loopTimers;

}
