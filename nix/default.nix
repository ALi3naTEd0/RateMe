{ lib
, stdenv
, flutter
, pkg-config
, gtk3
, makeWrapper
, wrapGAppsHook
}:

stdenv.mkDerivation rec {
  pname = "rateme";
  version = "1.0.3-1";

  src = ./..;

  nativeBuildInputs = [
    flutter
    pkg-config
    gtk3
    makeWrapper
    wrapGAppsHook
  ];

  buildInputs = [ gtk3 ];

  # Disable network access
  __noChroot = false;
  
  # Skip the pub get step entirely and build with what we have
  postUnpack = ''
    # Ensure the .pub-cache directory exists
    mkdir -p $TMPDIR/.pub-cache
    export PUB_CACHE=$TMPDIR/.pub-cache
    
    # Copy any existing packages from the source
    if [ -d $src/.dart_tool ]; then
      cp -r $src/.dart_tool $sourceRoot/
    fi
  '';

  buildPhase = ''
    # Try building with existing dependencies
    export HOME=$TMPDIR
    export PUB_CACHE=$TMPDIR/.pub-cache
    
    # Try to build skipping dependency check
    flutter build linux --release --suppress-analytics
  '';

  installPhase = ''
    mkdir -p $out/bin $out/share/applications
    cp -r build/linux/x64/release/bundle/* $out/bin/
    mv $out/bin/rateme $out/bin/RateMe
  '';

  meta = with lib; {
    description = "A multi-platform app to rate and organize your music collection";
    homepage = "https://github.com/ALi3naTEd0/RateMe";
    license = licenses.gpl3;
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ "ALi3naTEd0" ];
  };
}
