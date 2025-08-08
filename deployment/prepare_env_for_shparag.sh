#!/usr/bin/env bash

set -Eeuo pipefail

log() { echo "[$(date -Is)] $*"; }
die() { echo "[$(date -Is)] ERROR: $*" >&2; exit 1; }

# Must run as root
if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run as root. Use: sudo $0"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SYS_PKGS_SCRIPT="${SCRIPT_DIR}/install_system_packages.sh"
JAVA_SCRIPT="${SCRIPT_DIR}/install_java_dependencies.sh"
DOCKER_SCRIPT="${SCRIPT_DIR}/install_docker.sh"
CUDA_SCRIPT="${SCRIPT_DIR}/install_cuda.sh"
NVIDIA_CTK_SCRIPT="${SCRIPT_DIR}/install_nvidia_container_toolkit.sh"

for f in "${SYS_PKGS_SCRIPT}" "${JAVA_SCRIPT}" "${DOCKER_SCRIPT}" "${CUDA_SCRIPT}" "${NVIDIA_CTK_SCRIPT}"; do
  [[ -f "${f}" ]] || die "Required script not found: ${f}"
done

log "============= SETTING UP ENV FOR SHPARAG =================="

log "[1/5] Installing system packages"
"${SYS_PKGS_SCRIPT}"

log "[2/5] Installing Java dependencies (OpenJDK 17)"
"${JAVA_SCRIPT}"

log "[3/5] Installing Docker Engine (latest)"
"${DOCKER_SCRIPT}"

log "[4/5] Installing CUDA Toolkit 12.4"
"${CUDA_SCRIPT}"

log "[5/5] Installing NVIDIA Container Toolkit (latest)"
"${NVIDIA_CTK_SCRIPT}"

log "============= ENV SETUP COMPLETED SUCCESSFULLY =================="
