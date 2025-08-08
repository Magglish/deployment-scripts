#!/usr/bin/env bash

# Idempotent CUDA Toolkit installation for Ubuntu/Debian using NVIDIA's APT repository
# References:
# - Ubuntu: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/#ubuntu
# - Debian: https://docs.nvidia.com/cuda/cuda-installation-guide-linux/#debian

set -Eeuo pipefail

log() { echo "[$(date -Is)] $*"; }
die() { echo "[$(date -Is)] ERROR: $*" >&2; exit 1; }

# Must run as root
if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run as root. Use: sudo $0"
fi

export DEBIAN_FRONTEND=noninteractive

KEYRING_DIR="/etc/apt/keyrings"
KEY_FILE="${KEYRING_DIR}/cuda-archive-keyring.gpg"
SHARE_KEYRING_DIR="/usr/share/keyrings"

# Detect distro and version
[[ -r /etc/os-release ]] || die "/etc/os-release not found; unsupported distribution"
. /etc/os-release

OS_ID="${ID:-}"
OS_VERSION_ID="${VERSION_ID:-}"
[[ -n "${OS_ID}" ]] || die "Cannot detect distribution ID"
[[ -n "${OS_VERSION_ID}" ]] || die "Cannot detect distribution version"

case "${OS_ID}" in
  ubuntu|debian) ;;
  *) die "Unsupported distribution: ${OS_ID}. Only Ubuntu/Debian are supported." ;;
esac

# Enforce x86_64 only
DEB_ARCH="$(dpkg --print-architecture)"
if [[ "${DEB_ARCH}" != "amd64" ]]; then
  die "Unsupported architecture: ${DEB_ARCH}. This installer supports x86_64 (amd64) only."
fi
NVIDIA_ARCH="x86_64"

# Build convenience strings
OS_VERSION_COMPACT="${OS_VERSION_ID//./}"
OS_VERSION_MAJOR="${OS_VERSION_ID%%.*}"
DIST_STRING="${OS_ID}${OS_VERSION_COMPACT}"

log "Target distribution: ${OS_ID} ${OS_VERSION_ID} (${DIST_STRING}), arch: ${DEB_ARCH} (NVIDIA: ${NVIDIA_ARCH})"


# Install CUDA 12.4 repository via local installer package
install -d -m 0755 "${SHARE_KEYRING_DIR}"

case "${OS_ID}" in
  debian)
    case "${OS_VERSION_MAJOR}" in
      12|11|10) ;;
      *) die "Unsupported Debian version: ${OS_VERSION_ID}. Supported: 12, 11, 10." ;;
    esac

    LOCAL_REPO_PKG="cuda-repo-debian${OS_VERSION_MAJOR}-12-4-local"
    REPO_DEB="${LOCAL_REPO_PKG}_12.4.0-550.54.14-1_amd64.deb"
    REPO_URL_DEB="https://developer.download.nvidia.com/compute/cuda/12.4.0/local_installers/${REPO_DEB}"
    TMP_DEB="/tmp/${REPO_DEB}"

    if dpkg -s "${LOCAL_REPO_PKG}" >/dev/null 2>&1; then
      log "${LOCAL_REPO_PKG} already installed; skipping download."
    else
      log "Downloading local CUDA repo installer: ${REPO_URL_DEB}"
      curl -fL --retry 3 --retry-delay 2 -o "${TMP_DEB}" "${REPO_URL_DEB}"
      log "Installing local CUDA repo: ${REPO_DEB}"
      dpkg -i "${TMP_DEB}" || die "Failed to install ${REPO_DEB}"
    fi

    LOCAL_REPO_DIR="/var/cuda-repo-debian${OS_VERSION_MAJOR}-12-4-local"
    if compgen -G "${LOCAL_REPO_DIR}/cuda-*-keyring.gpg" > /dev/null; then
      cp "${LOCAL_REPO_DIR}/cuda-"*-"-keyring.gpg" "${SHARE_KEYRING_DIR}/"
    else
      die "CUDA keyring not found in ${LOCAL_REPO_DIR}"
    fi

    if ! command -v add-apt-repository >/dev/null 2>&1; then
      log "Installing software-properties-common to enable add-apt-repository..."
      apt-get update -y
      apt-get install -y software-properties-common
    fi
    log "Ensuring 'contrib' component is enabled..."
    add-apt-repository -y contrib || true
    ;;

  ubuntu)
    case "${OS_VERSION_COMPACT}" in
      2204|2004) ;;
      *) die "Unsupported Ubuntu version: ${OS_VERSION_ID}. Supported: 22.04, 20.04." ;;
    esac

    PIN_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${OS_VERSION_COMPACT}/${NVIDIA_ARCH}/cuda-ubuntu${OS_VERSION_COMPACT}.pin"
    PIN_DST="/etc/apt/preferences.d/cuda-repository-pin-600"
    TMP_PIN="/tmp/cuda-ubuntu${OS_VERSION_COMPACT}.pin"
    log "Downloading CUDA APT pin: ${PIN_URL}"
    curl -fL --retry 3 --retry-delay 2 -o "${TMP_PIN}" "${PIN_URL}"
    mv "${TMP_PIN}" "${PIN_DST}"

    LOCAL_REPO_PKG="cuda-repo-ubuntu${OS_VERSION_COMPACT}-12-4-local"
    REPO_DEB="${LOCAL_REPO_PKG}_12.4.0-550.54.14-1_amd64.deb"
    REPO_URL_DEB="https://developer.download.nvidia.com/compute/cuda/12.4.0/local_installers/${REPO_DEB}"
    TMP_DEB="/tmp/${REPO_DEB}"

    if dpkg -s "${LOCAL_REPO_PKG}" >/dev/null 2>&1; then
      log "${LOCAL_REPO_PKG} already installed; skipping download."
    else
      log "Downloading local CUDA repo installer: ${REPO_URL_DEB}"
      curl -fL --retry 3 --retry-delay 2 -o "${TMP_DEB}" "${REPO_URL_DEB}"
      log "Installing local CUDA repo: ${REPO_DEB}"
      dpkg -i "${TMP_DEB}" || die "Failed to install ${REPO_DEB}"
    fi

    LOCAL_REPO_DIR="/var/cuda-repo-ubuntu${OS_VERSION_COMPACT}-12-4-local"
    if compgen -G "${LOCAL_REPO_DIR}/cuda-*-keyring.gpg" > /dev/null; then
      cp "${LOCAL_REPO_DIR}/cuda-"*-"-keyring.gpg" "${SHARE_KEYRING_DIR}/"
    else
      die "CUDA keyring not found in ${LOCAL_REPO_DIR}"
    fi
    ;;
