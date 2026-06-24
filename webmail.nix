{ pkgs, lib, ... }:

let
  customCss = pkgs.writeText "roundcube-custom.css" (builtins.readFile ./webmail.css);
in
{
  services.roundcube = {
    enable = true;
    hostName = "mail.selim.one";
    extraConfig = ''
      $config['default_host'] = 'ssl://mail.selim.one';
      $config['default_port'] = 993;
      $config['smtp_server'] = 'ssl://mail.selim.one';
      $config['smtp_port'] = 465;
      $config['smtp_user'] = '%u';
      $config['smtp_pass'] = '%p';
      $config['product_name'] = 'Selim Mail';
      $config['custom_stylesheet'] = '/custom.css';
    '';
  };

  # Restrict nginx to localhost — Caddy handles public HTTPS
  services.nginx.defaultListenAddresses = [ "127.0.0.1" ];
  services.nginx.virtualHosts."mail.selim.one".listen = [
    { addr = "127.0.0.1"; port = 8080; ssl = false; }
  ];
  services.nginx.virtualHosts."mail.selim.one".locations."/custom.css" = {
    alias = toString customCss;
  };

  # Caddy proxies mail.selim.one → nginx on localhost
  services.caddy.virtualHosts."mail.selim.one".extraConfig = ''
    reverse_proxy 127.0.0.1:8080
  '';
}
