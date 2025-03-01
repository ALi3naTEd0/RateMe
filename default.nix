{ lib
, stdenv
, fetchFromGitHub
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

    mkdir -p $out/bin $out/opt/rateme $out/share/applications
    cp -a ./* $out/opt/rateme/

    # Symlink icon
    mkdir -p $out/share/icons/hicolor/512x512/apps
    ln -s $out/opt/rateme/data/flutter_assets/assets/rateme.png \
      $out/share/icons/hicolor/512x512/apps/rateme.png

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

    # Wrapper
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
