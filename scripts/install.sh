#!/usr/bin/env bash
set -euo pipefail

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# 清理函数
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "安装过程中发生错误，退出码: $exit_code"
    fi
    exit $exit_code
}

# 捕获信号
trap cleanup EXIT SIGINT SIGTERM

# 版本和包名称
VERSION=$(cat "VERSION" 2>/dev/null || echo "0.2")
PKG_NAME="ssh-manager"

# 默认安装路径
DEFAULT_BIN_PATH="/usr/local/bin/sshm"
DEFAULT_CONF_DIR="/etc/ssh-manager"
DEFAULT_DOC_PATH="/usr/local/share/doc/$PKG_NAME"
DEFAULT_LICENSE_PATH="/usr/local/share/licenses/$PKG_NAME"
DEFAULT_LIB_PATH="/usr/local/share/ssh-manager"

# 允许通过环境变量自定义安装路径
BIN_PATH="${INSTALL_PATH:-$DEFAULT_BIN_PATH}"
CONF_DIR="${CONFIG_DIR:-$DEFAULT_CONF_DIR}"
DOC_PATH="${DOC_DIR:-$DEFAULT_DOC_PATH}"
LICENSE_PATH="${LICENSE_DIR:-$DEFAULT_LICENSE_PATH}"
LIB_PATH="${LIB_DIR:-$DEFAULT_LIB_PATH}"
CONF_TEMPLATE_PATH="$CONF_DIR/config.yaml.example"

log_info "SSH Manager $VERSION 安装脚本开始执行"

# 检查是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
    log_error "需要以 root 权限运行（使用 sudo）"
    exit 1
fi

# 检查依赖
check_dependency() {
    local cmd="$1"
    local package_name="$2"

    if ! command -v "$cmd" &>/dev/null; then
        log_error "缺少依赖: $cmd"
        if [ -n "$package_name" ]; then
            log_info "请先安装 $package_name 包，例如:"
            if [[ "$package_name" == "iputils" ]]; then
                log_info "  Debian/Ubuntu: sudo apt-get install ${package_name}-ping"
            else
                log_info "  Debian/Ubuntu: sudo apt-get install ${package_name}"
            fi
            log_info "  CentOS/RHEL:   sudo yum install $package_name 或 sudo dnf install $package_name"
            log_info "  Arch Linux:    sudo pacman -S $package_name"
            log_info "  macOS:         brew install $package_name"
        else
            log_info "请先安装 $cmd 命令然后重新运行此脚本"
        fi
        exit 1
    fi

    local cmd_version
    cmd_version=$(get_command_version "$cmd" 2>/dev/null || echo "未知版本")
    log_info "找到依赖: $cmd ($cmd_version)"
}

# 获取命令版本的辅助函数
get_command_version() {
    local cmd="$1"
    case "$cmd" in
        bash)
            echo "${BASH_VERSION:-unknown}"
            ;;
        expect)
            expect -version 2>/dev/null | head -n1
            ;;
        sed|awk|ping)
            "$cmd" --version 2>/dev/null | head -n1 | cut -d' ' -f1,2,3
            ;;
        base64|cp|mkdir|chmod|rm)
            # 对于这些基本命令，通常不显示详细版本
            echo "系统工具"
            ;;
        *)
            "$cmd" --version 2>/dev/null | head -n1
            ;;
    esac
}

log_info "检查依赖项..."

# 检查核心依赖及其对应的包名
check_dependency expect expect
check_dependency bash bash
check_dependency sed sed
check_dependency awk gawk
check_dependency ping iputils  # 或者 inetutils-ping 取决于发行版
check_dependency base64 coreutils
check_dependency cp coreutils
check_dependency mkdir coreutils
check_dependency chmod coreutils
check_dependency rm coreutils

log_info "所有依赖项检查完成"

# 验证源文件是否存在
if [[ ! -f "bin/sshm.sh" ]]; then
    log_error "源文件 bin/sshm.sh 不存在"
    exit 1
fi

log_info "验证源文件存在"

# 备份现有安装
backup_existing_installation() {
    if [[ -f "$BIN_PATH" ]]; then
        log_warn "检测到现有的安装，正在创建备份"
        cp "$BIN_PATH" "$BIN_PATH.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        log_info "已备份现有二进制文件到 $BIN_PATH.bak.timestamp"
    fi

    if [[ -f "$CONF_TEMPLATE_PATH" ]]; then
        cp "$CONF_TEMPLATE_PATH" "$CONF_TEMPLATE_PATH.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        log_info "已备份现有配置模板"
    fi
}

backup_existing_installation

# 创建目录
log_info "创建目录结构..."
mkdir -p "$CONF_DIR"
mkdir -p "$(dirname "$DOC_PATH")"
mkdir -p "$(dirname "$LICENSE_PATH")"
mkdir -p "$LIB_PATH"

# 安装主程序
log_info "安装主程序..."
if cp "bin/sshm.sh" "$BIN_PATH"; then
    if chmod 755 "$BIN_PATH"; then
        log_success "主程序已成功安装到 $BIN_PATH"
    else
        log_error "设置执行权限失败"
        exit 1
    fi
else
    log_error "复制主程序失败"
    exit 1
fi

# 安装库文件
log_info "安装库文件..."
if [ -f "lib/yaml_parser.sh" ]; then
    if cp "lib/yaml_parser.sh" "$LIB_PATH/yaml_parser.sh"; then
        chmod 644 "$LIB_PATH/yaml_parser.sh"
        log_success "库文件已安装到 $LIB_PATH/yaml_parser.sh"
    else
        log_error "复制库文件失败"
        exit 1
    fi
