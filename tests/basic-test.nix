{ pkgs, nixosModules, lib ? pkgs.lib }:

let
  hostName = "nixarrtest";
in
pkgs.nixosTest {
  name = "nixarr-basic-test";

  # Define the VM configurations
  nodes = {
    ${hostName} = { config, pkgs, ... }: {
      imports = [
        nixosModules.default
      ];

      # Set up basic test configuration
      nixarr = {
        enable = true;

        # Add basic service configurations to test (example)
        sonarr = {
          enable = true;
        };
        radarr = {
          enable = true;
        };

        # Set required directories
        mediaDir = "/data/media";
        stateDir = "/data/.state/nixarr";
        
        # Explicitly disable optional components that might have assertions
        vpn.enable = false;
        jellyfin.enable = false;
        plex.enable = false;
        jellyseerr.enable = false;
        bazarr.enable = false;
        lidarr.enable = false;
        readarr.enable = false;
        prowlarr.enable = false;
        transmission.enable = false;
        sabnzbd.enable = false;
        autobrr.enable = false;
        recyclarr.enable = false;
      };

      # Enable virtualisation
      virtualisation.memorySize = 2048;
      virtualisation.diskSize = 4096;

      # Open required ports for testing
      networking.firewall.allowedTCPPorts = [ 80 443 8989 7878 ];

      # Add other necessary system configurations for testing
      networking.hostName = hostName;
    };
  };

  # Define the test script
  testScript = ''
    start_all()

    # Wait for the system to be up
    ${hostName}.wait_for_unit("multi-user.target")

    # Test that core services are running
    ${hostName}.succeed("systemctl is-active sonarr.service")
    ${hostName}.succeed("systemctl is-active radarr.service")

    # Check if the services are responding
    ${hostName}.wait_until_succeeds("curl -s http://localhost:8989/ | grep -q Sonarr")
    ${hostName}.wait_until_succeeds("curl -s http://localhost:7878/ | grep -q Radarr")

    # Check for media directory
    ${hostName}.succeed("test -d /data/media")
    ${hostName}.succeed("test -d /data/.state/nixarr")

    # Test users and groups
    ${hostName}.succeed("getent group media")
    ${hostName}.succeed("getent passwd sonarr")
    ${hostName}.succeed("getent passwd radarr")

    # Print log information for debugging
    ${hostName}.succeed("journalctl -u sonarr -n 20 >&2")

    ${hostName}.shutdown()
  '';
} 