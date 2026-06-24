{ nvim-config, ... }:
{
  home.username = "arcadia";
  home.homeDirectory = "/home/arcadia";

  xdg.configFile."nvim" = {
    source = nvim-config;
    recursive = true;
  };

  # Remote control of prometheus's on-demand game-stream host (Sunshine/Moonlight).
  #   game-on  -> pauses prometheus's AI/Docker stacks + starts the virtual display + Sunshine
  #   game-off -> tears it down and resumes them
  # Requires an SSH key for slava@prometheus (manual, on arcadia: `ssh-copy-id slava@192.168.1.42`).
  programs.bash.enable = true;
  home.shellAliases = {
    game-on  = "ssh slava@192.168.1.42 /home/slava/Documents/projects/dotfiles/game-stream/stream-up.sh";
    game-off = "ssh slava@192.168.1.42 /home/slava/Documents/projects/dotfiles/game-stream/stream-down.sh";
  };

  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
}
