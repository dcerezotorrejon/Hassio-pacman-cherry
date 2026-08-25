#!/usr/bin/env bash
set -euo pipefail

# Cargar variables globales
source /env.sh

BUILDER_SCRIPT="/builder.sh"
SLEEP_SECONDS=$((POLL_INTERVAL * 60))

# Crear estructura de directorios inicial
mkdir -p "$REPO_DIR" "$BUILDS_DIR" /var/tmp/makepkg
chown -R builder:builder "$BUILDS_DIR" "$REPO_DIR" /var/tmp/makepkg

bashio::log.info "Bucle de sincronización activado. Intervalo: $POLL_INTERVAL minutos."

while true; do
    # Asegurar servidor web Caddy
    if ! pgrep -x "caddy" > /dev/null; then
        bashio::log.info "Iniciando servidor web Caddy en puerto ${PORT:-8034}..."
        caddy file-server --listen ":${PORT:-8034}" --root "$REPO_DIR" --browse > /dev/null 2>&1 &
        sleep 2
    fi

    # Ejecutar compilación
    if ! "$BUILDER_SCRIPT"; then
        bashio::log.error "Builder falló durante la ejecución."
    else
        bashio::log.info "Builder completado con éxito."
    fi

    bashio::log.info "Esperando $POLL_INTERVAL minutos para la siguiente comprobación..."
    sleep "$SLEEP_SECONDS"
done