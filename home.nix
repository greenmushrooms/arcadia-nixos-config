{ nvim-config, ... }:
{
  home.username = "arcadia";
  home.homeDirectory = "/home/arcadia";

  xdg.configFile."nvim" = {
    source = nvim-config;
    recursive = true;
  };

  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
}
