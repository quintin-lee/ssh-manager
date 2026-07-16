#!/usr/bin/env bash
# ============================================================================
# build_makeself.sh — Build self-extracting .run installer via makeself
#
# Usage:
#   ./scripts/build_makeself.sh       # Generate ssh-manager-<ver>.run
#
# Workflow:
#   1. Prepare payload directory    — copy bin/, lib/, conf/, completions/, doc/
#   2. Embed install script         — install.sh runs after extraction
#   3. Package with makeself        — output single .run executable
#
# Output:
#   ssh-manager-<version>.run       (self-extracting installer, project root)
#
# Dependencies: makeself
# ============================================================================

set -e

# Resolve Project Root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# App name derived from project directory
# Build configuration (values used in output naming)
VERSION=$(cat "${PROJECT_ROOT}/VERSION" 2>/dev/null || echo "0.2")
BUILD_DIR="${PROJECT_ROOT}/build/makeself"
PAYLOAD_DIR="${BUILD_DIR}/payload"
OUTPUT_FILE="${PROJECT_ROOT}/ssh-manager-${VERSION}.run"

# 1. Clean and Prepare Staging Directory
rm -rf "${BUILD_DIR}" 2>/dev/null || true
mkdir -p "${PAYLOAD_DIR}"

echo "Preparing payload..."

# 2. Copy Application Files
# We maintain the directory structure inside the payload for clarity
mkdir -p "${PAYLOAD_DIR}/bin"
mkdir -p "${PAYLOAD_DIR}/conf"
mkdir -p "${PAYLOAD_DIR}/lib"
mkdir -p "${PAYLOAD_DIR}/doc"
mkdir -p "${PAYLOAD_DIR}/completions"

cp "${PROJECT_ROOT}/bin/sshm.sh" "${PAYLOAD_DIR}/bin/sshm"
cp "${PROJECT_ROOT}/conf/config.yaml" "${PAYLOAD_DIR}/conf/config.yaml"
for _f in yaml_parser.sh yaml_ops.sh config.sh util.sh ssh.sh node_cmd.sh tui.sh; do
    cp "${PROJECT_ROOT}/lib/${_f}" "${PAYLOAD_DIR}/lib/${_f}"
done
cp "${PROJECT_ROOT}/lib/ssh_connect.tcl" "${PAYLOAD_DIR}/lib/ssh_connect.tcl"
cp "${PROJECT_ROOT}/VERSION" "${PAYLOAD_DIR}/VERSION"
cp "${PROJECT_ROOT}/completions/sshm.bash" "${PAYLOAD_DIR}/completions/sshm.bash"
cp "${PROJECT_ROOT}/completions/_sshm" "${PAYLOAD_DIR}/completions/_sshm"
[ -f "${PROJECT_ROOT}/README.md" ] && cp "${PROJECT_ROOT}/README.md" "${PAYLOAD_DIR}/doc/README.md"

# 3. Create the Internal Install Script
# This script runs *after* extraction, inside the temporary directory
cat > "${PAYLOAD_DIR}/install.sh" << 'EOF'
#!/usr/bin/env bash
set -e

sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Define installation paths
INSTALL_BIN="/usr/local/bin/sshm"
INSTALL_CONF_DIR="/etc/ssh-manager"
INSTALL_DOC_DIR="/usr/local/share/doc/ssh-manager"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Installing SSH Manager...${NC}"

# Check for root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# 1. Install Binary
echo "Installing binary to ${INSTALL_BIN}..."
cp bin/sshm "${INSTALL_BIN}"
chmod 755 "${INSTALL_BIN}"

# Update config path in the installed script to point to /etc/ssh-manager/config.yaml
sed_i 's#^CONF="${SSH_MANAGER_CONFIG:-config\.yaml}"#CONF="${SSH_MANAGER_CONFIG:-/etc/ssh-manager/config.yaml}"#' "${INSTALL_BIN}"

# Install library
echo "Installing library..."
INSTALL_LIB_DIR="/usr/local/share/ssh-manager"
mkdir -p "${INSTALL_LIB_DIR}"
chmod 755 "${INSTALL_LIB_DIR}" 2>/dev/null || true
for _f in yaml_parser.sh yaml_ops.sh config.sh util.sh ssh.sh node_cmd.sh tui.sh; do
    cp "lib/${_f}" "${INSTALL_LIB_DIR}/${_f}"
    chmod 644 "${INSTALL_LIB_DIR}/${_f}"
done
cp lib/ssh_connect.tcl "${INSTALL_LIB_DIR}/ssh_connect.tcl"
chmod 644 "${INSTALL_LIB_DIR}/ssh_connect.tcl"
cp VERSION "${INSTALL_LIB_DIR}/VERSION"
chmod 644 "${INSTALL_LIB_DIR}/VERSION"

# Also install to /usr/share for compatibility with .deb lookups
mkdir -p /usr/share/ssh-manager
chmod 755 /usr/share/ssh-manager 2>/dev/null || true
for _f in yaml_parser.sh yaml_ops.sh config.sh util.sh ssh.sh node_cmd.sh tui.sh; do
    cp "lib/${_f}" /usr/share/ssh-manager/"${_f}"
    chmod 644 /usr/share/ssh-manager/"${_f}"
