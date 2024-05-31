pkgname="RateMe"
pkgver=0.0.9
pkgrel=1
pkgdesc="Music Rating App"
arch=('x86_64')
url="https://github.com/ALi3naTEd0/RateMe"
license=('GPL3')

source=()

build() {
    cd "$srcdir/RateMe"  # Cambiar a RateMe si ese es el nombre del directorio clonado
    # No hay necesidad de comandos de construcción específicos para Flutter
}

package() {
    cd "$srcdir/RateMe"  # Cambiar a RateMe si ese es el nombre del directorio clonado
    
    # Crear la estructura de directorios del paquete
    mkdir -p "$pkgdir/usr/bin"
    mkdir -p "$pkgdir/usr/share/applications"
    
    # Copiar los archivos de la aplicación al directorio de instalación
    cp -r "linux/"* "$pkgdir/usr/bin/"

    # Crear un enlace simbólico al ejecutable de la aplicación
    ln -s "/usr/bin/rateme" "$pkgdir/usr/bin/"

    # Instalar el archivo .desktop para el lanzador de la aplicación
    install -Dm644 "linux/rateme.desktop" "$pkgdir/usr/share/applications/rateme.desktop"
}
