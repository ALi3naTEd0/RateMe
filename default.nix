{ pkgs ? import <nixpkgs> {} }:

pkgs.callPackage (
  { lib
  , stdenv
  , makeWrapper
  , gtk3
  , pcre2
  , xorg
  , gsettings-desktop-schemas
  , glib
  }:

  stdenv.mkDerivation rec {
    pname = "rateme";
    version = "1.0.3-1";

    src = ./build/linux/x64/release/bundle;
    
    nativeBuildInputs = [ makeWrapper ];
    
    buildInputs = [
      gtk3
      pcre2
      xorg.libX11
      glib
    ];

    dontBuild = true;
    dontPatchELF = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/{bin,opt/rateme,share/applications,share/icons/hicolor/512x512/apps}
      cp -a ./* $out/opt/rateme/

      # Copy icon directly
      if [ -f data/flutter_assets/assets/rateme.png ]; then
        cp data/flutter_assets/assets/rateme.png $out/share/icons/hicolor/512x512/apps/
      elif [ -f data/flutter_assets/assets/app-icon.png ]; then
        cp data/flutter_assets/assets/app-icon.png $out/share/icons/hicolor/512x512/apps/rateme.png
      fi

      # Create desktop file
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

      runHook postInstall
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
