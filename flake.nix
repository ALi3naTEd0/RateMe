{
  description = "Rate Me! - A multi-platform music rating app";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = rec {
          rateme = pkgs.callPackage ./nix { };
          default = rateme;
        };

        apps = rec {
          rateme = flake-utils.lib.mkApp { drv = self.packages.${system}.rateme; };
          default = rateme;
        };
      }
    );
}
