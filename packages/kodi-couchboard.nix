# Kodi screensaver that shows the couchboard render from prometheus
# (homelab/couchboard: clock, weather, TV, family calendar).
{ lib, buildKodiAddon }:

buildKodiAddon {
  pname = "couchboard";
  namespace = "screensaver.couchboard";
  version = "1.1.0";
  src = ./screensaver.couchboard;

  meta = {
    description = "Kodi screensaver showing the couchboard family board";
    platforms = lib.platforms.all;
  };
}
