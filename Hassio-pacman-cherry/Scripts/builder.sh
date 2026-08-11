#!/usr/bin/with-contenv bashio

REPO_DIR="/share/pacman-repo"
BUILDS_DIR="/tmp/custom-AUR"

# Leer URL del repositorio desde la interfaz web de Home Assistant
PKGBUILD_REPO_URL=$(bashio::config 'pkgbuild_repo_url')

bashio::log.info "Iniciando servicio Pacman Cherry Repo (Base Arch Linux nativa)..."

mkdir -p "$REPO_DIR" "$BUILDS_DIR"
chown -R builder:builder "$BUILDS_DIR" "$REPO_DIR"

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
    su builder -c "git clone '$PKGBUILD_REPO_URL' '$BUILDS_DIR'"
    HAS_GIT_CHANGES=true
else
    bashio::log.info "Comprobando actualizaciones en el repositorio Git..."
    su builder -c "git -C '$BUILDS_DIR' fetch origin"
    LOCAL_HASH=$(su builder -c "git -C '$BUILDS_DIR' rev-parse HEAD")
    REMOTE_HASH=$(su builder -c "git -C '$BUILDS_DIR' rev-parse origin/main")

    if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
        bashio::log.info "Nuevos commits detectados. Actualizando repositorio local..."
        su builder -c "git -C '$BUILDS_DIR' pull"
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
# Usar Process Substitution (< <(...)) para evitar subshell en el while
while read -r pkg_file; do
    [ -n "$pkg_file" ] || continue

    pkg_dir=$(dirname "$pkg_file")
    pkg_name=$(basename "$pkg_dir")

    chown -R builder:builder "$pkg_dir"

    pkg_version=$(su builder -c "cd '$pkg_dir' && makepkg --printsrcinfo" | awk '/pkgver =/ {ver=$3} /pkgrel =/ {rel=$3} END {print ver "-" rel}')
    target_pkg="${pkg_name}-${pkg_version}-x86_64.pkg.tar.zst"
    target_any="${pkg_name}-${pkg_version}-any.pkg.tar.zst"

    if [ -f "$REPO_DIR/$target_pkg" ] || [ -f "$REPO_DIR/$target_any" ]; then
        bashio::log.info "Omite $pkg_name: La versión $pkg_version ya está en $REPO_DIR."
        continue
    fi

    bashio::log.info "Compilando nueva versión de $pkg_name ($pkg_version)..."

    if su builder -c "cd '$pkg_dir' && makepkg -s --noconfirm --needed"; then
        bashio::log.info "Compilación exitosa: $pkg_name"
        find "$pkg_dir" -maxdepth 1 -name "*.pkg.tar.zst" -exec cp {} "$REPO_DIR/" \;
        # Limpiar carpeta de trabajo del paquete tras compilar
        su builder -c "cd '$pkg_dir' && makepkg -c --noconfirm" 2>/dev/null
    else
        bashio::log.error "Fallo al compilar el paquete: $pkg_name"
    fi
done < <(find "$BUILDS_DIR" -maxdepth 2 -name "PKGBUILD")

# ==========================================
# 3. REGENERAR BASE DE DATOS Y ENLACES HTTP
# ==========================================
cd "$REPO_DIR" || exit 1

# Usar nullglob para comprobar de forma segura si hay paquetes .pkg.tar.zst
shopt -s nullglob
PACKAGES=(*.pkg.tar.zst)
shopt -u nullglob

if [ ${#PACKAGES[@]} -gt 0 ]; then
    bashio::log.info "Actualizando base de datos pacman-cherry.db y enlaces simbólicos..."

    rm -f pacman-cherry.db* pacman-cherry.files*

    # Ejecutar repo-add de forma segura pasando el array de paquetes
    su builder -c "repo-add -n -R pacman-cherry.db.tar.gz ${PACKAGES[*]}"

    ln -sf pacman-cherry.db.tar.gz pacman-cherry.db
    ln -sf pacman-cherry.files.tar.gz pacman-cherry.files
else
    bashio::log.warning "No se encontraron archivos .pkg.tar.zst en $REPO_DIR. Se omite la generación del repositorio."
fi

# Limpieza de caché de pacman
yes | pacman -Scc 2>/dev/null || true

bashio::log.info "Sincronización finalizada con éxito."