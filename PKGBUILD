# Maintainer: ALi3naTEd0 <ALi3naTEd0@protonmail.com>
pkgname=rateme
pkgver=0.0.9
pkgrel=5
pkgdesc="Rate Me!"
arch=('x86_64')
url="https://github.com/ALi3naTEd0/RateMe"
license=('GPL3')
depends=('gtk3' 'libappindicator-gtk3' 'libxkbcommon' 'hicolor-icon-theme')
makedepends=('git')
options=('!lto')
source=(
  "git+https://github.com/ALi3naTEd0/RateMe.git#tag=v${pkgver}-${pkgrel}"
)
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
}

package() {
  cd "$srcdir/RateMe"

  install -Dm755 "build/linux/release/bundle/rateme" "$pkgdir/usr/bin/rateme"
  install -Dm644 "linux/rateme.desktop" "$pkgdir/usr/share/applications/rateme.desktop"
}
