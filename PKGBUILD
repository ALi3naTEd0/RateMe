# Maintainer: ALi3naTEd0 <eduardo.fortuny@outlook.com>
pkgname=rateme
pkgver=1.1.1
pkgrel=1
pkgdesc="Rate Me! - A music album rating application"  # Note the exclamation mark here
arch=('x86_64')
url="https://github.com/ALi3naTEd0/RateMe"
license=('MIT')
depends=(
    'gtk3'
    'zenity'
    'adwaita-icon-theme'
    'libglvnd'
    'pcre2'
    'openssl'
    'libsecret'
    'hicolor-icon-theme'
    'xcursor-themes'
    'gnome-themes-extra'
)
makedepends=(
    'git'
    'flutter'
    'clang'
    'cmake'
    'ninja'
    'patchelf'
)
# Add options to prevent including api_keys.dart in the package source
options=('!strip' '!debug' '!lto' 'staticlibs')
source=("git+$url.git#branch=main")
sha256sums=('SKIP')

prepare() {
    cd "$srcdir/RateMe"
    # Make sure we are using the latest flutter version
    flutter upgrade
    flutter clean
    
    # Create api_keys.dart with the real API keys
    mkdir -p lib
    cat > lib/api_keys.dart << EOF
class ApiKeys {
  // Spotify API keys - Base64 encoded for basic obfuscation
  static const String spotifyClientId = _decodeKey('MWRkZjIwMjFlZTM4NGZhODhiOTJmMGVkOTdkZTY4MDI=');
  static const String spotifyClientSecret = _decodeKey('ZjI4YzdmZWQ1Nzk0NDk3ODlkMjdjZTM4YWJjMTJjMzk=');
  
  // Discogs API keys - Base64 encoded for basic obfuscation
  static const String discogsConsumerKey = _decodeKey('amZkZHNmUWt5dUNjd0V5am5zd2s=');
  static const String discogsConsumerSecret = _decodeKey('bkFMb1NtRHdLbm9CT1RKRHhnT1NQU2JPa2tXRlN2RVk=');
  
  // Decode base64 encoded keys
  static String _decodeKey(String encodedKey) {
    // Simple base64 decoding - this happens at runtime
    final List<int> bytes = base64.decode(encodedKey);
    return utf8.decode(bytes);
  }
  
  // API request timeout durations (in seconds)
  static const int defaultRequestTimeout = 30;
  static const int longRequestTimeout = 60;
  
  // Fallback API servers/endpoints
  static const List<String> spotifyApiServers = [
    'https://api.spotify.com/v1/',
    'https://api-partner.spotify.com/v1/',
  ];
  
  // Rate limiting configuration
  static const int maxRequestsPerMinute = 120;
  static const int cooldownPeriodSeconds = 60;
  
  // Retry configuration
  static const int maxRetries = 3;
  static const int retryDelaySeconds = 2;
  
  // Cache configuration
  static const bool enableResponseCaching = true;
  static const int defaultCacheExpiryMinutes = 60;
}

// Import statement for base64 and utf8 - needed at the top of the file
import 'dart:convert';

class ApiEndpoints {
  // Spotify endpoints
  static const String spotifyAlbumSearch = 'search';
  static const String spotifyAlbumDetails = 'albums';
  static const String spotifyArtistDetails = 'artists';
  
  // Discogs endpoints
  static const String discogsSearch = 'database/search';
  static const String discogsMaster = 'masters';
  static const String discogsRelease = 'releases';
}
EOF
}

build() {
    cd "$srcdir/RateMe"
    
    # Verify essential files
    [ ! -f "linux/runner/rateme.desktop" ] && { echo "Error: .desktop file not found"; exit 1; }
    [ ! -f "assets/rateme.png" ] && { echo "Error: rateme.png not found"; exit 1; }

    # Build with release configuration
    flutter config --enable-linux-desktop
    flutter build linux --release
}

package() {
    cd "$srcdir/RateMe"
    
    # Create required directories
    install -dm755 "$pkgdir/usr/lib/$pkgname"
    install -dm755 "$pkgdir/usr/bin"
    
    # Install bundle files maintaining structure
    cp -r build/linux/x64/release/bundle/* "$pkgdir/usr/lib/$pkgname/"
    
    # Ensure plugins are in the correct location
    if [ -d "$pkgdir/usr/lib/$pkgname/plugins" ]; then
        cp -r "$pkgdir/usr/lib/$pkgname/plugins/"* "$pkgdir/usr/lib/$pkgname/lib/"
    fi
    
    # Create launcher script with environment setup
    cat > "$pkgdir/usr/bin/$pkgname" << EOF
#!/bin/sh
export GDK_BACKEND=x11
export GTK_THEME=Adwaita
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
export LD_LIBRARY_PATH="/usr/lib/$pkgname/lib:\$LD_LIBRARY_PATH"
exec /usr/lib/$pkgname/$pkgname "\$@"
EOF
    chmod 755 "$pkgdir/usr/bin/$pkgname"
    
    # Install .desktop and icon files
    install -Dm644 "linux/runner/rateme.desktop" \
        "$pkgdir/usr/share/applications/rateme.desktop"
    install -Dm644 "assets/rateme.png" \
        "$pkgdir/usr/share/icons/hicolor/512x512/apps/rateme.png"
    
    # Create desktop entry with correct name and icon
    cat > "$pkgdir/usr/share/applications/$pkgname.desktop" << EOF
[Desktop Entry]
Name=Rate Me!
Comment=Rate your music albums
Exec=/usr/bin/$pkgname
Icon=rateme
Type=Application
Categories=Audio;Music;
EOF

    chmod 644 "$pkgdir/usr/share/applications/$pkgname.desktop"

    # Adjust RPATH for all libraries
    find "$pkgdir/usr/lib/$pkgname/lib" -type f -name "*.so" -exec \
        patchelf --set-rpath '/usr/lib/rateme/lib:$ORIGIN' {} \;
    
    # Adjust RPATH for main executable
    patchelf --set-rpath "/usr/lib/$pkgname/lib" "$pkgdir/usr/lib/$pkgname/$pkgname"
}

post_install() {
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor
}