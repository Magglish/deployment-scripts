#!/usr/bin/env bash

# Idempotent installation of NVIDIA Container Toolkit for Ubuntu/Debian
# Docs followed: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html#with-apt-ubuntu-debian

set -Eeuo pipefail

log() { echo "[$(date -Is)] $*"; }
die() { echo "[$(date -Is)] ERROR: $*" >&2; exit 1; }

# Must run as root
if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run as root. Use: sudo $0"
fi

export DEBIAN_FRONTEND=noninteractive

# Detect distro
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

log "Target distribution: ${OS_ID} ${OS_VERSION_ID}"

# Configure NVIDIA Container Toolkit repository (with signed-by keyring)
KEYRING_FILE="/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
LIST_FILE="/etc/apt/sources.list.d/nvidia-container-toolkit.list"

if [[ ! -s "${KEYRING_FILE}" ]]; then
  log "Fetching libnvidia-container GPG key and installing keyring at ${KEYRING_FILE}..."
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o "${KEYRING_FILE}"
  chmod 0644 "${KEYRING_FILE}"
else
  log "Keyring already present at ${KEYRING_FILE}"
fi

LIST_CONTENT="$(
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed "s#deb https://#deb [signed-by=${KEYRING_FILE}] https://#g"
)"

if [[ ! -f "${LIST_FILE}" ]]; then
  log "Creating APT source list at ${LIST_FILE}"
  printf "%s\n" "${LIST_CONTENT}" > "${LIST_FILE}"
elif ! diff -q <(printf "%s\n" "${LIST_CONTENT}") "${LIST_FILE}" >/dev/null 2>&1; then
  log "Updating APT source list at ${LIST_FILE}"
  printf "%s\n" "${LIST_CONTENT}" > "${LIST_FILE}"
else
  log "APT source list already up-to-date at ${LIST_FILE}"
fi

log "Updating apt package index..."
apt-get update -y

# Always install the latest available versions from the repository
log "Installing NVIDIA Container Toolkit packages (latest available versions)"
apt-get install -y \
  nvidia-container-toolkit \
  nvidia-container-toolkit-base \
  libnvidia-container-tools \
  libnvidia-container1

# Configure Docker runtime via nvidia-ctk, if Docker is installed
if command -v nvidia-ctk >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
  log "Configuring Docker to use NVIDIA Container Runtime via nvidia-ctk..."
  if nvidia-ctk runtime configure --runtime=docker; then
    if systemctl list-unit-files | grep -q '^docker\.service'; then
      log "Restarting Docker daemon"
      systemctl restart docker || log "Could not restart docker via systemd; please restart Docker manually."
    else
      log "Docker systemd service not found; please restart Docker manually if needed."
    fi
  else
    log "nvidia-ctk runtime configuration returned non-zero exit code; check logs and configure manually if needed."
  fi
else
  log "Skipping Docker runtime configuration (nvidia-ctk or docker not found)."
fi

log "NVIDIA Container Toolkit installation completed successfully."


