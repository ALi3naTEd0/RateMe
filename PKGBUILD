# Maintainer: ALi3naTEd0 <ALi3naTEd0@protonmail.com>
pkgname=rateme
pkgver=0.0.9
pkgrel=5
pkgdesc="Rate Me!"
arch=('x86_64')
url="https://github.com/ALi3naTEd0/RateMe"
license=('GPL3')
depends=('gtk3' 'libappindicator-gtk3' 'libxkbcommon' 'hicolor-icon-theme' 'flutter-engine')
makedepends=('git' 'flutter' 'patchelf')
options=('!lto')
source=("git+https://github.com/ALi3naTEd0/RateMe.git#tag=v${pkgver}-${pkgrel}")
sha256sums=('SKIP')

prepare() {
    cd "$srcdir/RateMe"
    # Update Flutter if necessary
    if [ ! -d "$srcdir/flutter" ]; then
        git clone https://github.com/flutter/flutter.git -b stable "$srcdir/flutter"
    else
        cd "$srcdir/flutter"
        git pull
    fi
}

build() {
    cd "$srcdir/flutter"
    export PATH="$srcdir/flutter/bin:$PATH"
    cd "$srcdir/RateMe"
    flutter build linux --release --no-tree-shake-icons
    
    # Configura RPATH
    patchelf --set-rpath '$ORIGIN/lib' build/linux/x64/release/bundle/rateme
}

package() {
    cd "$srcdir/RateMe"
    
    # Crear directorio de destino
    mkdir -p "$pkgdir/opt/rateme"
    
    # Copiar todo el contenido del bundle
    cp -R "build/linux/x64/release/bundle/"* "$pkgdir/opt/rateme/"
    
    # Crear enlace simbólico en /usr/bin
    mkdir -p "$pkgdir/usr/bin"
    ln -s /opt/rateme/rateme "$pkgdir/usr/bin/rateme"
    
    # Instalar archivo .desktop
    install -Dm644 "linux/rateme.desktop" "$pkgdir/usr/share/applications/rateme.desktop"
    
    # Ajustar el archivo .desktop si es necesario
    sed -i 's|^Exec=.*|Exec=/opt/rateme/rateme|' "$pkgdir/usr/share/applications/rateme.desktop"
}