{ nvim-config, pkgs, ... }:
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

  # One-shot couch launcher: powers prometheus's game-stream up, opens Moonlight,
  # then tears it back down to AI/server mode on exit (the EXIT trap also covers a
  # Moonlight crash). Point a desktop tile at `game` for true one-click.
  home.packages = [
    (pkgs.writeShellScriptBin "game" ''
      PROM=192.168.1.42
      SG=/home/slava/Documents/projects/dotfiles/game-stream
      teardown() { echo "→ tearing down game-stream…"; ${pkgs.openssh}/bin/ssh slava@$PROM "$SG/stream-down.sh" || true; }
      trap teardown EXIT

      echo "→ starting game-stream on prometheus…"
      ${pkgs.openssh}/bin/ssh slava@$PROM "$SG/stream-up.sh"

      echo "→ waiting for Sunshine to come up…"
      for _ in $(seq 1 40); do
        ${pkgs.bash}/bin/bash -c "</dev/tcp/$PROM/47989" 2>/dev/null && break
        sleep 0.5
      done

      moonlight
    '')
  ];

  home.stateVersion = "25.11";
  programs.home-manager.enable = true;
}
