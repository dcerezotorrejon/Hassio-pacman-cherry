#!/usr/bin/env bash

# 1. Si estamos bajo S6 Overlay (Home Assistant), cargar variables persitentes de S6
if [ -d /var/run/s6/container_environment ]; then
    for env_file in /var/run/s6/container_environment/*; do
        [ -f "$env_file" ] || continue
        var_name=$(basename "$env_file")
        if [ -z "${!var_name:-}" ]; then
            export "$var_name"="$(cat "$env_file")"
        fi
    done
fi

# Directorios globales por defecto
export REPO_DIR="${REPO_DIR:-/data/pacman-cherry/builds}"
export BUILDS_DIR="${BUILDS_DIR:-/data/pacman-cherry/pkgbuilds-repo}"

# Cargar Bashio únicamente si estamos bajo el Supervisor de Home Assistant
if [ -n "${SUPERVISOR_TOKEN:-}" ] && [ -f /usr/lib/bashio/bashio.sh ]; then
    source /usr/lib/bashio/bashio.sh
fi

# Fallback para logs si Bashio no está cargado (Portainer / Docker)
if ! type bashio::log.info &>/dev/null; then
    bashio::log.info()    { echo "[INFO] $*"; }
    bashio::log.error()   { echo "[ERROR] $*" >&2; }
    bashio::log.warning() { echo "[WARNING] $*"; }
    bashio::log.debug()   { echo "[DEBUG] $*"; }
fi

# Selector de configuración: Entorno Docker > Bashio Config > Default
get_config_value() {
    local env_var="$1"
    local bashio_key="$2"
    local default_val="$3"

    # 1. Portainer / Docker CLI (Variables de entorno)
    if [ -n "${!env_var:-}" ]; then
        echo "${!env_var}"
        return
    fi

    # 2. Home Assistant Add-on (Opciones UI)
    if type bashio::config &>/dev/null && bashio::config.has_value "$bashio_key" 2>/dev/null; then
        local val
        val="$(bashio::config "$bashio_key" 2>/dev/null || true)"
        if [ -n "$val" ]; then
            echo "$val"
            return
        fi
    fi

    # 3. Fallback
    echo "$default_val"
}

# Asignar y exportar variables globales
export PKGBUILD_REPO_URL="$(get_config_value 'PKGBUILD_REPO_URL' 'pkgbuild_repo_url' '')"
export POLL_INTERVAL="$(get_config_value 'POLL_INTERVAL' 'poll_interval' '30')"
export LOG_LEVEL="$(get_config_value 'LOG_LEVEL' 'log_level' 'info')"
export PORT="$(get_config_value 'PORT' 'port' '8034')"

# Validaciones
if [ -z "$PKGBUILD_REPO_URL" ]; then
    bashio::log.error "Missing PKGBUILD_REPO_URL – set via env var or config."
    exit 1
fi

if ! [[ "$POLL_INTERVAL" =~ ^[0-9]+$ ]]; then
    bashio::log.error "Invalid POLL_INTERVAL: must be numeric"
    exit 1
fi