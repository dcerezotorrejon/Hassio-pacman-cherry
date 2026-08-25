#!/usr/bin/env bash

# Directorios globales
export REPO_DIR="${REPO_DIR:-/data/pacman-cherry/builds}"
export BUILDS_DIR="${BUILDS_DIR:-/data/pacman-cherry/pkgbuilds-repo}"

# Cargar bashio solo si estamos en Home Assistant Supervisor y existe el token
if [ -n "${SUPERVISOR_TOKEN:-}" ] && [ -f /usr/lib/bashio/bashio.sh ]; then
    source /usr/lib/bashio/bashio.sh
fi

# Fallback robusto para funciones de bashio si no están definidas (standalone docker o sin supervisor)
if ! type bashio::log.info &>/dev/null; then
    bashio::log.info() { echo "[INFO] $*"; }
    bashio::log.error() { echo "[ERROR] $*" >&2; }
    bashio::log.warning() { echo "[WARNING] $*"; }
    bashio::log.debug() { echo "[DEBUG] $*"; }
fi

if ! type bashio::config &>/dev/null; then
    bashio::config() {
        local key="$1"
        local default="$2"
        case "$key" in
            pkgbuild_repo_url) echo "${PKGBUILD_REPO_URL:-$default}" ;;
            poll_interval) echo "${POLL_INTERVAL:-$default}" ;;
            log_level) echo "${LOG_LEVEL:-$default}" ;;
            *) echo "$default" ;;
        esac
    }
fi

# Configuración con soporte para variables de entorno directas y fallback a bashio::config
export PKGBUILD_REPO_URL="${PKGBUILD_REPO_URL:-$(bashio::config 'pkgbuild_repo_url' 2>/dev/null || echo '')}"
export POLL_INTERVAL="${POLL_INTERVAL:-$(bashio::config 'poll_interval' 2>/dev/null || echo '30')}"
export LOG_LEVEL="${LOG_LEVEL:-$(bashio::config 'log_level' 2>/dev/null || echo 'info')}"
export PORT="${PORT:-8034}"

# Validate required environment variables
if [ -z "$PKGBUILD_REPO_URL" ]; then
    bashio::log.error "Missing PKGBUILD_REPO_URL – set via env var or config."
    exit 1
fi

if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]]; then
    bashio::log.error "Invalid POLL_INTERVAL: must be numeric"
    exit 1
fi
