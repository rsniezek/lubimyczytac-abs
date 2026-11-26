# NixOS module: run the LubimyCzytaj metadata provider as a local service.
#
# The provider is stateless (its cache lives in memory) and is meant to be
# reached by Audiobookshelf on loopback, so it binds 127.0.0.1 by default and
# opens no firewall port unless asked to.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.lubimyczytac-abs;
in
{
  options.services.lubimyczytac-abs = {
    enable = lib.mkEnableOption "the LubimyCzytaj metadata provider for Audiobookshelf";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The provider package to use.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address to listen on. Keep it on loopback unless Audiobookshelf runs elsewhere.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "TCP port to listen on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the port in the firewall (only useful when the host is not loopback).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.lubimyczytac-abs = {
      description = "LubimyCzytaj metadata provider for Audiobookshelf";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HOST = cfg.host;
        PORT = toString cfg.port;
      };

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/lubimyczytac-abs";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";

        # Stateless: no writable state, no home directory, no new privileges.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        LockPersonality = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
