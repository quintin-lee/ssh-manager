#!/usr/bin/env bash
set -e

# Resolve Project Root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
APP_NAME="ssh-manager"
APP_VERSION=$(cat "${PROJECT_ROOT}/VERSION" 2>/dev/null || echo "0.2")
RELEASE="1"
ARCH="all"
DESCRIPTION="Manager ssh connection in your terminal!"
LICENSE="MIT"
MAINTAINER="quintin <quintin@example.com>"

# Directories
BUILD_DIR="${PROJECT_ROOT}/build"
STAGING_DIR="${BUILD_DIR}/stage"
OUTPUT_DIR="${PROJECT_ROOT}/dist"

# Clean previous builds
rm -rf "${BUILD_DIR}"
mkdir -p "${STAGING_DIR}"
mkdir -p "${OUTPUT_DIR}"

# -----------------------------------------------------------------------------
# System Detection
# -----------------------------------------------------------------------------
OS_TYPE="generic"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        debian|ubuntu|kali|raspbian) OS_TYPE="debian" ;;
        centos|fedora|rhel|rocky|almalinux) OS_TYPE="redhat" ;;
        arch|manjaro) OS_TYPE="arch" ;;
        *) 
            # Check ID_LIKE
            if [[ "$ID_LIKE" =~ "debian" ]]; then OS_TYPE="debian";
            elif [[ "$ID_LIKE" =~ "rhel" || "$ID_LIKE" =~ "fedora" ]]; then OS_TYPE="redhat";
            fi
            ;;
    esac
fi

echo "Detected System Type: $OS_TYPE"
echo "Starting build process for ${APP_NAME} v${APP_VERSION}..."

# -----------------------------------------------------------------------------
# 1. Prepare Staging Area
# -----------------------------------------------------------------------------
echo "Preparing staging area..."
mkdir -p "${STAGING_DIR}/usr/bin"
mkdir -p "${STAGING_DIR}/etc/ssh-manager"
mkdir -p "${STAGING_DIR}/usr/share/ssh-manager"
mkdir -p "${STAGING_DIR}/usr/share/doc/${APP_NAME}"
mkdir -p "${STAGING_DIR}/usr/share/licenses/${APP_NAME}"
mkdir -p "${STAGING_DIR}/usr/share/bash-completion/completions"
mkdir -p "${STAGING_DIR}/usr/share/zsh/site-functions"
mkdir -p "${STAGING_DIR}/usr/share/man/man1"

cp "${PROJECT_ROOT}/bin/sshm.sh" "${STAGING_DIR}/usr/bin/sshm"
chmod 755 "${STAGING_DIR}/usr/bin/sshm"
cp "${PROJECT_ROOT}/lib/yaml_parser.sh" "${STAGING_DIR}/usr/share/ssh-manager/yaml_parser.sh"
chmod 644 "${STAGING_DIR}/usr/share/ssh-manager/yaml_parser.sh"
cp "${PROJECT_ROOT}/completions/sshm.bash" "${STAGING_DIR}/usr/share/bash-completion/completions/sshm"
cp "${PROJECT_ROOT}/completions/_sshm" "${STAGING_DIR}/usr/share/zsh/site-functions/_sshm"
cp "${PROJECT_ROOT}/doc/sshm.1" "${STAGING_DIR}/usr/share/man/man1/sshm.1"
cp "${PROJECT_ROOT}/conf/config.yaml" "${STAGING_DIR}/etc/ssh-manager/config.yaml"
chmod 644 "${STAGING_DIR}/etc/ssh-manager/config.yaml"
cp "${PROJECT_ROOT}/conf/config.yaml" "${STAGING_DIR}/etc/ssh-manager/config.yaml.default"
chmod 644 "${STAGING_DIR}/etc/ssh-manager/config.yaml.default"

sed -i 's#CONF="${SSH_MANAGER_CONFIG:-config\.yaml}"#CONF="${SSH_MANAGER_CONFIG:-/etc/ssh-manager/config.yaml}"#' "${STAGING_DIR}/usr/bin/sshm"

[ -f "${PROJECT_ROOT}/README.md" ] && cp "${PROJECT_ROOT}/README.md" "${STAGING_DIR}/usr/share/doc/${APP_NAME}/README.md"

cat > "${STAGING_DIR}/usr/share/licenses/${APP_NAME}/LICENSE" << EOF
MIT License
Copyright (c) $(date +%Y) ${APP_NAME} Authors
EOF

# -----------------------------------------------------------------------------
# 2. Build Functions
# -----------------------------------------------------------------------------

