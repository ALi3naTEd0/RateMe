# Maintainer: ALi3naTEd0 <ali3nated0@protonmail.com>
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
# Remove options related to api_keys.dart protection
options=('!strip' '!debug' '!lto' 'staticlibs')
source=("git+$url.git#branch=main")
sha256sums=('SKIP')

prepare() {
    cd "$srcdir/RateMe"
    
    # Handle Flutter upgrade with local changes
    echo "Checking Flutter environment..."
    if ! flutter upgrade --force; then
        echo "Warning: Flutter upgrade failed, attempting to continue with existing Flutter version"
    fi
    
    flutter clean
    
    # Remove API keys generation - now handled by user input in the app
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