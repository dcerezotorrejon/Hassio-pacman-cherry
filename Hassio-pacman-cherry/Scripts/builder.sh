#!/usr/bin/with-contenv bashio

REPO_DIR="/share/pacman-repo"
BUILDS_DIR="/tmp/custom-AUR"
ARCH_DIR="/opt/arch"
PKGBUILD_REPO_URL=$(bashio::config 'pkgbuild_repo_url')

# ==========================================
# 0. MONTAR SISTEMAS Y CONFIGURAR RED
# ==========================================
bashio::log.info "Verificando montajes del sistema en el chroot..."
mkdir -p "$ARCH_DIR/dev" "$ARCH_DIR/proc" "$ARCH_DIR/sys" "$ARCH_DIR/tmp" "$ARCH_DIR/etc" "$REPO_DIR"

mountpoint -q "$ARCH_DIR/dev" || mount --rbind /dev "$ARCH_DIR/dev"
mountpoint -q "$ARCH_DIR/proc" || mount -t proc proc "$ARCH_DIR/proc"
mountpoint -q "$ARCH_DIR/sys" || mount -t sysfs sysfs "$ARCH_DIR/sys"
mkdir -p "$ARCH_DIR/share/pacman-repo"
mountpoint -q "$ARCH_DIR/share/pacman-repo" || mount --bind "$REPO_DIR" "$ARCH_DIR/share/pacman-repo"

# Actualizar resolución DNS dentro del chroot
cp -L /etc/resolv.conf "$ARCH_DIR/etc/resolv.conf" 2>/dev/null || true
chmod 1777 "$ARCH_DIR/tmp"

# ==========================================
# 1. PREPARACIÓN DEL ENTORNO CHROOT (ROOT)
# ==========================================
mkdir -p "$ARCH_DIR/etc/pacman.d/gnupg"
chmod 700 "$ARCH_DIR/etc/pacman.d/gnupg"
chown -R root:root "$ARCH_DIR/etc/pacman.d/gnupg"

if [ ! -f "$ARCH_DIR/etc/pacman.d/gnupg/pubring.gpg" ]; then
    bashio::log.info "Inicializando pacman-key dentro del chroot..."
    chroot "$ARCH_DIR" pacman-key --init
    chroot "$ARCH_DIR" pacman-key --populate archlinux
fi

# Desactivar CheckSpace en pacman.conf del chroot
chroot "$ARCH_DIR" sed -i 's/^CheckSpace/#CheckSpace/' /etc/pacman.conf 2>/dev/null || true

# Garantizar herramientas esenciales y sudo sin contraseña
chroot "$ARCH_DIR" pacman -Sy --noconfirm --needed base-devel git fakeroot debugedit pacman-contrib sudo
chroot "$ARCH_DIR" sed -i 's/ OPTIONS=(\([^)]*\)debug\([^)]*\))/ OPTIONS=(\1!debug\2)/g' /etc/makepkg.conf 2>/dev/null || true

chroot "$ARCH_DIR" groupadd -g 1000 builder 2>/dev/null || true
chroot "$ARCH_DIR" useradd -u 1000 -g builder -m -s /bin/bash builder 2>/dev/null || true
mkdir -p "$ARCH_DIR/etc/sudoers.d"
echo "builder ALL=(ALL) NOPASSWD: ALL" > "$ARCH_DIR/etc/sudoers.d/builder"
chmod 440 "$ARCH_DIR/etc/sudoers.d/builder"

# ==========================================
# 2. EVALUAR CAMBIOS EN GIT Y DB
# ==========================================
IS_STARTUP=false
HAS_GIT_CHANGES=false

# Si no existe pacman-cherry.db, consideramos que es un arranque limpio / Startup
if [ ! -f "$REPO_DIR/pacman-cherry.db" ]; then
    IS_STARTUP=true
    bashio::log.info "Ejecución de startup detectada: Se garantizará la generación de la base de datos."
fi

# Clonar o actualizar repositorio Git
if [ ! -d "$BUILDS_DIR/.git" ]; then
    bashio::log.info "Clonando repositorio de PKGBUILDs..."
    git clone "$PKGBUILD_REPO_URL" "$BUILDS_DIR"
    HAS_GIT_CHANGES=true
