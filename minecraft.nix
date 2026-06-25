{ pkgs, ... }:

{
  services.minecraft-servers = {
    enable = true;
    eula = true;

    servers.paper = {
      enable = true;
      package = pkgs.minecraftServers."paper-26_2-build_34";

      jvmOpts = "-Xms1G -Xmx4G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200";

      serverProperties = {
        server-port = 25565;
        gamemode = "survival";
        difficulty = "normal";
        max-players = 20;
        motd = "selim.one";
        online-mode = true;
        white-list = false;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 25565 ];
  networking.firewall.allowedUDPPorts = [ 25565 ];
}
