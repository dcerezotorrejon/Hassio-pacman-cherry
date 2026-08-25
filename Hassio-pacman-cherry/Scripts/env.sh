#!/usr/bin/env bash

# Directorios globales por defecto
export REPO_DIR="${REPO_DIR:-/data/pacman-cherry/builds}"
export BUILDS_DIR="${BUILDS_DIR:-/data/pacman-cherry/pkgbuilds-repo}"

# Cargar Bashio únicamente si estamos bajo el Supervisor de Home Assistant
if [ -n "${SUPERVISOR_TOKEN:-}" ] && [ -f /usr/lib/bashio/bashio.sh ]; then
    source /usr/lib/bashio/bashio.sh
fi

# Fallback de funciones de log si Bashio no está cargado
if ! type bashio::log.info &>/dev/null; then
    bashio::log.info()    { echo "[INFO] $*"; }
    bashio::log.error()   { echo "[ERROR] $*" >&2; }
    bashio::log.warning() { echo "[WARNING] $*"; }
    bashio::log.debug()   { echo "[DEBUG] $*"; }
fi

# Helper para priorizar variables de entorno (Docker/Portainer) y usar bashio::config como fallback (HA)
get_config_value() {
    local env_var="$1"
    local bashio_key="$2"
    local default_val="$3"

    # 1. Si la variable de entorno de Docker existe y no está vacía, usarla
    if [ -n "${!env_var:-}" ]; then
        echo "${!env_var}"
        return
    fi

    # 2. Si existe bashio::config (Home Assistant), intentar leer la opción del add-on
    if type bashio::config &>/dev/null && bashio::config.has_value "$bashio_key" 2>/dev/null; then
        bashio::config "$bashio_key" 2>/dev/null
        return
    fi

    # 3. Usar valor por defecto
    echo "$default_val"
}

# Asignación e exportación de variables globales
export PKGBUILD_REPO_URL="$(get_config_value 'PKGBUILD_REPO_URL' 'pkgbuild_repo_url' '')"
export POLL_INTERVAL="$(get_config_value 'POLL_INTERVAL' 'poll_interval' '30')"
export LOG_LEVEL="$(get_config_value 'LOG_LEVEL' 'log_level' 'info')"
export PORT="$(get_config_value 'PORT' 'port' '8034')"

# Validación de variables requeridas
if [ -z "$PKGBUILD_REPO_URL" ]; then
    bashio::log.error "Missing PKGBUILD_REPO_URL – set via env var or config."
    exit 1
fi

if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]]; then
    bashio::log.error "Invalid POLL_INTERVAL: must be numeric"
    exit 1
fi