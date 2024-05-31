pkgname="RateMe"
pkgver=0.0.9
pkgrel=1
pkgdesc="Music Rating App"
arch=('x86_64')
url="https://github.com/ALi3naTEd0/RateMe"
license=('GPL3')

source=()

build() {
    cd "$srcdir"
    # No hay necesidad de comandos de construcción específicos para Flutter
}

package() {
    cd "$srcdir"
    
    # Crear la estructura de directorios del paquete
    mkdir -p "$pkgdir/usr/bin"
    
    # Copiar los archivos de la aplicación al directorio de instalación
    cp -r "$srcdir/linux/"* "$pkgdir/usr/bin/"

    # Crear un enlace simbólico al ejecutable de la aplicación
    ln -s "/usr/bin/rateme" "$pkgdir/usr/bin/"

    # Instalar el archivo .desktop para el lanzador de la aplicación
    install -Dm644 "$srcdir/linux/rateme.desktop" "$pkgdir/usr/share/applications/rateme.desktop"
}
