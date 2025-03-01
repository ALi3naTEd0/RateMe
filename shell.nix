{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    flutter
    pkg-config
    gtk3
    libkeybinder3
    xorg.libX11
    xorg.libXi
    xorg.libXrandr
    cairo
    pango
    glib
    pcre2
  ];

  shellHook = ''
    export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [
      pkgs.libGL
      pkgs.libxkbcommon
      pkgs.vulkan-loader
    ]}:$LD_LIBRARY_PATH
    
    export PUB_CACHE="$HOME/.pub-cache"
    export CHROME_EXECUTABLE=${pkgs.chromium}/bin/chromium
    
    echo "Flutter development environment ready!"
    echo "Try 'flutter doctor' to verify your setup."
  '';
}
