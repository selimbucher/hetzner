{ pkgs, ... }:

let
  wakeupScript = pkgs.writeScriptBin "mc-wakeup" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./mc-wakeup.py}
  '';

  idleStopScript = pkgs.writeScriptBin "mc-idle-stop" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./mc-idle-stop.py}
  '';
in

{
  services.minecraft-servers = {
    enable = true;
    eula = true;

    servers.paper = {
      enable = true;
      package = pkgs.minecraftServers."paper-26_2-build_34";
      jvmOpts = "-Xms512M -Xmx2G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200";

      serverProperties = {
        server-port    = 25566;
        gamemode       = "survival";
        difficulty     = "normal";
        max-players    = 20;
        motd           = "selim.one";
        online-mode    = true;
        white-list     = false;
        enable-rcon    = true;
        "rcon.port"    = 25575;
        "rcon.password" = "mc-rcon-local";
      };
    };
  };

  # Wakeup proxy: listens publicly on 25565, proxies to Paper on 25566.
  # When Paper is sleeping: shows MOTD and starts it on login.
  systemd.services.mc-wakeup = {
    description = "Minecraft wakeup proxy";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${wakeupScript}/bin/mc-wakeup";
      Restart    = "always";
      RestartSec = "2s";
      # Hardening: this is the one custom root service on a public port (parses
      # untrusted Minecraft packets), and it shares the box with sensitive life-system
      # data under /root. ProtectHome=true makes /root + /home invisible to it, so even
      # a proxy RCE cannot read /root/life-data. It only needs network + `systemctl
      # start` (talks to /run/systemd), so these don't break it.
      ProtectHome           = true;
      NoNewPrivileges       = true;
      PrivateTmp            = true;
      ProtectKernelTunables = true;
      ProtectKernelModules  = true;
      ProtectControlGroups  = true;
      RestrictSUIDSGID      = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
  };

  # Idle-stop: check every 5 min via RCON, stop Paper after 15 min with 0 players.
  systemd.services.mc-idle-stop = {
    description = "Stop Paper when idle";
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = "${idleStopScript}/bin/mc-idle-stop";
    };
  };

  systemd.timers.mc-idle-stop = {
    description = "Periodically check if Paper is idle";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnBootSec       = "5min";
      OnUnitActiveSec = "5min";
    };
  };

  networking.firewall.allowedTCPPorts = [ 25565 ];
  networking.firewall.allowedUDPPorts = [ 25565 ];
}
