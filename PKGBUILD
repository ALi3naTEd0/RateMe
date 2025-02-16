# Maintainer: ALi3naTEd0 <ALi3naTEd0@protonmail.com>
pkgname=rateme
pkgver=0.0.9
pkgrel=5
pkgdesc="Aplicación de calificación musical"
arch=('x86_64')
url="https://github.com/ALi3naTEd0/RateMe"
license=('GPL3')
depends=(
    'gtk3'
    'libglvnd'
    'pcre2'
    'openssl'
    'libsecret'
)
makedepends=(
    'git'
    'flutter'
    'clang'
    'cmake'
    'ninja'
    'patchelf'
)
source=("git+$url.git#branch=rateme")
sha256sums=('SKIP')

build() {
    cd "$srcdir/RateMe"
    
    # Check essential files
    [ ! -f "linux/runner/rateme.desktop" ] && { echo "Error: .desktop no encontrado"; exit 1; }
    [ ! -f "assets/rateme.png" ] && { echo "Error: rateme.png no encontrado"; exit 1; }

    # Clean build
    flutter clean
    flutter pub get
    flutter build linux --release
}

package() {
    # Install executable
    install -Dm755 "$srcdir/RateMe/build/linux/x64/release/bundle/rateme" \
        "$pkgdir/usr/bin/rateme"

    # Install .desktop
    install -Dm644 "$srcdir/RateMe/linux/runner/rateme.desktop" \
        "$pkgdir/usr/share/applications/rateme.desktop"

    # Install icon
    install -Dm644 "$srcdir/RateMe/assets/rateme.png" \
        "$pkgdir/usr/share/icons/hicolor/512x512/apps/rateme.png"

    # Install libraries
    install -d "$pkgdir/usr/lib/rateme"
    cp -r "$srcdir/RateMe/build/linux/x64/release/bundle/lib" \
        "$pkgdir/usr/lib/rateme/"

    # Adjust RPATH
    find "$pkgdir/usr/lib/rateme/lib" -name '*.so' -exec patchelf --set-rpath '$ORIGIN' {} \;
    patchelf --set-rpath '/usr/lib/rateme/lib' "$pkgdir/usr/bin/rateme"
}