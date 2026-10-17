# Remote transcoding for prometheus' Jellyfin (rffmpeg).
#
# Jellyfin on prometheus runs every ffmpeg through rffmpeg, which runs it here over SSH as
# `transcode`, so the N100's iGPU (VA-API) does the work instead of prometheus' CPU, which the
# LLM queue keeps busy. rffmpeg passes Jellyfin's own paths straight through, so the same
# paths exist here: media read-only, Jellyfin's config read-only, its cache read-write
# (transcode output). They are SSHFS mounts back to prometheus over arcadia's existing key,
# automounted on first use, so nothing here waits on prometheus at boot.
{ pkgs, ... }:
let
  prometheus = "slava@192.168.1.42";
  sshfs = ro: [
    "_netdev" "noauto" "x-systemd.automount" "x-systemd.idle-timeout=30min" "x-systemd.mount-timeout=15s"
    "allow_other" "reconnect" "ServerAliveInterval=15" "ServerAliveCountMax=3"
    "IdentityFile=/home/arcadia/.ssh/id_ed25519" "UserKnownHostsFile=/home/arcadia/.ssh/known_hosts"
  ] ++ (if ro then [ "ro" ] else [ ]);

  # Exactly the ffmpeg build Jellyfin ships (8.1.3-1), so its generated command lines match.
  jellyfinFfmpeg = pkgs.stdenvNoCC.mkDerivation {
    pname = "jellyfin-ffmpeg-portable";
    version = "8.1.3-1";
    src = pkgs.fetchurl {
      url = "https://github.com/jellyfin/jellyfin-ffmpeg/releases/download/v8.1.3-1/jellyfin-ffmpeg_8.1.3-1_portable_linux64-gpl.tar.xz";
      hash = "sha256-uG3AI8ZKWppBDm46k4qXBGAhT6548xwVU8n4jxwom2o=";
    };
    sourceRoot = ".";
    dontFixup = true;            # static binaries; libva/libdrm are dlopen()ed at run time
    installPhase = ''
      install -Dm755 ffmpeg $out/libexec/ffmpeg
      install -Dm755 ffprobe $out/libexec/ffprobe
    '';
  };
  # The portable build dlopen()s libva/libdrm by name; give it NixOS' copies and the iHD driver.
  wrap = name: pkgs.writeShellScript "jellyfin-${name}" ''
    export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [ pkgs.libva pkgs.libdrm pkgs.vpl-gpu-rt ]}
    export LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri LIBVA_DRIVER_NAME=iHD
    exec ${jellyfinFfmpeg}/libexec/${name} "$@"
  '';
in
{
  system.fsPackages = [ pkgs.sshfs ];
  fileSystems = {
    "/video" = { device = "${prometheus}:/mnt/Media/Video"; fsType = "fuse.sshfs"; options = sshfs true; };
    "/music" = { device = "${prometheus}:/mnt/Media/Music"; fsType = "fuse.sshfs"; options = sshfs true; };
    "/books" = { device = "${prometheus}:/mnt/Media/Books"; fsType = "fuse.sshfs"; options = sshfs true; };
    "/config" = { device = "${prometheus}:/mnt/ContainerHub/DockerConfig/jellyfin/config"; fsType = "fuse.sshfs"; options = sshfs true; };
    "/cache" = { device = "${prometheus}:/mnt/ContainerHub/DockerConfig/jellyfin/cache"; fsType = "fuse.sshfs"; options = sshfs false; };
  };

  # rffmpeg calls the same path remotely as Jellyfin uses locally.
  systemd.tmpfiles.rules = [
    "d /usr/lib/jellyfin-ffmpeg 0755 root root -"
    "L+ /usr/lib/jellyfin-ffmpeg/ffmpeg - - - - ${wrap "ffmpeg"}"
    "L+ /usr/lib/jellyfin-ffmpeg/ffprobe - - - - ${wrap "ffprobe"}"
  ];

  users.groups.transcode = { };
  users.users.transcode = {
    isSystemUser = true;
    group = "transcode";
    extraGroups = [ "video" "render" ];
    home = "/var/lib/transcode";
    createHome = true;
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBxtejCy59sdwkNPzymPeI9h4YTY//MhYzUHg8KGnKw4 jellyfin-rffmpeg@prometheus"
    ];
  };
}