else
    bashio::log.info "Comprobando cambios en el repositorio Git..."
    git -C "$BUILDS_DIR" fetch origin

    LOCAL_HASH=$(git -C "$BUILDS_DIR" rev-parse HEAD)
    REMOTE_HASH=$(git -C "$BUILDS_DIR" rev-parse origin/main)

    if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
        bashio::log.info "Nuevos commits detectados. Actualizando repositorio..."
        git -C "$BUILDS_DIR" pull
        HAS_GIT_CHANGES=true
    fi
fi

# En ejecuciones subsecuentes, si no hay cambios en Git ni es startup, salimos rápidamente
if [ "$IS_STARTUP" = false ] && [ "$HAS_GIT_CHANGES" = false ]; then
    bashio::log.info "Sin cambios en Git. Fin del ciclo de comprobación."
    exit 0
fi

# ==========================================
# 3. PROCESO DE COMPILACIÓN CON MAKEPKG
# ==========================================
find "$BUILDS_DIR" -maxdepth 2 -name "PKGBUILD" | while read -r pkg_file; do
    pkg_dir=$(dirname "$pkg_file")
    pkg_name=$(basename "$pkg_dir")

    work_dir="$ARCH_DIR/tmp/builds/$pkg_name"
    rm -rf "$work_dir"
    mkdir -p "$work_dir"
    cp -r "$pkg_dir"/* "$work_dir/"
    chroot "$ARCH_DIR" chown -R builder:builder "/tmp/builds/$pkg_name"

    pkg_version=$(chroot --userspec=builder:builder "$ARCH_DIR" bash -c "cd /tmp/builds/$pkg_name && makepkg --printsrcinfo" | awk '/pkgver =/ {ver=$3} /pkgrel =/ {rel=$3} END {print ver "-" rel}')

    target_pkg="${pkg_name}-${pkg_version}-x86_64.pkg.tar.zst"
    target_any="${pkg_name}-${pkg_version}-any.pkg.tar.zst"

    # Si la versión compilada ya existe en /share, omitimos compilación
    if [ -f "$REPO_DIR/$target_pkg" ] || [ -f "$REPO_DIR/$target_any" ]; then
        bashio::log.info "Omite $pkg_name: La versión $pkg_version ya existe."
        rm -rf "$work_dir"
        continue
    fi

    bashio::log.info "Compilando nueva versión de $pkg_name ($pkg_version)..."

    deps=$(chroot --userspec=builder:builder "$ARCH_DIR" bash -c "cd /tmp/builds/$pkg_name && makepkg --printsrcinfo" | awk '/depends =/ {print $3}')
    if [ -n "$deps" ]; then
        chroot "$ARCH_DIR" pacman -Sy --noconfirm --needed $deps 2>/dev/null || true
    fi

    if chroot --userspec=builder:builder "$ARCH_DIR" bash -c "cd /tmp/builds/$pkg_name && makepkg -s --noconfirm --needed"; then
        bashio::log.info "Compilación exitosa: $pkg_name"
        find "$work_dir" -name "*.pkg.tar.zst" -exec cp {} "$REPO_DIR/" \;
    else
        bashio::log.error "Fallo al compilar el paquete: $pkg_name"
    fi

    rm -rf "$work_dir"
done

# ==========================================
# 4. REGENERAR BASE DE DATOS Y ENLACES
# ==========================================
bashio::log.info "Actualizando base de datos pacman-cherry.db y enlaces simbólicos..."

# Eliminar ficheros antiguos
rm -f "$REPO_DIR"/pacman-cherry.db* "$REPO_DIR"/pacman-cherry.files*

# Generar pacman-cherry.db.tar.gz
chroot "$ARCH_DIR" bash -c "cd /share/pacman-repo && repo-add pacman-cherry.db.tar.gz *.pkg.tar.zst"

# Crear symlinks exactos
ln -sf "$REPO_DIR/pacman-cherry.db.tar.gz" "$REPO_DIR/pacman-cherry.db"
ln -sf "$REPO_DIR/pacman-cherry.files.tar.gz" "$REPO_DIR/pacman-cherry.files"

# Limpieza post-build
yes | chroot "$ARCH_DIR" pacman -Scc 2>/dev/null || true
rm -rf "$ARCH_DIR/tmp/builds/*"

bashio::log.info "Sincronización finalizada con éxito."