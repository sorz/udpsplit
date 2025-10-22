self:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.services.udpsplit;
  desc = "udpsplit - simple UDP forwarder that splits WireGuard traffic over dual-stack network";
  defaultPkg = self.packages.${pkgs.system}.default;
  instanceType = lib.types.submodule {
    options = {
      remote = lib.mkOption {
        type = lib.types.str;
        description = "Remote socket address";
      };
      logLevel = lib.mkOption {
        type = lib.types.enum [
          "error"
          "warn"
          "info"
          "debug"
          "trace"
        ];
        default = "info";
        description = "Log level";
      };
    };
  };
in
{
  options.services.udpsplit = {
    enable = lib.mkEnableOption desc;
    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPkg;
      description = "Package to run for the udpsplit service";
    };
    ports = lib.mkOption {
      type = lib.types.attrsOf instanceType;
      description = "UDP listen ports and corresponding remote addresses";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services =
      lib.mapAttrs' (port: instance:
        let
          service = {
            description = desc;
            wantedBy = [ "multi-user.target" ];
            after = [ "network-online.target" ];
            wants = [ "network-online.target" ];
            serviceConfig = {
              Type = "exec";
              DynamicUser = true;
              ExecStart = ''
                ${cfg.package}/bin/udpsplit \
                  --port ${port} \
                  --remote ${instance.remote} \
                  --log-level ${instance.logLevel}
              '';
              SocketBindAllow = [ "udp:${port}" ];
              SocketBindDeny = [ "any" ];

              PrivateDevices = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ProtectHostname = true;
              ProtectClock = true;
              ProtectProc = "invisible";
              ProtectKernelModules = true;
              ProtectKernelLogs = true;
              ProtectKernelTunables = true;
              ProtectControlGroups = true;
              RestrictRealtime = true;
              RestrictNamespaces = true;
              RestrictSUIDSGID = true;
              RestrictAddressFamilies = "AF_INET AF_INET6";
              LockPersonality = true;
              NoNewPrivileges = true;
              MemoryDenyWriteExecute = true;
              CapabilityBoundingSet = "";
              SystemCallArchitectures = "native";
              SystemCallFilter = "~@obsolete @clock @cpu-emulation @debug @keyring @module @mount @raw-io @swap";
            };
          };
        in
        lib.nameValuePair "udpsplit-${port}" service
      ) cfg.ports;
  };
}
