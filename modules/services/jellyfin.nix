# Jellyfin Configuration
# Self-hosted media server with hardware transcoding

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.nixnas.jellyfin;
in
{
  options.nixnas.jellyfin = {
    enable = mkEnableOption "Jellyfin media server";

    dataDir = mkOption {
      type = types.path;
      default = "/data/jellyfin";
      description = "Jellyfin data directory";
    };

    mediaDir = mkOption {
      type = types.path;
      default = "/data/media";
      description = "Media library directory";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open firewall ports for Jellyfin";
    };
  };

  config = mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = cfg.openFirewall;
      dataDir = cfg.dataDir;
    };

    # Hardware acceleration (Intel QuickSync / VAAPI)
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver    # Intel Gen 8+ (Broadwell and newer)
        intel-vaapi-driver    # Intel Gen 7 and earlier
        vaapiVdpau           # VDPAU backend for VAAPI
        libvdpau-va-gl       # VDPAU driver with OpenGL/VAAPI backend
        intel-compute-runtime # OpenCL support
      ];
    };

    # Allow jellyfin to access GPU for transcoding
    users.users.jellyfin.extraGroups = [ "render" "video" ];

    # Ensure directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 jellyfin jellyfin -"
      "d ${cfg.mediaDir} 0775 root media -"
      "d ${cfg.mediaDir}/movies 0775 root media -"
      "d ${cfg.mediaDir}/tv 0775 root media -"
      "d ${cfg.mediaDir}/music 0775 root media -"
      "d ${cfg.mediaDir}/photos 0775 root media -"
    ];

    # Add jellyfin to media group for library access
    users.users.jellyfin.extraGroups = mkAfter [ "media" ];

    # Avahi service for discovery
    services.avahi.extraServiceFiles.jellyfin = mkIf config.services.avahi.enable ''
      <?xml version="1.0" standalone='no'?>
      <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
      <service-group>
        <name replace-wildcards="yes">Jellyfin on %h</name>
        <service>
          <type>_http._tcp</type>
          <port>8096</port>
        </service>
      </service-group>
    '';
  };
}
