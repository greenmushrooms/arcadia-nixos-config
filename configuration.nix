{ config, pkgs, ... }:
let
  kodiWithPlugins = pkgs.kodi.withPackages (kodiPkgs: with kodiPkgs; [
    jellycon
    inputstream-adaptive
    inputstream-ffmpegdirect
  ]);
in
{
  imports = [
    ./hardware-configuration.nix
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
  nixpkgs.config.allowUnfree = true;

  # Networking
  networking.hostName = "arcadia";
  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  # Timezone & Locale
  time.timeZone = "America/Toronto";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Intel Graphics
  hardware.graphics = {
    enable = true;
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
  powerManagement.cpuFreqGovernor = "powersave";

  # Disable ALL sleep/suspend (the nuclear option)
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
  systemd.services."systemd-suspend".enable = false;
  systemd.services."systemd-hibernate".enable = false;
  systemd.services."systemd-hybrid-sleep".enable = false;
  systemd.services."systemd-suspend-then-hibernate".enable = false;

  services.logind = {
    lidSwitch = "ignore";
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
    vim
    wget
    git
    htop
    libva-utils
    intel-gpu-tools
    alacritty
    fuzzel
    waybar
    firefox
    brave
    libcec
    moonlight-qt
    heroic
  ];

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
      ExecStart = "/run/current-system/sw/bin/nixos-rebuild switch --flake /home/arcadia/projects/arcadia-nixos-config#arcadia";
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
