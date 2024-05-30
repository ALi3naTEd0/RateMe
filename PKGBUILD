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
    # No hay necesidad de comandos de empaquetado específicos para Flutter

    # Instalar el paquete después de crearlo
    pacman -U "RateMe-0.0.9-1-x86_64.pkg.tar.zst"
}