done
cp lib/ssh_connect.tcl /usr/share/ssh-manager/ssh_connect.tcl
chmod 644 /usr/share/ssh-manager/ssh_connect.tcl

mkdir -p /usr/local/lib 2>/dev/null || true
cp lib/yaml_parser.sh /usr/local/lib/yaml_parser.sh 2>/dev/null || true
chmod 644 /usr/local/lib/yaml_parser.sh 2>/dev/null || true
for _f in yaml_ops.sh config.sh util.sh ssh.sh node_cmd.sh tui.sh; do
    cp "lib/${_f}" /usr/local/lib/"${_f}" 2>/dev/null || true
    chmod 644 /usr/local/lib/"${_f}" 2>/dev/null || true
done
cp lib/ssh_connect.tcl /usr/local/lib/ssh_connect.tcl 2>/dev/null || true
chmod 644 /usr/local/lib/ssh_connect.tcl 2>/dev/null || true

# Install completions
echo "Installing shell completions..."
if [ -f completions/sshm.bash ]; then
    mkdir -p /usr/share/bash-completion/completions
    cp completions/sshm.bash /usr/share/bash-completion/completions/sshm
    chmod 644 /usr/share/bash-completion/completions/sshm
fi
if [ -f completions/_sshm ]; then
    mkdir -p /usr/share/zsh/site-functions
    cp completions/_sshm /usr/share/zsh/site-functions/_sshm
    chmod 644 /usr/share/zsh/site-functions/_sshm
fi

# Verify library files were installed correctly
_verify_lib() {
    local f="$1"
    if [ ! -f "/usr/local/share/ssh-manager/${f}" ] && [ ! -f "/usr/share/ssh-manager/${f}" ]; then
        echo "ERROR: Failed to install ${f}"
        ls -la /usr/local/share/ssh-manager/ 2>/dev/null || true
        ls -la /usr/share/ssh-manager/ 2>/dev/null || true
        exit 1
    fi
}
for _f in yaml_parser.sh yaml_ops.sh config.sh util.sh ssh.sh node_cmd.sh tui.sh ssh_connect.tcl; do
    _verify_lib "${_f}"
done
_verify_lib "VERSION"
echo "All library files and VERSION verified OK"

# 2. Install Config
echo "Installing configuration..."
mkdir -p "${INSTALL_CONF_DIR}"

# Install default config if not present
if [ ! -f "${INSTALL_CONF_DIR}/config.yaml" ]; then
    cp conf/config.yaml "${INSTALL_CONF_DIR}/config.yaml"
    chmod 644 "${INSTALL_CONF_DIR}/config.yaml"
    echo "Created default config at ${INSTALL_CONF_DIR}/config.yaml"
else
    echo "Config file already exists, skipping overwrite."
fi

# Always provide a .default reference
cp conf/config.yaml "${INSTALL_CONF_DIR}/config.yaml.default"
chmod 644 "${INSTALL_CONF_DIR}/config.yaml.default"

# 3. Install Documentation
if [ -d doc ]; then
    echo "Installing documentation..."
    mkdir -p "${INSTALL_DOC_DIR}"
    cp -r doc/* "${INSTALL_DOC_DIR}/"
fi

# 4. Create Uninstaller
        cat > /usr/local/bin/sshm-uninstall << UNINSTALL_EOF
#!/usr/bin/env bash
if [ "\$(id -u)" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi
rm -f ${INSTALL_BIN}
for _f in yaml_parser.sh yaml_ops.sh config.sh util.sh ssh.sh node_cmd.sh tui.sh ssh_connect.tcl; do
    rm -f "${INSTALL_LIB_DIR}/${_f}"
    rm -f "/usr/share/ssh-manager/${_f}"
done
rm -f ${INSTALL_LIB_DIR}/VERSION
rm -f /usr/share/ssh-manager/VERSION
rmdir ${INSTALL_LIB_DIR} 2>/dev/null || true
rmdir /usr/share/ssh-manager 2>/dev/null || true
rm -f /usr/share/bash-completion/completions/sshm
rm -f /usr/share/zsh/site-functions/_sshm
rm -f /usr/local/bin/sshm-uninstall
# Optional: remove config dir?
# rm -rf ${INSTALL_CONF_DIR}
echo "SSH Manager uninstalled."
UNINSTALL_EOF
chmod 755 /usr/local/bin/sshm-uninstall

echo -e "${GREEN}Installation Complete!${NC}"
echo "Run 'sshm' to start."
EOF

chmod +x "${PAYLOAD_DIR}/install.sh"
chmod +x "${PAYLOAD_DIR}/bin/sshm"

# 4. Generate the Self-Extracting Archive using makeself
echo "Generating installer..."

# Syntax: makeself [args] archive_dir file_name label startup_script [script_args]
makeself --notemp \
    "${PAYLOAD_DIR}" \
    "${OUTPUT_FILE}" \
    "SSH Manager v${VERSION} Installer" \
    ./install.sh

echo "----------------------------------------------------"
echo "Successfully created: ${OUTPUT_FILE}"
echo "To install, run: sudo ./${OUTPUT_FILE}"
