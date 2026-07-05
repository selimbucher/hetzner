# Firefly III — self-hosted money ledger (PRODUCT/finance route 2026-07-05:
# Firefly as the money store; feeds come later via the data importer —
# GoCardless/SaltEdge for EEA accounts, camt.053/CSV for BEKB).
# Served by Caddy (php-fpm pool) at money.selim.one — the module's nginx stays off.
{ config, pkgs, ... }:
{
  services.firefly-iii = {
    enable = true;
    settings = {
      APP_ENV = "production";
      APP_KEY_FILE = "/var/lib/firefly-iii/app-key";
      APP_URL = "https://money.selim.one";
      TZ = "Europe/Zurich";
      TRUSTED_PROXIES = "127.0.0.1";
      DB_CONNECTION = "sqlite";
    };
  };

  services.caddy.virtualHosts."money.selim.one".extraConfig = ''
    log {
      output file /var/log/caddy/access-money.selim.one.log
    }
    root * ${config.services.firefly-iii.package}/public
    php_fastcgi unix/${config.services.phpfpm.pools.firefly-iii.socket} {
      resolve_root_symlink
    }
    file_server
  '';

  # Caddy must be able to reach the pool socket
  services.phpfpm.pools.firefly-iii.settings."listen.acl_users" =
    pkgs.lib.mkForce "caddy,firefly-iii";
}
