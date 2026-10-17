{ config, pkgs, ... }:
let
  # Native Wayland build: the X11 one ran under XWayland in Plasma and lagged on
  # the N100. It still carries the X11 backend for the standalone Kodi session.
  kodiEnv = pkgs.kodi-wayland.withPackages (kodiPkgs: with kodiPkgs; [
    # 26.05 ships 0.9.1; 1.0 dropped the deprecated auth Jellyfin 12 rejects.
    # Drop this override once stable carries >= 1.0.
    (jellycon.overrideAttrs (old: {
      version = "1.0.2";
      src = old.src.override {
        rev = "v1.0.2";
        sha256 = "sha256-dpH611GZ+BG63bSFypcZ9VUtNCA/tL8zgKuaU7cCRII=";
      };
      # Music menu starts with Jellyfin's Playlists (normally a separate library).
      # Playlists and albums start with "Play all" / "Shuffle" rows; playlists play in order.
      patches = (old.patches or [ ]) ++ [
        ./packages/jellycon-music-playlists.patch
        ./packages/jellycon-play-all.patch
      ];
    }))
    inputstream-adaptive
    inputstream-ffmpegdirect
    (callPackage ./packages/kodi-couchboard.nix { })
    # Music visualization: plain bars (projectM was too busy). Settings in
    # addon_data/visualization.spectrum: no rotation, slow.
    visualization-spectrum
  ]);
  # Kodi's native PipeWire sink loses the HDMI output when the TV is switched on
  # (the sink is re-created) and every later stream fails with "could not create
  # stream" until Kodi restarts. Through pipewire-pulse the stream just follows the
  # new default sink.
  kodiWithPlugins = pkgs.symlinkJoin {
    name = "kodi-with-plugins";
    paths = [ kodiEnv ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for b in kodi kodi-standalone; do
        [ -e $out/bin/$b ] && wrapProgram $out/bin/$b --set KODI_AE_SINK PULSE
      done
    '';
  };

  # Couch-remote launcher chords (keyd, see services.keyd below). keyd runs as root,
  # so each action is bounced into arcadia's graphical session with systemd-run --user.
  couchStart = pkgs.writeShellScript "couch-start" ''
    exec ${pkgs.systemd}/bin/systemd-run --user -M arcadia@.host --collect -q -- \
      ${pkgs.kdePackages.konsole}/bin/konsole -e game
  '';
  couchStop = pkgs.writeShellScript "couch-stop" ''
    exec ${pkgs.systemd}/bin/systemd-run --user -M arcadia@.host --collect -q -- \
      ${pkgs.bash}/bin/bash -c '${pkgs.procps}/bin/pkill -x moonlight; ${pkgs.openssh}/bin/ssh slava@192.168.1.42 /home/slava/Documents/projects/dotfiles/game-stream/stream-down.sh'
  '';
  couchKodi = pkgs.writeShellScript "couch-kodi" ''
    exec ${pkgs.systemd}/bin/systemd-run --user -M arcadia@.host --collect -q -- \
      ${kodiWithPlugins}/bin/kodi
  '';
  couchHeroic = pkgs.writeShellScript "couch-heroic" ''
    exec ${pkgs.systemd}/bin/systemd-run --user -M arcadia@.host --collect -q -- \
      ${pkgs.heroic}/bin/heroic
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ./jellyfin-transcode.nix
  ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [ "consoleblank=0" ];
  boot.extraModprobeConfig = ''
    options r8169 aspm=0
  '';

  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nixpkgs.config.allowUnfree = true;

  # Networking
  networking.hostName = "arcadia";
  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Timezone & Locale
  time.timeZone = "America/Toronto";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Intel Graphics
  hardware.graphics = {
    enable = true;
    # 32-bit Mesa (/run/opengl-driver-32) for 32-bit Windows games under Proton:
    # without it MM6 dies at startup with "failed to open iris ... i386-linux-gnu".
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
      libvdpau-va-gl
    ];
  };
  hardware.cpu.intel.updateMicrocode = true;
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # Display & Desktop
  services.xserver = {
    enable = true;
    desktopManager.kodi = {
      enable = true;
      package = kodiWithPlugins;
    };
  };

  services.desktopManager.plasma6.enable = true;

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.displayManager.autoLogin = {
    enable = true;
    user = "arcadia";
  };
  services.displayManager.defaultSession = "plasma";

  # Input
  services.libinput = {
    enable = true;
    mouse.naturalScrolling = true;
  };

  # Couch-remote launcher chords. The remote's keyboard has no Super key, so we use
  # Right Alt (AltGr — unused on en_CA) as a layer modifier: hold AltGr, then g/Shift+g/k/h.
  # keyd rewrites at the /dev/input layer, below the compositor, so it works in both
  # Plasma (Wayland) and the Kodi session. The couch-* scripts (see let block above)
  # bounce each action into arcadia's graphical session since keyd runs as root.
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings = {
        main."rightalt" = "layer(launch)";
        launch = {
          "g" = "command(${couchStart})";   # AltGr+g → Konsole running `game`
          "k" = "command(${couchKodi})";    # AltGr+k → Kodi
          "h" = "command(${couchHeroic})";  # AltGr+h → Heroic (Epic/GOG/sideloaded games)
        };
        # AltGr+Shift+g → teardown. A composite layer is keyd's reliable way to make
        # the shifted chord distinct from plain AltGr+g (a same-layer S-g would not).
        "launch+shift"."g" = "command(${couchStop})";
      };
    };
  };

  # Audio (PipeWire)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Power - keep CPU efficient but NEVER sleep
  services.thermald.enable = true;
  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "ondemand";

  # Disable ALL sleep/suspend (the nuclear option)
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;

  services.logind = {
    settings.Login = {
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      IdleAction = "ignore";
      IdleActionSec = 0;
    };
  };

  # Disable screen blanking/locking
  environment.etc."xdg/kscreenlockerrc".text = ''
    [Daemon]
    Autolock=false
    LockOnResume=false
  '';

  environment.etc."xdg/powermanagementprofilesrc".text = ''
    [AC][DPMSControl]
    idleTime=0
    [AC][DimDisplay]
    idleTime=0
    [AC][SuspendSession]
    idleTime=0
    suspendType=0
  '';

  # Auto-start Kodi
  environment.etc."xdg/autostart/kodi.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Kodi
    Exec=kodi
    X-KDE-autostart-phase=2
  '';

  # Allow input group to write to /dev/uinput (needed by antimicrox)
  services.udev.extraRules = ''
    KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
  '';

  # Passwordless login
  security.pam.services.sddm.allowNullPassword = true;

  # Faster shutdown
  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";

  # User
  users.users.arcadia = {
    isNormalUser = true;
    description = "Media Center";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" "input" "render" ];
  };

  # Packages
  environment.systemPackages = with pkgs; [
    wget
    git
    htop
    libva-utils
    intel-gpu-tools
    firefox
    brave
    libcec
    moonlight-qt
    heroic
    protonup-qt
    antimicrox
    mpv                 # low-latency doorbell viewer (couchboard addon)
    claude-code
    python3
  ];

  programs.nix-ld.enable = true;

  # GitHub Actions Runner
  services.github-runners.arcadia = {
    enable = true;
    url = "https://github.com/greenmushrooms/arcadia-nixos-config";
    tokenFile = "/home/arcadia/.github-runner-token";
    extraLabels = [ "nixos" ];
    user = "arcadia";
    serviceOverrides = {
      ReadWritePaths = [ "/home/arcadia/projects/arcadia-nixos-config" ];
      ProtectHome = false;
    };
  };

  # Dedicated rebuild service
  systemd.services.nixos-rebuild-switch = {
    description = "NixOS Rebuild Switch";
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre = "-/run/current-system/sw/bin/systemctl reset-failed nixos-rebuild-switch-to-configuration.service";
      ExecStart = "/run/current-system/sw/bin/nixos-rebuild switch --refresh --no-write-lock-file --flake github:greenmushrooms/arcadia-nixos-config#arcadia";
    };
  };

  # Allow arcadia to trigger rebuild without password
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "nixos-rebuild-switch.service" &&
          subject.user == "arcadia") {
        return polkit.Result.YES;
      }
    });
  '';

  # Services
  services.openssh.enable = true;

  system.stateVersion = "25.11";
}
