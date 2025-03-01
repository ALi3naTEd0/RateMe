{ lib
, stdenv
, fetchFromGitHub
, flutter
, pkg-config
, gtk3
, makeWrapper
, wrapGAppsHook
, xdg-utils
}:

stdenv.mkDerivation rec {
  pname = "rateme";
  version = "1.0.2-1";

  src = fetchFromGitHub {
    owner = "ALi3naTEd0";
    repo = "RateMe";
    rev = "v${version}";
    sha256 = ""; # Hay que llenar esto después de intentar construir
  };

  nativeBuildInputs = [
    flutter
    pkg-config
    gtk3
    makeWrapper
    wrapGAppsHook
  ];

  buildInputs = [
    gtk3
  ];

  buildPhase = ''
    runHook preBuild
    export HOME=$(mktemp -d)
    flutter build linux --release
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/applications
    cp -r build/linux/x64/release/bundle/* $out/bin/
    mv $out/bin/rateme $out/bin/RateMe

    # Create desktop entry
    cat > $out/share/applications/rateme.desktop << EOF
    [Desktop Entry]
    Name=Rate Me!
    Comment=Rate and organize your music collection
    Exec=$out/bin/RateMe
    Icon=$out/bin/data/flutter_assets/assets/rateme.png
    Terminal=false
    Type=Application
    Categories=Audio;Music;
    EOF

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
