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
