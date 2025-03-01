{ pkgs ? import <nixpkgs> {} }:

pkgs.callPackage (
  { lib
  , stdenv
  , makeWrapper
  , pkg-config
  , gtk3
  , pcre2
  , xorg
  , gsettings-desktop-schemas
  , glib
  , fetchurl
  }:

  stdenv.mkDerivation rec {
    pname = "rateme";
    version = "1.0.3-1";

    src = ./build/linux/x64/release/bundle;
    
    icon = fetchurl {
      url = "https://raw.githubusercontent.com/ALi3naTEd0/RateMe/rateme/assets/rateme.png";
      sha256 = "05ag3r2nvadj7lwmykr9vbxf15adqxjm1c5wd1x04xnhzdlw9395";
    };

    nativeBuildInputs = [ 
      makeWrapper 
      pkg-config
    ];
    
    buildInputs = [
      gtk3
      pcre2
      xorg.libX11
      glib
    ];

    installPhase = ''
      # Create base directories
      mkdir -p $out/{bin,opt/rateme,share/applications,share/icons/hicolor/512x512/apps}
      
      # Copy all app files
      cp -r ./* $out/opt/rateme/

      # Copy icon using the downloaded file
      cp ${icon} $out/share/icons/hicolor/512x512/apps/rateme.png

      # Create desktop entry
      cat > $out/share/applications/rateme.desktop << EOF
      [Desktop Entry]
      Type=Application
      Version=1.0
      Name=Rate Me!
      Comment=Rate and organize your music collection
      Exec=$out/bin/rateme
      Icon=rateme
      Categories=Audio;Music;
      Terminal=false
      EOF

      # Create wrapper
      makeWrapper $out/opt/rateme/rateme $out/bin/rateme \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ gtk3 pcre2 xorg.libX11 glib ]}" \
        --prefix XDG_DATA_DIRS : "$out/share:${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}:$XDG_DATA_DIRS"
    '';

    meta = with lib; {
      description = "A multi-platform app to rate and organize your music collection";
      homepage = "https://github.com/ALi3naTEd0/RateMe";
      license = licenses.gpl3;
      platforms = [ "x86_64-linux" ];
      maintainers = with maintainers; [ "ALi3naTEd0" ];
    };
  }
) {}
