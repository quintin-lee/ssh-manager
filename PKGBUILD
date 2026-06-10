# Maintainer: quintin <quintin@example.com>
pkgname="ssh-manager"
pkgver="$(cat VERSION 2>/dev/null || echo "0.2")"
pkgrel=4  # 升级版本号
pkgdesc="Manager ssh connection in your terminal!"
arch=("any")
license=("MIT")
depends=("expect" "bash" "sed" "awk" "iputils" "coreutils")
optdepends=("util-linux: for additional utilities")

# 备份配置文件，避免更新时被覆盖
backup=('etc/ssh-manager/config.yaml')

source=()
sha512sums=()

# 安装前预处理：检查源文件存在性
prepare() {
    # 检查源脚本是否存在且有可执行权限
    if [[ ! -f "${startdir}/bin/sshm.sh" ]]; then
        echo "错误：找不到主脚本文件 ${startdir}/bin/sshm.sh"
        return 1
    fi
    
    # 确保源脚本本身有可执行权限（打包前检查）
    if [[ ! -x "${startdir}/bin/sshm.sh" ]]; then
        echo "警告：源脚本无执行权限，自动添加..."
        chmod +x "${startdir}/bin/sshm.sh"
    fi

    if [[ ! -f "${startdir}/conf/config.yaml" ]]; then
        echo "错误：找不到默认配置文件 ${startdir}/conf/config.yaml"
        return 1
    fi
    
    if [[ ! -f "${startdir}/README.md" ]]; then
        echo "警告：找不到 README.md 文件（非必需）"
    fi
}

package() {
    mkdir -p "${pkgdir}/usr/bin"
    mkdir -p "${pkgdir}/etc/ssh-manager"
    mkdir -p "${pkgdir}/usr/share/ssh-manager"
    chmod 755 "${pkgdir}/usr/share/ssh-manager"
    mkdir -p "${pkgdir}/usr/share/doc/ssh-manager"
    mkdir -p "${pkgdir}/usr/share/licenses/ssh-manager"
    mkdir -p "${pkgdir}/usr/share/bash-completion/completions"
    mkdir -p "${pkgdir}/usr/share/zsh/site-functions"
    mkdir -p "${pkgdir}/usr/share/man/man1"

    cp "${startdir}/bin/sshm.sh" "${pkgdir}/usr/bin/sshm"
    chmod 755 "${pkgdir}/usr/bin/sshm"

    cp "${startdir}/lib/yaml_parser.sh" "${pkgdir}/usr/share/ssh-manager/yaml_parser.sh"
    chmod 644 "${pkgdir}/usr/share/ssh-manager/yaml_parser.sh"
    cp "${startdir}/VERSION" "${pkgdir}/usr/share/ssh-manager/VERSION"
    chmod 644 "${pkgdir}/usr/share/ssh-manager/VERSION"

    cp "${startdir}/completions/sshm.bash" "${pkgdir}/usr/share/bash-completion/completions/sshm"
    chmod 644 "${pkgdir}/usr/share/bash-completion/completions/sshm"
    cp "${startdir}/completions/_sshm" "${pkgdir}/usr/share/zsh/site-functions/_sshm"
    chmod 644 "${pkgdir}/usr/share/zsh/site-functions/_sshm"
    cp "${startdir}/doc/sshm.1" "${pkgdir}/usr/share/man/man1/sshm.1"
    chmod 644 "${pkgdir}/usr/share/man/man1/sshm.1"

    cp "${startdir}/conf/config.yaml" "${pkgdir}/etc/ssh-manager/config.yaml"
    chmod 644 "${pkgdir}/etc/ssh-manager/config.yaml"  # 所有人可读

    # Also provide the .default template
    cp "${startdir}/conf/config.yaml" "${pkgdir}/etc/ssh-manager/config.yaml.default"
    chmod 644 "${pkgdir}/etc/ssh-manager/config.yaml.default"  # 所有人可读

    sed -i 's#^CONF="${SSH_MANAGER_CONFIG:-config\.yaml}"#CONF="${SSH_MANAGER_CONFIG:-/etc/ssh-manager/config.yaml}"#'  ${pkgdir}/usr/bin/sshm

    if [[ -f "${startdir}/README.md" ]]; then
        cp "${startdir}/README.md" "${pkgdir}/usr/share/doc/ssh-manager/README.md"
    fi

    # 生成默认 MIT 许可证
    cat > "${pkgdir}/usr/share/licenses/ssh-manager/LICENSE" << EOF
MIT License

Copyright (c) $(date +%Y) ${pkgname} Authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

    cat > "${pkgdir}/usr/share/doc/ssh-manager/INSTALL_NOTES" << EOF
使用说明：
1.  默认配置文件路径（优先级）：
    - 环境变量 SSH_MANAGER_CONFIG 自定义路径
    - 用户级：~/.config/ssh-manager/config.yaml（推荐）
    - 系统级：/etc/ssh-manager/config.yaml（仅管理员可写）
2.  首次使用自动从系统模板创建用户配置，无需手动操作
3.  配置文件权限：chmod 600 ~/.config/ssh-manager/config.yaml（保护敏感信息）
4.  系统模板路径：/etc/ssh-manager/config.yaml.default
EOF

    # 6. 打包过程中的本地检查
    echo "==> 正在检查打包文件..."
    # 验证脚本是否可执行
    if [[ ! -x "${pkgdir}/usr/bin/sshm" ]]; then
        echo "错误：sshm 脚本没有可执行权限"
        return 1
    fi
    echo "==> 打包文件检查通过"
}

pkgver() {
    echo "${pkgver}"
}


