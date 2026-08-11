#!/usr/bin/with-contenv bashio

REPO_DIR="/share/pacman-repo"
mkdir -p "$REPO_DIR"

# Leer intervalo en minutos (por defecto 30)
POLL_INTERVAL=$(bashio::config 'poll_interval' 30)
SLEEP_SECONDS=$((POLL_INTERVAL * 60))

bashio::log.info "Iniciando servidor web Caddy en puerto 8034..."
caddy file-server --listen :8034 --root "$REPO_DIR" --browse &

bashio::log.info "Bucle de sincronización activado. Intervalo: $POLL_INTERVAL minutos."

# Bucle infinito de comprobación
while true; do
    /builder.sh || bashio::log.warning "Ocurrió un error en el ciclo de compilación."

    bashio::log.info "Esperando $POLL_INTERVAL minutos para la siguiente comprobación..."
    sleep "$SLEEP_SECONDS"
done