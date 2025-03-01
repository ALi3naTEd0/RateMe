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
        version = "1.0.3-1"; # Update this when releasing
      in
      {
        packages = rec {
          rateme = pkgs.stdenv.mkDerivation {
            pname = "rateme";
            inherit version;
            
            src = pkgs.fetchurl {
              url = "https://github.com/ALi3naTEd0/RateMe/releases/download/v${version}/RateMe_${version}.AppImage";
              # This hash se actualizará automáticamente por el CI en cada release
              sha256 = "0000000000000000000000000000000000000000000000000000";
            };
            
            # ...rest of derivation...
          };
          default = rateme;
        };

        apps = rec {
          rateme = flake-utils.lib.mkApp { drv = self.packages.${system}.rateme; };
          default = rateme;
        };
      }
    );
}
