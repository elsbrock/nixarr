{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr;

  # Helper to create API key extraction for a service
  mkApiKeyExtractor = serviceName: serviceConfig: {
    description = "Extract ${serviceName} API key";
    after = ["${serviceName}.service"];
    requires = ["${serviceName}.service"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Use DynamicUser if the parent service does
      DynamicUser = serviceConfig.serviceConfig.DynamicUser or false;
      # Only set User if not using DynamicUser
      ${
        if !(serviceConfig.serviceConfig.DynamicUser or false)
        then "User"
        else null
      } =
        serviceConfig.user or null;
      Group = "api-keys";
      UMask = "0027"; # Results in 0640 permissions

      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p ${cfg.stateDir}/api-keys"
        "${pkgs.coreutils}/bin/chown root:api-keys ${cfg.stateDir}/api-keys"
        "${pkgs.coreutils}/bin/chmod 750 ${cfg.stateDir}/api-keys"
        # Wait for config file to exist
        "${pkgs.bash}/bin/bash -c 'while [ ! -f ${serviceConfig.stateDir}/config.xml ]; do sleep 1; done'"
      ];

      ExecStart = pkgs.writeShellScript "extract-${serviceName}-api-key" ''
        ${pkgs.dasel}/bin/dasel -f "${serviceConfig.stateDir}/config.xml" \
          -s ".Config.ApiKey" | tr -d '\n\r' > "${cfg.stateDir}/api-keys/${serviceName}.key"
        chown $USER:api-keys "${cfg.stateDir}/api-keys/${serviceName}.key"
      '';
    };
  };
in {
  config = mkIf cfg.enable {
    users.groups.api-keys = {};

    # Ensure all services that need API keys are in the group
    users.users = mkMerge [
      # Static users
      (mkIf cfg.transmission.enable {torrenter.extraGroups = ["api-keys"];})
      (mkIf cfg.transmission.privateTrackers.cross-seed.enable {cross-seed.extraGroups = ["api-keys"];})
    ];

    # Add api-keys group to services with DynamicUser
    systemd.services = mkMerge [
      (mkIf cfg.sonarr.enable {sonarr.serviceConfig.SupplementaryGroups = ["api-keys"];})
      (mkIf cfg.radarr.enable {radarr.serviceConfig.SupplementaryGroups = ["api-keys"];})
      (mkIf cfg.lidarr.enable {lidarr.serviceConfig.SupplementaryGroups = ["api-keys"];})
      (mkIf cfg.readarr.enable {readarr.serviceConfig.SupplementaryGroups = ["api-keys"];})
      (mkIf cfg.prowlarr.enable {prowlarr.serviceConfig.SupplementaryGroups = ["api-keys"];})
      (mkIf cfg.recyclarr.enable {recyclarr.serviceConfig.SupplementaryGroups = ["api-keys"];})

      # Create API key extractors for enabled services
      (mkIf cfg.sonarr.enable {"sonarr-api-key" = mkApiKeyExtractor "sonarr" cfg.sonarr;})
      (mkIf cfg.radarr.enable {"radarr-api-key" = mkApiKeyExtractor "radarr" cfg.radarr;})
      (mkIf cfg.lidarr.enable {"lidarr-api-key" = mkApiKeyExtractor "lidarr" cfg.lidarr;})
      (mkIf cfg.readarr.enable {"readarr-api-key" = mkApiKeyExtractor "readarr" cfg.readarr;})
      (mkIf cfg.prowlarr.enable {"prowlarr-api-key" = mkApiKeyExtractor "prowlarr" cfg.prowlarr;})
    ];

    # Create the api-keys directory
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir}/api-keys 0750 root api-keys - -"
    ];
  };
}
