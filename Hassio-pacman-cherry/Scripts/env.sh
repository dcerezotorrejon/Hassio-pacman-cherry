#!/usr/bin/env bash

# Directorios globales
export REPO_DIR="/data/pacman-cherry/builds"
export BUILDS_DIR="/data/pacman-cherry/pkgbuilds-repo"

# Configuración con soporte para variables de entorno directas y fallback a bashio::config
export PKGBUILD_REPO_URL="${PKGBUILD_REPO_URL:-$(bashio::config 'pkgbuild_repo_url' 2>/dev/null || echo '')}"
export POLL_INTERVAL="${POLL_INTERVAL:-$(bashio::config 'poll_interval' 2>/dev/null || echo '30')}"
export LOG_LEVEL="${LOG_LEVEL:-$(bashio::config 'log_level' 2>/dev/null || echo 'info')}"
export PORT="${PORT:-8034}"

# Fallback para funciones de bashio si no se está ejecutando bajo Home Assistant Supervisor
if ! type bashio::log.info &>/dev/null || [ -z "${SUPERVISOR_TOKEN:-}" ]; then
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
        es}
    }
fi