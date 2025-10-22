{
  description = "udpsplit - simple UDP forwarder that splits WireGuard traffic over dual-stack network";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        craneLib = crane.mkLib pkgs;
        commonArgs = {
          src = craneLib.cleanCargoSource ./.;
          strictDeps = true;
          buildInputs = [
            pkgs.openssl
          ];
          nativeBuildInputs = [
            pkgs.pkg-config
          ];
        };

        udpsplit = craneLib.buildPackage (
          commonArgs
          // {
            cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          }
        );
      in
      {
        checks = {
          inherit udpsplit;
        };
        packages.default = udpsplit;
        apps.default = flake-utils.lib.mkApp {
          drv = udpsplit;
        };

        devShells.default = craneLib.devShell {
          checks = self.checks.${system};
          packages = [ ];
        };

        formatter = pkgs.nixfmt-tree;
      }
    )
    // {
      nixosModules.default = import ./nixos.nix self;
    };
}