esac

log "Updating apt package index..."
apt-get update -y

# Always install fixed CUDA Toolkit version 12.4 (no arguments accepted)
REQUESTED_VERSION="12-4"
PACKAGE="cuda-toolkit-${REQUESTED_VERSION}"

log "Planned package to install: ${PACKAGE}"

# Install package only if not already present
if dpkg -s "${PACKAGE}" >/dev/null 2>&1; then
  INSTALLED_VERSION="$(dpkg-query -W -f='${Version}\n' "${PACKAGE}" 2>/dev/null || true)"
  log "${PACKAGE} is already installed (version: ${INSTALLED_VERSION})"
else
  log "Installing ${PACKAGE}..."
  apt-get install -y "${PACKAGE}"
  log "Installed ${PACKAGE} successfully."
fi

# Ensure proprietary NVIDIA driver (datacenter) is installed, avoiding open kernel modules
# Pin open-kernel variants to prevent accidental installation
PIN_FILE="/etc/apt/preferences.d/nvidia-proprietary-only.pref"
if [[ ! -f "${PIN_FILE}" ]]; then
  log "Creating APT pin to avoid open kernel module packages (${PIN_FILE})"
  cat > "${PIN_FILE}" <<'EOF'
Package: nvidia-driver-*-open
Pin: release *
Pin-Priority: -1

Package: nvidia-kernel-open-dkms
Pin: release *
Pin-Priority: -1
EOF
fi

log "Updating apt package index (after pinning)..."
apt-get update -y

# Ensure kernel headers for DKMS are present
KERN_VER="$(uname -r)"
if ! dpkg -s "linux-headers-${KERN_VER}" >/dev/null 2>&1; then
  log "Installing kernel headers for DKMS: linux-headers-${KERN_VER}"
  if ! apt-get install -y "linux-headers-${KERN_VER}"; then
    log "Could not install linux-headers-${KERN_VER}. Continuing, assuming headers are available via meta-packages."
  fi
fi

# Install NVIDIA proprietary driver via CUDA repo meta-package
DRIVER_META="cuda-drivers"
if dpkg -s "${DRIVER_META}" >/dev/null 2>&1 || command -v nvidia-smi >/dev/null 2>&1; then
  log "NVIDIA driver already present (cuda-drivers or nvidia-smi)."
else
  log "Installing NVIDIA proprietary driver via ${DRIVER_META}..."
  apt-get install -y "${DRIVER_META}"
  log "Installed NVIDIA driver (${DRIVER_META}). A reboot is recommended."
fi

log "CUDA installation script completed successfully."


