{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.jellyseerr;
  nixarr = config.nixarr;
  defaultPort = 5055;
in {
  imports = [
    ./jellyseerr-module
  ];

  options.nixarr.jellyseerr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Jellyseerr service.
      '';
    };

    package = mkPackageOption pkgs "jellyseerr" {};

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/jellyseerr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/jellyseerr"'';
      example = "/nixarr/.state/jellyseerr";
      description = ''
        The location of the state directory for the Jellyseerr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/jellyseerr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    port = mkOption {
      type = types.port;
      default = defaultPort;
      example = 12345;
      description = "Jellyseerr web-UI port.";
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.jellyseerr.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Jellyseerr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Jellyseerr traffic through the VPN.
      '';
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.jellyseerr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    util-nixarr.services.jellyseerr = {
      enable = true;
      package = cfg.package;
      openFirewall = cfg.openFirewall;
      port = cfg.port;
      configDir = cfg.stateDir;
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.jellyseerr.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

    # Port mappings
    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = defaultPort;
          to = defaultPort;
        }
      ];
    };

    services.nginx = mkIf cfg.vpn.enable {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString defaultPort}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = defaultPort;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString defaultPort}";
        };
      };
    };
  };
}
