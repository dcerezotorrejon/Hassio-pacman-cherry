#!/usr/bin/with-contenv bashio

# Cargar variables de entorno globales
source /env.sh

POLL_INTERVAL=$(bashio::config 'poll_interval' 30)
SLEEP_SECONDS=$((POLL_INTERVAL * 60))

# Crear estructura de directorios inicial
mkdir -p "$REPO_DIR" "$BUILDS_DIR" /var/tmp/makepkg
chown -R builder:builder "$BUILDS_DIR" "$REPO_DIR" /var/tmp/makepkg

bashio::log.info "Bucle de sincronización activado. Intervalo: $POLL_INTERVAL minutos."

while true; do
    # Asegurar que Caddy se mantenga en ejecución
    if ! pgrep -x "caddy" > /dev/null; then
        bashio::log.info "Iniciando servidor web Caddy en puerto 8034..."
        caddy file-server --listen :8034 --root "$REPO_DIR" --browse > /dev/null 2>&1 &
        sleep 2
    fi

    # Ejecutar compilación en subproceso
    /builder.sh || bashio::log.warning "Ocurrió un aviso o error en el ciclo de compilación."

    bashio::log.info "Esperando $POLL_INTERVAL minutos para la siguiente comprobación..."
    sleep "$SLEEP_SECONDS"
done