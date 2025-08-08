#!/usr/bin/env bash

# Idempotent installation of OpenJDK 17 (headless) on Debian/Ubuntu
# and non-interactive selection of Java 17 as the default via update-alternatives.
#
# Usage:
#   sudo ./install_java_dependencies.sh

set -Eeuo pipefail

log() { echo "[$(date -Is)] $*"; }
die() { echo "[$(date -Is)] ERROR: $*" >&2; exit 1; }

# Must run as root
if [[ "$(id -u)" -ne 0 ]]; then
  die "This script must be run as root. Use: sudo $0"
fi

export DEBIAN_FRONTEND=noninteractive

# Detect distro (Ubuntu/Debian)
[[ -r /etc/os-release ]] || die "/etc/os-release not found; unsupported distribution"
. /etc/os-release
OS_ID="${ID:-}"
case "${OS_ID}" in
  ubuntu|debian) ;;
  *) die "Unsupported distribution: ${OS_ID}. Only Ubuntu/Debian are supported." ;;
esac

# Ensure apt is available
command -v apt-get >/dev/null 2>&1 || die "apt-get not found. This script supports apt-based systems only."

PACKAGE="openjdk-17-jdk-headless"

log "Updating apt package index..."
apt-get update -y

if dpkg -s "${PACKAGE}" >/dev/null 2>&1; then
  INSTALLED_VERSION="$(dpkg-query -W -f='${Version}\n' "${PACKAGE}" 2>/dev/null || true)"
  log "${PACKAGE} is already installed (version: ${INSTALLED_VERSION})"
else
  log "Installing ${PACKAGE}..."
  apt-get install -y "${PACKAGE}"
  log "Installed ${PACKAGE} successfully."
fi

# Resolve the JDK 17 bin directory robustly
resolve_jdk17_bin_dir() {
  local bin_dir
  # Preferred: query dpkg file list
  bin_dir="$(dpkg -L "${PACKAGE}" 2>/dev/null | grep -E '/usr/lib/jvm/.*/bin/javac$' | head -n1 || true)"
  if [[ -n "${bin_dir}" ]]; then
    dirname "${bin_dir}"
    return 0
  fi
  # Fallback: search common JVM locations
  local candidate
  candidate="$(find /usr/lib/jvm -maxdepth 1 -type d \( -name 'java-17-*' -o -name 'jdk-17*' -o -name 'java-1.17.0-*' \) 2>/dev/null | head -n1 || true)"
  if [[ -n "${candidate}" && -x "${candidate}/bin/javac" ]]; then
    echo "${candidate}/bin"
    return 0
  fi
  return 1
}

JDK_BIN_DIR="$(resolve_jdk17_bin_dir || true)"
[[ -n "${JDK_BIN_DIR}" ]] || die "Could not determine JDK 17 bin directory after installation."
[[ -x "${JDK_BIN_DIR}/java" ]] || die "Missing java executable at ${JDK_BIN_DIR}/java"
[[ -x "${JDK_BIN_DIR}/javac" ]] || die "Missing javac executable at ${JDK_BIN_DIR}/javac"

JAVA_TARGET="${JDK_BIN_DIR}/java"
JAVAC_TARGET="${JDK_BIN_DIR}/javac"

# Ensure an alternative exists and set it non-interactively
ensure_and_set_alternative() {
  local name="$1" link="/usr/bin/$1" target="$2" priority="1711"
  if update-alternatives --list "${name}" >/dev/null 2>&1; then
    # Register target if missing
    if ! update-alternatives --list "${name}" | grep -Fxq "${target}"; then
      log "Registering ${name} alternative: ${target}"
      update-alternatives --install "${link}" "${name}" "${target}" "${priority}"
    fi
  else
    log "Creating ${name} alternatives group with target ${target}"
    update-alternatives --install "${link}" "${name}" "${target}" "${priority}"
  fi
  log "Setting ${name} alternative to ${target}"
  update-alternatives --set "${name}" "${target}"
}

ensure_and_set_alternative java  "${JAVA_TARGET}"
ensure_and_set_alternative javac "${JAVAC_TARGET}"

# Verify selected version is Java 17
JAVA_VERSION_STR="$(java -version 2>&1 | head -n1 || true)"
JAVAC_VERSION_STR="$(javac -version 2>&1 | head -n1 || true)"

if ! echo "${JAVA_VERSION_STR}" | grep -q '"17'; then
  die "java -version is not 17 after update-alternatives. Output: ${JAVA_VERSION_STR}"
fi
if ! echo "${JAVAC_VERSION_STR}" | grep -q 'javac 17'; then
  die "javac -version is not 17 after update-alternatives. Output: ${JAVAC_VERSION_STR}"
fi

log "Java default updated successfully. $(command -v java) -> ${JAVA_VERSION_STR}"
log "Javac default updated successfully. $(command -v javac) -> ${JAVAC_VERSION_STR}"

# Optionally export JAVA_HOME for login shells
JAVA_HOME_DIR="$(dirname "${JDK_BIN_DIR}")"
PROFILE_SNIPPET="/etc/profile.d/java17.sh"
if [[ ! -f "${PROFILE_SNIPPET}" ]]; then
  log "Creating ${PROFILE_SNIPPET} to export JAVA_HOME"
  cat > "${PROFILE_SNIPPET}" <<EOF
export JAVA_HOME="${JAVA_HOME_DIR}"
export PATH="\${JAVA_HOME}/bin:\${PATH}"
EOF
  chmod 0644 "${PROFILE_SNIPPET}"
else
  log "${PROFILE_SNIPPET} already exists; leaving as-is"
fi

log "OpenJDK 17 installation and configuration completed successfully."


