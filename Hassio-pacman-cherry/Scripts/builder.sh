#!/usr/bin/with-contenv bashio

REPO_DIR="/share/pacman-repo"
BUILDS_DIR="/tmp/custom-AUR"

# Leer URL del repositorio desde la interfaz web de Home Assistant
PKGBUILD_REPO_URL=$(bashio::config 'pkgbuild_repo_url')

bashio::log.info "Iniciando servicio Pacman Cherry Repo (Base Arch Linux nativa)..."

mkdir -p "$REPO_DIR" "$BUILDS_DIR"
chown -R builder:builder "$BUILDS_DIR"

# Configurar e iniciar Caddy en segundo plano para servir HTTP en el puerto 8034
if ! pgrep -x "caddy" > /dev/null; then
    bashio::log.info "Iniciando servidor web Caddy en puerto 8034..."
    caddy file-server --listen :8034 --root "$REPO_DIR" --browse &
fi

# ==========================================
# 1. GESTIÓN DE GIT Y ESTADO DE STARTUP
# ==========================================
IS_STARTUP=false
HAS_GIT_CHANGES=false

if [ ! -f "$REPO_DIR/pacman-cherry.db" ]; then
    IS_STARTUP=true
    bashio::log.info "Ejecución inicial detectada: Se generará la base de datos de paquetes."
fi

if [ ! -d "$BUILDS_DIR/.git" ]; then
    bashio::log.info "Clonando repositorio de PKGBUILDs..."
    git clone "$PKGBUILD_REPO_URL" "$BUILDS_DIR"
    HAS_GIT_CHANGES=true
else
    bashio::log.info "Comprobando actualizaciones en el repositorio Git..."
    git -C "$BUILDS_DIR" fetch origin
    LOCAL_HASH=$(git -C "$BUILDS_DIR" rev-parse HEAD)
    REMOTE_HASH=$(git -C "$BUILDS_DIR" rev-parse origin/main)

    if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
        bashio::log.info "Nuevos commits detectados. Actualizando repositorio local..."
        git -C "$BUILDS_DIR" pull
        HAS_GIT_CHANGES=true
    fi
fi

if [ "$IS_STARTUP" = false ] && [ "$HAS_GIT_CHANGES" = false ]; then
    bashio::log.info "Sin cambios en Git. Fin del ciclo de comprobación."
    exit 0
fi

# ==========================================
# 2. COMPILACIÓN DIRECTA CON MAKEPKG
# ==========================================
find "$BUILDS_DIR" -maxdepth 2 -name "PKGBUILD" | while read -r pkg_file; do
    pkg_dir=$(dirname "$pkg_file")
    pkg_name=$(basename "$pkg_dir")

    chown -R builder:builder "$pkg_dir"

    pkg_version=$(su builder -c "cd '$pkg_dir' && makepkg --printsrcinfo" | awk '/pkgver =/ {ver=$3} /pkgrel =/ {rel=$3} END {print ver "-" rel}')
    target_pkg="${pkg_name}-${pkg_version}-x86_64.pkg.tar.zst"
    target_any="${pkg_name}-${pkg_version}-any.pkg.tar.zst"

    if [ -f "$REPO_DIR/$target_pkg" ] || [ -f "$REPO_DIR/$target_any" ]; then
        bashio::log.info "Omite $pkg_name: La versión $pkg_version ya está compilada en /share."
        continue
    fi

    bashio::log.info "Compilando nueva versión de $pkg_name ($pkg_version)..."

    if su builder -c "cd '$pkg_dir' && makepkg -s --noconfirm --needed"; then
        bashio::log.info "Compilación exitosa: $pkg_name"
        find "$pkg_dir" -name "*.pkg.tar.zst" -exec cp {} "$REPO_DIR/" \;
    else
        bashio::log.error "Fallo al compilar el paquete: $pkg_name"
    fi
done

# ==========================================
# 3. REGENERAR BASE DE DATOS Y ENLACES HTTP
# ==========================================
bashio::log.info "Actualizando base de datos pacman-cherry.db y enlaces simbólicos..."
cd "$REPO_DIR" || exit 1

rm -f pacman-cherry.db* pacman-cherry.files*

repo-add pacman-cherry.db.tar.gz *.pkg.tar.zst

ln -sf pacman-cherry.db.tar.gz pacman-cherry.db
ln -sf pacman-cherry.files.tar.gz pacman-cherry.files

# Limpieza de paquetes huérfanos o temporales
yes | pacman -Scc 2>/dev/null || true

bashio::log.info "Sincronización finalizada con éxito."