# music-sync — Apple Music <-> Spotify mirror (2026-09-23): playlists, liked
# songs, saved albums, favourites (star), deletions both ways. Runs every 15 min;
# the first run is `sudo music-sync-admin seed` by hand (merges both libraries).
# Apple's media-user-token dies ~6-monthly; the service mails when it does.
# Secrets: /etc/secrets/music-sync/* from hetzner-secrets (see secrets.nix).
{ ... }:
{
  services.music-sync = {
    enable = true;
    appleUserTokenFile      = "/etc/secrets/music-sync/apple-user-token";
    spotifyClientIdFile     = "/etc/secrets/music-sync/spotify-client-id";
    spotifyClientSecretFile = "/etc/secrets/music-sync/spotify-client-secret";
    # rewritten by the service if Spotify rotates it, hence the state dir
    spotifyRefreshTokenFile = "/var/lib/music-sync/spotify-refresh-token";
    # Apple's starred songs <-> this Spotify playlist, both ways
    spotifyFavoritesPlaylist = "Lieblingstitel";
    # off: starring an album on Apple adds all its tracks to the library (= Liked Songs)
    syncAlbums = false;
    notifyEmail = "me@selim.one";
    notifyFrom = "music-sync@selim.one";
    after = [ "hetzner-secrets.service" ];
  };
}
