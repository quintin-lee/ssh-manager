#!/usr/bin/env bash
set -e

# Resolve Project Root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

APP_NAME="ssh-manager"
VERSION=$(cat "${PROJECT_ROOT}/VERSION" 2>/dev/null || echo "0.2")
BUILD_DIR="${PROJECT_ROOT}/build/makeself"
PAYLOAD_DIR="${BUILD_DIR}/payload"
OUTPUT_FILE="${PROJECT_ROOT}/ssh-manager-${VERSION}.run"

# 1. Clean and Prepare Staging Directory
rm -rf "${BUILD_DIR}"
mkdir -p "${PAYLOAD_DIR}"

echo "Preparing payload..."

# 2. Copy Application Files
# We maintain the directory structure inside the payload for clarity
mkdir -p "${PAYLOAD_DIR}/bin"
mkdir -p "${PAYLOAD_DIR}/conf"
mkdir -p "${PAYLOAD_DIR}/doc"

cp "${PROJECT_ROOT}/bin/sshm.sh" "${PAYLOAD_DIR}/bin/sshm"
cp "${PROJECT_ROOT}/conf/config.yaml" "${PAYLOAD_DIR}/conf/config.yaml"
[ -f "${PROJECT_ROOT}/README.md" ] && cp "${PROJECT_ROOT}/README.md" "${PAYLOAD_DIR}/doc/README.md"

# 3. Create the Internal Install Script
# This script runs *after* extraction, inside the temporary directory
cat > "${PAYLOAD_DIR}/install.sh" << 'EOF'
#!/usr/bin/env bash
set -e

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
sed -i 's#CONF="${SSH_MANAGER_CONFIG:-config.yaml}"#CONF="${SSH_MANAGER_CONFIG:-/etc/ssh-manager/config.yaml}"#' "${INSTALL_BIN}"

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
