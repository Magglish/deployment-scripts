#!/usr/bin/env bash

# Idempotent Docker Engine installation for Debian/Ubuntu using the official APT repository
# Reference: https://docs.docker.com/engine/install/debian/#install-using-the-repository

set -Eeuo pipefail

log() { echo "[$(date -Is)] $*"; }
die() { echo "[$(date -Is)] ERROR: $*" >&2; exit 1; }

# Check if running as root
if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run as root. Use: sudo $0"
fi

export DEBIAN_FRONTEND=noninteractive

KEYRING_DIR="/etc/apt/keyrings"
KEY_FILE="${KEYRING_DIR}/docker.asc"
SOURCE_LIST_FILE="/etc/apt/sources.list.d/docker.list"

# Detect distribution and codename
[[ -r /etc/os-release ]] || die "/etc/os-release not found; unsupported distribution"
. /etc/os-release

OS_ID="${ID:-}"
OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
[[ -n "${OS_ID}" ]] || die "Cannot detect distribution ID"
[[ -n "${OS_CODENAME}" ]] || die "Cannot detect distribution codename"

case "${OS_ID}" in
  debian|ubuntu) ;;
  *) die "Unsupported distribution: ${OS_ID}. Only Debian/Ubuntu are supported." ;;
esac

ARCH="$(dpkg --print-architecture)"
REPO_URL="https://download.docker.com/linux/${OS_ID}"

# Ensure keyring directory exists with safe permissions
install -d -m 0755 "${KEYRING_DIR}"

# Install or verify Docker's GPG key (ASCII armored per Debian docs)
if [[ ! -s "${KEY_FILE}" ]]; then
  log "Fetching Docker GPG key to ${KEY_FILE}..."
  curl -fsSL "${REPO_URL}/gpg" -o "${KEY_FILE}"
  chmod 0644 "${KEY_FILE}"
else
  log "Docker GPG key already present at ${KEY_FILE}"
fi

# Configure apt source list
EXPECTED_DEB_LINE="deb [arch=${ARCH} signed-by=${KEY_FILE}] ${REPO_URL} ${OS_CODENAME} stable"
if [[ -f "${SOURCE_LIST_FILE}" ]]; then
  if grep -Fqx "${EXPECTED_DEB_LINE}" "${SOURCE_LIST_FILE}"; then
    log "Docker apt repository already configured"
  else
    log "Updating Docker apt repository entry at ${SOURCE_LIST_FILE}"
    printf "%s\n" "${EXPECTED_DEB_LINE}" > "${SOURCE_LIST_FILE}"
  fi
else
  log "Adding Docker apt repository at ${SOURCE_LIST_FILE}"
  printf "%s\n" "${EXPECTED_DEB_LINE}" > "${SOURCE_LIST_FILE}"
fi

log "Updating apt package index..."
apt-get update -y

# Install Docker packages only if docker is not already installed
if command -v docker >/dev/null 2>&1; then
  log "Docker already installed: $(docker --version)"
else
  log "Installing Docker Engine, CLI, containerd, Buildx and Compose plugin..."
  apt-get install -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  log "Installed Docker: $(docker --version)"
fi

# Ensure docker group exists
if ! getent group docker >/dev/null 2>&1; then
  groupadd -f docker
fi

# Optionally add invoking user to docker group for rootless usage
# Usage: sudo ADD_USER_TO_DOCKER_GROUP=1 ./deployment/install_docker.sh
if [[ "${ADD_USER_TO_DOCKER_GROUP:-0}" == "1" ]]; then
  INVOKER_USER="${SUDO_USER:-}"
  if [[ -n "${INVOKER_USER}" && "${INVOKER_USER}" != "root" ]]; then
    if id -nG "${INVOKER_USER}" | grep -qw docker; then
      log "User ${INVOKER_USER} is already in the docker group"
    else
      log "Adding user ${INVOKER_USER} to docker group..."
      usermod -aG docker "${INVOKER_USER}"
      log "User ${INVOKER_USER} added to docker group. Re-login required for changes to take effect."
    fi
  fi
fi

log "Docker installation script completed successfully."