build_deb() {
    if command -v dpkg-deb >/dev/null 2>&1; then
        echo "Building .deb package..."
        DEB_DIR="${BUILD_DIR}/deb"
        mkdir -p "${DEB_DIR}/DEBIAN"
        cp -r "${STAGING_DIR}/"* "${DEB_DIR}/"
        cat > "${DEB_DIR}/DEBIAN/control" << EOF
Package: ${APP_NAME}
Version: ${APP_VERSION}-${RELEASE}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: expect, bash, sed, gawk, iputils-ping, coreutils
Maintainer: ${MAINTAINER}
Description: ${DESCRIPTION}
EOF
        dpkg-deb --build "${DEB_DIR}" "${OUTPUT_DIR}/${APP_NAME}_${APP_VERSION}-${RELEASE}_${ARCH}.deb"
    else
        echo "Error: 'dpkg-deb' not found. Cannot build .deb package."
        return 1
    fi
}

build_rpm() {
    if command -v rpmbuild >/dev/null 2>&1; then
        echo "Building .rpm package..."
        RPM_ROOT="${BUILD_DIR}/rpmbuild"
        mkdir -p "${RPM_ROOT}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
        TAR_NAME="${APP_NAME}-${APP_VERSION}"
        mkdir -p "${RPM_ROOT}/BUILD/${TAR_NAME}"
        cp -r "${STAGING_DIR}/"* "${RPM_ROOT}/BUILD/${TAR_NAME}/"
        
        cat > "${RPM_ROOT}/SPECS/${APP_NAME}.spec" << EOF
Name:       ${APP_NAME}
Version:    ${APP_VERSION}
Release:    ${RELEASE}%{?dist}
Summary:    ${DESCRIPTION}
License:    ${LICENSE}
BuildArch:  noarch
Requires:   expect, bash, sed, gawk, iputils, coreutils
%description
${DESCRIPTION}
%install
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/etc/ssh-manager
mkdir -p %{buildroot}/usr/share/ssh-manager
cp -r ${RPM_ROOT}/BUILD/${TAR_NAME}/usr/bin/* %{buildroot}/usr/bin/
cp -r ${RPM_ROOT}/BUILD/${TAR_NAME}/etc/ssh-manager/* %{buildroot}/etc/ssh-manager/
cp -r ${RPM_ROOT}/BUILD/${TAR_NAME}/usr/share/ssh-manager/* %{buildroot}/usr/share/ssh-manager/
%files
/usr/bin/sshm
%config(noreplace) /etc/ssh-manager/config.yaml
/etc/ssh-manager/config.yaml.default
/usr/share/ssh-manager/yaml_parser.sh
/usr/share/bash-completion/completions/sshm
/usr/share/zsh/site-functions/_sshm
/usr/share/man/man1/sshm.1
EOF
        rpmbuild --define "_topdir ${RPM_ROOT}" -bb "${RPM_ROOT}/SPECS/${APP_NAME}.spec"
        find "${RPM_ROOT}/RPMS" -name "*.rpm" -exec cp {} "${OUTPUT_DIR}/" \;
    else
        echo "Error: 'rpmbuild' not found. Cannot build .rpm package."
        return 1
    fi
}

build_arch() {
    if [ -f "${PROJECT_ROOT}/PKGBUILD" ] && command -v makepkg >/dev/null 2>&1; then
        echo "Building Arch package..."
        cd "${PROJECT_ROOT}"
        makepkg -f
        mv ./*.pkg.tar.zst "${OUTPUT_DIR}/" 2>/dev/null || true
        cd - >/dev/null
    else
        echo "Skipping Arch package: PKGBUILD or makepkg not found."
    fi
}

build_tarball() {
    echo "Building generic tarball..."
    TAR_NAME="${APP_NAME}-${APP_VERSION}"
    TAR_DIR="${BUILD_DIR}/${TAR_NAME}"
    mkdir -p "${TAR_DIR}"
    cp -r "${STAGING_DIR}/"* "${TAR_DIR}/"
    [ -f "${PROJECT_ROOT}/install.sh" ] && cp "${PROJECT_ROOT}/install.sh" "${TAR_DIR}/install.sh"
    tar -czf "${OUTPUT_DIR}/${TAR_NAME}.tar.gz" -C "${BUILD_DIR}" "${TAR_NAME}"
}

# -----------------------------------------------------------------------------
# 3. Execution based on System Type
# -----------------------------------------------------------------------------

case "$OS_TYPE" in
    debian)
        build_deb || build_tarball
        ;;
    redhat)
        build_rpm || build_tarball
        ;;
    arch)
        build_arch || build_tarball
        ;;
    *)
        echo "Unknown or generic system. Building all available or tarball..."
        # Try building what we can, otherwise tarball
        if ! { build_deb || build_rpm; }; then
            build_tarball
        fi
        ;;
esac

echo "----------------------------------------------------------------"
echo "Build complete! Artifacts are in ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"