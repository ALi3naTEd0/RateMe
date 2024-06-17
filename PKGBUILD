# Maintainer: ALi3naTEd0 <ALi3naTEd0@protonmail.com>
pkgname=rateme
pkgver=0.0.9
pkgrel=5
pkgdesc="Rate Me!"
arch=('x86_64')
url="https://github.com/ALi3naTEd0/RateMe"
license=('GPL3')
depends=('gtk3' 'libappindicator-gtk3' 'libxkbcommon' 'hicolor-icon-theme' 'flutter')  # Dependencies necessary for execution on the user's system, including flutter from AUR
makedepends=('git')  # Dependency to clone application repository
source=("git+https://github.com/ALi3naTEd0/RateMe.git#tag=v${pkgver}")

# Flutter dependency from AUR
depends=('flutter')

build() {
  cd "$srcdir/RateMe"
  
  flutter build linux --release
}

package() {
  cd "$srcdir/RateMe"
  
  # Install the application files
  install -Dm755 "build/linux/release/bundle/rateme" "$pkgdir/usr/bin/rateme"
  install -Dm644 "linux/rateme.desktop" "$pkgdir/usr/share/applications/rateme.desktop"
  
  # Install icon if available
  if [ -f "assets/icon.png" ]; then
    install -Dm644 "assets/icon.png" "$pkgdir/usr/share/icons/hicolor/256x256/apps/rateme.png"
  fi
}