else
    log_warn "库文件 lib/yaml_parser.sh 不存在，跳过"
fi

# 安装 Shell 补全
if [ -f "completions/sshm.bash" ]; then
    log_info "安装 bash 补全..."
    mkdir -p /usr/share/bash-completion/completions
    cp completions/sshm.bash /usr/share/bash-completion/completions/sshm
    chmod 644 /usr/share/bash-completion/completions/sshm
fi
if [ -f "completions/_sshm" ]; then
    log_info "安装 zsh 补全..."
    mkdir -p /usr/share/zsh/site-functions
    cp completions/_sshm /usr/share/zsh/site-functions/_sshm
    chmod 644 /usr/share/zsh/site-functions/_sshm
fi

# 安装配置模板
log_info "安装配置模板..."
if echo "nodes:" > "$CONF_TEMPLATE_PATH"; then
    if chmod 644 "$CONF_TEMPLATE_PATH"; then
        log_success "配置模板已安装到 $CONF_TEMPLATE_PATH"
    else
        log_error "设置配置模板权限失败"
        exit 1
    fi
else
    log_error "创建配置模板失败"
    exit 1
fi

# 安装文档
log_info "安装文档..."
mkdir -p "$DOC_PATH"
if cat > "$DOC_PATH/INSTALL_NOTES" << EOF
SSH Manager $VERSION 安装说明
=============================
1. 运行命令：sshm
2. 默认配置路径：~/.config/ssh-manager/config.yaml（自动创建）
3. 系统配置模板：$CONF_TEMPLATE_PATH
4. 卸载命令：sudo ssh-manager-uninstall
EOF
then
    log_success "安装说明已写入 $DOC_PATH/INSTALL_NOTES"
else
    log_error "写入安装说明失败"
    exit 1
fi

# 安装许可证
log_info "安装许可证..."
mkdir -p "$LICENSE_PATH"
if cat > "$LICENSE_PATH/LICENSE" << EOF
MIT License

Copyright (c) 2026 $PKG_NAME Authors

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
then
    log_success "许可证已写入 $LICENSE_PATH/LICENSE"
else
    log_error "写入许可证失败"
    exit 1
fi

# 创建卸载脚本
log_info "创建卸载脚本..."
if cat > /usr/local/bin/ssh-manager-uninstall << EOF
#!/usr/bin/env bash
set -euo pipefail

# 设置颜色输出
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
NC='\\033[0m' # No Color

log_info() {
    echo -e "\${BLUE}[INFO]\${NC} \$1"
}

log_success() {
    echo -e "\${GREEN}[SUCCESS]\${NC} \$1"
}

log_warn() {
    echo -e "\${YELLOW}[WARNING]\${NC} \$1"
}

log_error() {
    echo -e "\${RED}[ERROR]\${NC} \$1" >&2
}

# 检查是否为 root 用户
if [ "\$(id -u)" -ne 0 ]; then
    log_error "错误：需要以 root 权限运行"
    exit 1
fi

# 确认卸载
read -p "确定要卸载 SSH Manager 吗？(y/N): " confirm
if [[ ! "\$confirm" =~ ^[Yy]$ ]]; then
    log_info "取消卸载"
    exit 0
fi

# 停止可能正在运行的服务或进程
log_info "停止可能的相关进程..."
pkill -f "sshm" 2>/dev/null || true

# 删除主要文件
if rm -f "$BIN_PATH"; then
    log_success "已删除主程序 $(basename "$BIN_PATH")"
else
    log_warn "删除主程序失败或文件不存在"
fi

# 删除卸载脚本本身
if rm -f /usr/local/bin/ssh-manager-uninstall; then
    log_success "已删除卸载脚本"
else
    log_warn "删除卸载脚本失败或文件不存在"
fi

# 删除库文件
if rm -f "$LIB_PATH/yaml_parser.sh" 2>/dev/null; then
    log_success "已删除库文件"
fi
rmdir "$LIB_PATH" 2>/dev/null || true

# 删除补全文件
rm -f /usr/share/bash-completion/completions/sshm 2>/dev/null
rm -f /usr/share/zsh/site-functions/_sshm 2>/dev/null

# 删除配置目录（如果为空）
if [ -d "$CONF_DIR" ]; then
    if rmdir "$CONF_DIR" 2>/dev/null; then
        log_success "已删除空配置目录 $CONF_DIR"
    else
        log_warn "配置目录 $CONF_DIR 不为空，保留以保护用户配置。如需完全清理，请手动删除。"
    fi
fi

# 删除文档和许可证目录
if rm -rf "$(dirname "$DOC_PATH")"; then
    log_success "已删除文档目录"
fi

if rm -rf "$(dirname "$LICENSE_PATH")"; then
    log_success "已删除许可证目录"
fi

# 提示用户保留的配置文件
log_info "注意：用户配置文件 ~/.config/ssh-manager/ 未删除（包含敏感信息）"
log_success "SSH Manager 已成功卸载"
EOF
then
    if chmod 755 /usr/local/bin/ssh-manager-uninstall; then
        log_success "卸载脚本已安装并设置权限"
    else
        log_error "设置卸载脚本权限失败"
        exit 1
    fi
else
    log_error "创建卸载脚本失败"
    exit 1
fi

log_success "=== 安装完成 ==="
log_info "运行命令：sshm"
log_info "卸载命令：sudo ssh-manager-uninstall"
log_info "配置模板位置：$CONF_TEMPLATE_PATH"
