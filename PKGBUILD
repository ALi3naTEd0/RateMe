# Maintainer: ALi3naTEd0 <ALi3naTEd0@protonmail.com>
pkgname=rateme
pkgver=0.0.9
pkgrel=5
pkgdesc="Rate Me!"
arch=('x86_64')
url="https://github.com/ALi3naTEd0/RateMe"
license=('GPL3')
depends=('gtk3' 'libappindicator-gtk3' 'libxkbcommon' 'hicolor-icon-theme')
makedepends=('flutter' 'clang')
source=("git+https://github.com/ALi3naTEd0/RateMe.git#tag=v${pkgver}")
sha256sums=('SKIP')

build() {
  cd "$srcdir/RateMe"
  flutter build linux --release
}

package() {
  cd "$srcdir/RateMe"
  install -Dm755 "build/linux/release/bundle/rateme" "$pkgdir/usr/bin/rateme"
  install -Dm644 "linux/rateme.desktop" "$pkgdir/usr/share/applications/rateme.desktop"
  # Install icon if available
  if [ -f "assets/icon.png" ]; then
    install -Dm644 "assets/icon.png" "$pkgdir/usr/share/icons/hicolor/256x256/apps/rateme.png"
  fi
}
