{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.autobrr;
  nixarr = config.nixarr;
  # Externalize username and group
  user = "autobrr";
  group = "autobrr";

  # Define config format and template
  configFormat = pkgs.formats.toml {};
  configTemplate = configFormat.generate "autobrr.toml" cfg.settings;
in {
  options.nixarr.autobrr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Autobrr service.

        **Required options:** [`nixarr.enable`](#nixarr.enable)
      '';
    };

    package = mkPackageOption pkgs "autobrr" {};

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.autobrr.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for the Autobrr port.";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Autobrr traffic through the VPN.
      '';
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = configFormat.type;
        options = {
          host = mkOption {
            type = types.str;
            default = "localhost";
            example = "0.0.0.0";
            description = "Host to bind to.";
          };

          port = mkOption {
            type = types.port;
            default = 7474;
            example = 8474;
            description = "Port to listen on.";
          };

          baseUrl = mkOption {
            type = types.str;
            default = "/";
            example = "/autobrr/";
            description = ''
              Base URL to use when serving requests.
              Set custom baseUrl e.g., /autobrr/ to serve in subdirectory.
              Not needed for subdomain, or by accessing with the :port directly.
            '';
          };

          logLevel = mkOption {
            type = types.enum [
              "ERROR"
              "DEBUG"
              "INFO"
              "WARN"
              "TRACE"
            ];
            default = "INFO";
            example = "DEBUG";
            description = "Log level for autobrr.";
          };

          checkForUpdates = mkOption {
            type = types.bool;
            default = false;
            description = "Check for updates on startup.";
          };

          metricsEnabled = mkOption {
            type = types.bool;
            default = false;
            description = "Enable Prometheus metrics endpoint.";
          };

          metricsHost = mkOption {
            type = types.str;
            default = "127.0.0.1";
            example = "0.0.0.0";
            description = "Host to bind metrics server to.";
          };

          metricsPort = mkOption {
            type = types.port;
            default = 9712;
            example = 9712;
            description = "Port for metrics server.";
          };
        };
      };
      default = {};
      example = literalExpression ''
        {
          host = "0.0.0.0";
          port = 7474;
          logLevel = "DEBUG";
          logMaxSize = 50;
          logMaxBackups = 3;
          customDefinitions = "/path/to/definitions";
        }
      '';
      description = "Settings for autobrr, see https://autobrr.com/configuration/autobrr for more information. `sessionSecret` is automatically generated upon first installation and will be overridden.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/autobrr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/autobrr"'';
      example = "/nixarr/.state/autobrr";
      description = "The location of the state directory for the Autobrr service.";
    };

    exporter = {
      enable = mkOption {
        type = types.nullOr types.bool;
        default = null;
        example = true;
        description = ''
          Whether to enable the Prometheus metrics exporter for Autobrr.
          If null, follows the global nixarr.exporters.enable setting.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 9712;
        example = 9712;
        description = "Port for the Prometheus metrics exporter.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.autobrr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = cfg.enable -> nixarr.enable;
        message = ''
          The nixarr.autobrr.enable option requires the nixarr.enable
          option to be set, but it was not.
        '';
      }
    ];

    users = {
      groups.${group} = {};
      users.${user} = {
        isSystemUser = true;
        group = group;
      };
    };

    # Create state directory with proper permissions
    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 ${user} ${group} - -"
    ];

    # Configure the autobrr service
    services.autobrr = {
      enable = true;
      package = cfg.package;
      secretFile = "/dev/null";
      settings = mkMerge [
        cfg.settings
        (mkIf cfg.vpn.enable {host = "192.168.15.1";})
        (mkIf (nixarr.exporters.enable && (cfg.exporter.enable == null || cfg.exporter.enable)) {
          metricsEnabled = mkForce true;
          metricsHost = if cfg.vpn.enable then "192.168.15.1" else "127.0.0.1";
          metricsPort = cfg.exporter.port;
        })
      ];
    };

    # Override the autobrr service to use our state directory and session secret handling
    systemd.services.autobrr = {
      description = "Autobrr";
      after = ["syslog.target" "network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.openssl pkgs.dasel];

      serviceConfig = {
        Type = "simple";
        User = user;
        Group = "root";
        UMask = 066;
        DynamicUser = lib.mkForce false;
        # disable state directory
        StateDirectory = lib.mkForce null;
        ExecStartPre = lib.mkForce (pkgs.writeShellScript "autobrr-config-prep" ''
          # Generate session secret if it doesn't exist
          SESSION_SECRET_FILE="${cfg.stateDir}/session-secret"
          if [ ! -f "$SESSION_SECRET_FILE" ]; then
            openssl rand -base64 32 > "$SESSION_SECRET_FILE"
            chmod 600 "$SESSION_SECRET_FILE"
          fi

          # Create config with session secret
          SESSION_SECRET=$(cat "$SESSION_SECRET_FILE")
          cp '${configTemplate}' "${cfg.stateDir}/config.toml"
          chmod 600 "${cfg.stateDir}/config.toml"
          ${pkgs.dasel}/bin/dasel put -f "${cfg.stateDir}/config.toml" -v "$SESSION_SECRET" -o "${cfg.stateDir}/config.toml" "sessionSecret"
        '');
        ExecStart = lib.mkForce "${lib.getExe cfg.package} --config ${cfg.stateDir}";
        Restart = "on-failure";
      };

      # Enable and specify VPN namespace to confine service in
      vpnConfinement = mkIf cfg.vpn.enable {
        enable = true;
        vpnNamespace = "wg";
      };
    };

    # Port mappings for VPN
    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = cfg.settings.port;
          to = cfg.settings.port;
        }
      ];
    };

    # Nginx proxy for VPN-confined service
    services.nginx = mkIf cfg.vpn.enable {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString cfg.settings.port}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.settings.port;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString cfg.settings.port}";
        };
      };
    };

    # Open firewall ports if needed
    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.settings.port];
    };
  };
}
