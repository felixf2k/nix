# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

let
  secrets = import ./secrets.nix; # Import your secrets file
  mssClampScript = pkgs.writeShellScript "mss-clamp.sh" ''
    #!${pkgs.runtimeShell}
    IPTABLES="${pkgs.iptables}/bin/iptables"
    IP6TABLES="${pkgs.iptables}/bin/ip6tables"

    # MTU discovered to be 1390 (ping payload 1362 + 28 headers).
    # MSS = MTU - 40 headers = 1350. We manually set this to bypass the MTU black hole.
    MSS_VALUE="1350"

    case "$PLUTO_VERB" in
      up-client)
        # Check if the rule exists (-C) before inserting (-I) to prevent duplicates.
        $IPTABLES -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE 2>/dev/null || \
          $IPTABLES -t mangle -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE

        $IPTABLES -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE 2>/dev/null || \
          $IPTABLES -t mangle -I OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE

        $IP6TABLES -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE 2>/dev/null || \
          $IP6TABLES -t mangle -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE

        $IP6TABLES -t mangle -C OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE 2>/dev/null || \
          $IP6TABLES -t mangle -I OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE
        ;;
      down-client)
        # Safely delete the rules on disconnect.
        $IPTABLES -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE 2>/dev/null
        $IPTABLES -t mangle -D OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE 2>/dev/null
        $IP6TABLES -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE 2>/dev/null
        $IP6TABLES -t mangle -D OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_VALUE 2>/dev/null
        ;;
    esac
  '';
in
{
  imports =
    [ # Include the results of the hardware scan.
      /etc/nixos/hardware-configuration.nix
    ];
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable IP forwarding for the system to act as a router for the VPN tunnel
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };

  boot.kernelParams = [ 
    "video=DP-6:5120x1440@144"
  ];

  networking =
      let
        # Define MTU and MSS here to be used throughout the networking config.
        vpnMtu = 1389;
        # MSS = MTU - 40 bytes (20 for IP header, 20 for TCP header)
        vpnMss = vpnMtu - 40;
      in
      {
        hostName = "laptop";
        networkmanager.enable = true;
        firewall = {
          allowedTCPPorts = [ 5173 4173 ];
          allowedUDPPorts = [ 500 4500 ];
          # extraCommands = ''
          #   # Dynamically clamp TCP MSS to Path MTU. This is the key fix.
          #   # It automatically calculates the correct MSS for any connection,
          #   # including the VPN tunnel, without hardcoding values.

          #   # Rule for traffic passing THROUGH your firewall (fixes downloads for other devices)
          #   iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
          #   ip6tables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

          #   # Rule for traffic originating FROM your laptop (fixes uploads/downloads from the laptop itself)
          #   iptables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
          #   ip6tables -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
          # '';
        };
        extraHosts = ''
          127.0.0.1 caddy.localhost
        '';
      };

  environment.etc."strongswan/mss-clamp.sh" = {
    source = mssClampScript;
    mode = "0755"; # Make it executable
  };
  # Enable and configure Strongswan
  services.strongswan = {
    enable = true;
    connections = {
      # This is your VPN connection as provided by your colleague
      "CI-Dev-Clients" = {
        keyexchange = "ikev2";
        auto = "start";
        type = "tunnel";
        mobike = "yes";

        leftupdown = "/etc/strongswan/mss-clamp.sh";

        left = "%any";
        leftid="@laptop";
        leftsourceip = "%config";
        leftauth = "psk";

        right = "212.87.147.6";
        rightid = "@fortigate-0001";
        rightsubnet = "198.18.233.0/24,10.0.1.0/24,172.16.16.0/20,198.18.234.0/24";
        rightauth = "psk";

        fragmentation = "yes";
        rekey = "yes";
      };
    };
  };
  environment.etc."ipsec.secrets".source = lib.mkForce ./ipsec.secrets;

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver = {
    layout = "de";
    xkbVariant = "";
  };

  # Configure console keymap
  console.keyMap = "de";

  # Enable CUPS to print documents.
  services.printing.enable = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.felix = {
    isNormalUser = true;
    description = "Felix Fischerkeller";
    extraGroups = [ "networkmanager" "wheel" "docker"];
    packages = with pkgs; [
      thunderbird
      chromium
      microsoft-edge
      keepassxc
      spotify
      gimp
      lens
      microsoft-edge
      nextcloud-talk-desktop
      obsidian
      vscode
      discord
      solaar
      gnomeExtensions.solaar-extension
      libreoffice
      pnpm
      nodejs_24
      jetbrains.webstorm
      steam
      gnome-tweaks
    ];
  };

  # enable docker
  virtualisation.docker.enable = true;

  # dont logout on idle
  services.xserver.displayManager.gdm.autoSuspend = false;

  # remove gnome bloatware
  environment.gnome.excludePackages = (with pkgs; [
    gnome-photos
    gnome-tour
  ]) ++ (with pkgs; [
    cheese # webcam tool
    gnome-music
    epiphany # web browser
    geary # email reader
    evince # document viewer
    gnome-characters
    tali # poker game
    iagno # go game
    hitori # sudoku game
    atomix # puzzle game
  ]);

  # Install firefox.
  programs.firefox.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim 
    git
    tree
    strongswan
    gnomeExtensions.tiling-shell
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # These are already covered by the Strongswan setup, but good to have explicit.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

}
