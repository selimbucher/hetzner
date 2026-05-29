{ ... }: {
  services.caddy = {
    enable = true;
    virtualHosts."deckel-zue.org" = {
      extraConfig = ''
        respond "hello from deckel-zue.org"
      '';
    };
    virtualHosts."www.deckel-zue.org" = {
      extraConfig = ''
        redir https://deckel-zue.org{uri} permanent
      '';
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
  };
}