{ lib, stdenv, makeWrapper, gtk3 }:

stdenv.mkDerivation rec {
  pname = "rateme";
  version = "1.0.3-1";

  # Use the pre-built binaries
  src = ../build/linux/x64/release/bundle;

  nativeBuildInputs = [
    makeWrapper
  ];
  
  buildInputs = [
    gtk3
  ];

  installPhase = ''
    mkdir -p $out/bin $out/share/applications $out/share/icons/hicolor/512x512/apps
    
    # Copy all files
    cp -r * $out/
    
    # Create symlink
    ln -s $out/rateme $out/bin/RateMe
    
    # Copy icon (assuming it's in the bundle)
    cp $out/data/flutter_assets/assets/rateme.png $out/share/icons/hicolor/512x512/apps/
    
    # Create desktop entry
    cat > $out/share/applications/rateme.desktop << EOF
    [Desktop Entry]
    Name=Rate Me!
    Comment=Rate and organize your music collection
    Exec=$out/bin/RateMe
    Icon=$out/share/icons/hicolor/512x512/apps/rateme.png
    Terminal=false
    Type=Application
    Categories=Audio;Music;
    EOF
  '';

  meta = with lib; {
    description = "A multi-platform app to rate and organize your music collection";
    homepage = "https://github.com/ALi3naTEd0/RateMe";
    license = licenses.gpl3;
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ "ALi3naTEd0" ];
  };
}
