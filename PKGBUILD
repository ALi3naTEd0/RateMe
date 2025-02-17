# Maintainer: ALi3naTEd0 <ALi3naTEd0@protonmail.com>
pkgname=rateme
pkgver=0.0.9
pkgrel=6
pkgdesc="Aplicación de calificación musical"
arch=('x86_64')
url="https://github.com/ALi3naTEd0/RateMe"
license=('GPL3')
depends=(
    'gtk3'
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
source=("git+$url.git#branch=rateme")
sha256sums=('SKIP')

prepare() {
    cd "$srcdir/RateMe"
    # Asegurarse de que estamos usando la última versión de flutter
    flutter upgrade
    flutter clean
}

build() {
    cd "$srcdir/RateMe"
    
    # Verificar archivos esenciales
    [ ! -f "linux/runner/rateme.desktop" ] && { echo "Error: .desktop no encontrado"; exit 1; }
    [ ! -f "assets/rateme.png" ] && { echo "Error: rateme.png no encontrado"; exit 1; }

    # Construir con configuración de release
    flutter config --enable-linux-desktop
    flutter build linux --release
}

package() {
    cd "$srcdir/RateMe"
    
    # Crear directorios necesarios
    install -dm755 "$pkgdir/usr/lib/$pkgname"
    install -dm755 "$pkgdir/usr/bin"
    
    # Instalar archivos del bundle manteniendo la estructura
    cp -r build/linux/x64/release/bundle/* "$pkgdir/usr/lib/$pkgname/"
    
    # Asegurarse de que los plugins estén en el lugar correcto
    if [ -d "$pkgdir/usr/lib/$pkgname/plugins" ]; then
        cp -r "$pkgdir/usr/lib/$pkgname/plugins/"* "$pkgdir/usr/lib/$pkgname/lib/"
    fi
    
    # Crear launcher script con configuración de entorno
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
    
    # Instalar .desktop y icon
    install -Dm644 "linux/runner/rateme.desktop" \
        "$pkgdir/usr/share/applications/rateme.desktop"
    install -Dm644 "assets/rateme.png" \
        "$pkgdir/usr/share/icons/hicolor/512x512/apps/rateme.png"

    # Ajustar RPATH para todas las bibliotecas
    find "$pkgdir/usr/lib/$pkgname/lib" -type f -name "*.so" -exec \
        patchelf --set-rpath '/usr/lib/rateme/lib:$ORIGIN' {} \;
    
    # Ajustar RPATH para el ejecutable principal
    patchelf --set-rpath "/usr/lib/$pkgname/lib" "$pkgdir/usr/lib/$pkgname/$pkgname"
}

post_install() {
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor
}