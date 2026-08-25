#!/usr/bin/env bash
set -e

# Si estamos dentro de Home Assistant (Supervisor activo), delegamos en S6 Overlay
if [ -n "${SUPERVISOR_TOKEN:-}" ] && [ -x /init ]; then
    exec /init "$@"
fi

# Si estamos en Docker puro / Portainer, ejecutamos directamente el script principal
exec /run.sh "$@"