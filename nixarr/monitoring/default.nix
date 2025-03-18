{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr;
  
  # Helper function to determine if a specific exporter should be enabled
  shouldEnableExporter = service: 
    cfg.${service}.enable && 
    (cfg.monitoring.exporters.${service} or true);
    
  # Helper function to determine if a service is VPN-confined
  isVpnConfined = service: cfg.${service}.enable && cfg.${service}.vpn.enable;
    
  # Helper function to create a script that extracts API key from config.xml
  extractApiKey = service: stateDir: pkgs.writeShellScript "extract-${service}-apikey" ''
    ${pkgs.dasel}/bin/dasel -f ${stateDir}/config.xml -s "//ApiKey"
  '';
in {
  config = mkIf (cfg.enable && cfg.monitoring.enable) {
    # Configure Prometheus exporters for Arr services
    services.prometheus = {
      exporters = {
        # Enable exportarr for each supported service if it's enabled
        exportarr-sonarr = mkIf (shouldEnableExporter "sonarr") {
          enable = true;
          url = "http://127.0.0.1:8989";
          apiKey = "!${extractApiKey "sonarr" cfg.sonarr.stateDir}";
          port = 9707;
          environmentFile = null;
        };
        
        exportarr-radarr = mkIf (shouldEnableExporter "radarr") {
          enable = true;
          url = "http://127.0.0.1:7878";
          apiKey = "!${extractApiKey "radarr" cfg.radarr.stateDir}";
          port = 9708;
          environmentFile = null;
        };
        
        exportarr-lidarr = mkIf (shouldEnableExporter "lidarr") {
          enable = true;
          url = "http://127.0.0.1:8686";
          apiKey = "!${extractApiKey "lidarr" cfg.lidarr.stateDir}";
          port = 9709;
          environmentFile = null;
        };
        
        exportarr-readarr = mkIf (shouldEnableExporter "readarr") {
          enable = true;
          url = "http://127.0.0.1:8787";
          apiKey = "!${extractApiKey "readarr" cfg.readarr.stateDir}";
          port = 9710;
          environmentFile = null;
        };
        
        exportarr-prowlarr = mkIf (shouldEnableExporter "prowlarr") {
          enable = true;
          url = "http://127.0.0.1:9696";
          apiKey = "!${extractApiKey "prowlarr" cfg.prowlarr.stateDir}";
          port = 9711;
          environmentFile = null;
        };
        
        # Enable node and systemd exporters by default
        node.enable = true;
        systemd.enable = true;
      };
    };

    # Add systemd services for VPN-confined exporters
    systemd.services = mkMerge [
      (mkIf cfg.vpn.enable (
        let
          # Create VPN-confined exporter services for each Arr service
          makeVpnExporterService = service: nameInConfig:
            mkIf (isVpnConfined service) {
              "prometheus-exportarr-${service}-exporter".vpnConfinement = {
                enable = true;
                vpnNamespace = "wg";
              };
            };
        in
          lib.mkMerge [
            (makeVpnExporterService "sonarr" "exportarr-sonarr")
            (makeVpnExporterService "radarr" "exportarr-radarr")
            (makeVpnExporterService "lidarr" "exportarr-lidarr")
            (makeVpnExporterService "readarr" "exportarr-readarr")
            (makeVpnExporterService "prowlarr" "exportarr-prowlarr")
          ]
      ))
      {
        prometheus-wireguard-exporter = mkIf cfg.vpn.enable {
          description = "Prometheus Wireguard Exporter";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          
          serviceConfig = {
            ExecStart = "${pkgs.prometheus-wireguard-exporter}/bin/wireguard_exporter";
            Restart = "always";
            DynamicUser = true;
            ProtectHome = true;
            ProtectSystem = "full";
          };
          
          # Configure the service to run in the VPN namespace
          vpnConfinement = {
            enable = true;
            vpnNamespace = "wg";
          };
        };
      }
    ];
    
    # Add port mappings for VPN-confined exporters
    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = 
        (optional (shouldEnableExporter "sonarr" && isVpnConfined "sonarr") { from = 9707; to = 9707; }) ++
        (optional (shouldEnableExporter "radarr" && isVpnConfined "radarr") { from = 9708; to = 9708; }) ++
        (optional (shouldEnableExporter "lidarr" && isVpnConfined "lidarr") { from = 9709; to = 9709; }) ++
        (optional (shouldEnableExporter "readarr" && isVpnConfined "readarr") { from = 9710; to = 9710; }) ++
        (optional (shouldEnableExporter "prowlarr" && isVpnConfined "prowlarr") { from = 9711; to = 9711; }) ++
        [
          {
            from = 9586; # Default Wireguard exporter port
            to = 9586;
          }
        ];
    };
    
    # Open firewall ports for the exporters
    networking.firewall.allowedTCPPorts = mkIf (!cfg.vpn.enable) (
      (optional (shouldEnableExporter "sonarr") 9707) ++
      (optional (shouldEnableExporter "radarr") 9708) ++
      (optional (shouldEnableExporter "lidarr") 9709) ++
      (optional (shouldEnableExporter "readarr") 9710) ++
      (optional (shouldEnableExporter "prowlarr") 9711)
    );
  };
} 