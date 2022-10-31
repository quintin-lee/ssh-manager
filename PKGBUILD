pkgname="ssh-manager"
pkgver="0.1"
pkgrel=1
pkgdesc="Manager ssh connection in your terminal!"
arch=("any")
license=("custom")
depends=("expect")

source=("connect.sh" "login.exp" "host.conf")
sha512sums=("SKIP" "SKIP" "SKIP")

package() {
    mkdir -p "${pkgdir}/usr/local/ssh-manager"
    mkdir -p "${pkgdir}/usr/local/bin"
    sed -i '1!d' "${srcdir}/host.conf"
    cp "${srcdir}/connect.sh" "${pkgdir}/usr/local/ssh-manager/ssh-connect"
    cp "${srcdir}/login.exp" "${pkgdir}/usr/local/ssh-manager/login.exp"
    cp "${srcdir}/host.conf" "${pkgdir}/usr/local/ssh-manager/host.conf"
    ln -sf "/usr/local/ssh-manager/ssh-connect" "${pkgdir}/usr/local/bin/ssh-connect"
    chmod +x "${pkgdir}/usr/local/ssh-manager/ssh-connect"
    chmod +x "${pkgdir}/usr/local/ssh-manager/login.exp"
}

