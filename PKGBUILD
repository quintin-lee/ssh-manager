pkgname="ssh-manager"
pkgver="0.2"
pkgrel=1
pkgdesc="Manager ssh connection in your terminal!"
arch=("any")
license=("custom")
depends=("expect")

source=(
    "bin/config.sh"
    "bin/connect.sh"
    "bin/login.exp"
    "bin/parse_yaml.sh"
    "conf/conf.yml")
sha512sums=(
"SKIP"
"SKIP"
"SKIP"
"SKIP"
"SKIP")

package() {
    mkdir -p "${pkgdir}/usr/local/ssh-manager/bin"
    mkdir -p "${pkgdir}/usr/local/ssh-manager/conf"
    mkdir -p "${pkgdir}/usr/local/bin"
    cp "${srcdir}/bin/*" "${pkgdir}/usr/local/ssh-manager/bin"
    cp "${srcdir}/conf/*" "${pkgdir}/usr/local/ssh-manager/conf"
    ln -sf "/usr/local/ssh-manager/bin/connect.sh" "${pkgdir}/usr/local/bin/ssh-connect"
    chmod +x "${pkgdir}/usr/local/ssh-manager/ssh-connect"
    chmod +x "${pkgdir}/usr/local/ssh-manager/login.exp"
}

