#!/usr/bin/env bash

# Install essential system packages for Debian

set -euo pipefail

log() { echo "[$(date -Is)] $*"; }
die() { echo "[$(date -Is)] ERROR: $*" >&2; exit 1; }

# Check if running as root
if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run as root. Use: sudo $0"
fi

export DEBIAN_FRONTEND=noninteractive

log "Installing essential system packages..."
apt-get update -y 
apt-get install -y \
  build-essential \
  software-properties-common \
  gcc \
  libc6-dev \
  curl \
  ca-certificates \
  gnupg \
  git

log "System packages installation completed successfully."

