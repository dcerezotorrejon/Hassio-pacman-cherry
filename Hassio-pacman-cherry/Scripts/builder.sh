#!/usr/bin/with-contenv bashio

# Cargar variables de entorno globales
source /env.sh

IS_STARTUP=false
HAS_GIT_CHANGES=false

# 1. Comprobar estado de la base de datos y repositorio Git
if [ ! -f "$REPO_DIR/pacman-cherry.db" ]; then
    IS_STARTUP=true
    bashio::log.info "Ejecución inicial detectada: Se generará la base de datos de paquetes."
fi

if [ ! -d "$BUILDS_DIR/.git" ]; then
    bashio::log.info "Clonando repositorio de PKGBUILDs..."
    su builder -s /bin/bash -c "git clone '$PKGBUILD_REPO_URL' '$BUILDS_DIR'"
    HAS_GIT_CHANGES=true
else
    bashio::log.info "Comprobando actualizaciones en el repositorio Git..."
    su builder -s /bin/bash -c "git -C '$BUILDS_DIR' fetch origin"
    LOCAL_HASH=$(su builder -s /bin/bash -c "git -C '$BUILDS_DIR' rev-parse HEAD")
    REMOTE_HASH=$(su builder -s /bin/bash -c "git -C '$BUILDS_DIR' rev-parse '@{u}'")

    if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
        bashio::log.info "Nuevos commits detectados. Actualizando repositorio local..."
        su builder -s /bin/bash -c "git -C '$BUILDS_DIR' pull"
        HAS_GIT_CHANGES=true
    fi
fi

# 2. Ciclo de compilación
if [ "$IS_STARTUP" = true ] || [ "$HAS_GIT_CHANGES" = true ]; then

    while read -r pkg_file; do
        [ -n "$pkg_file" ] || continue

        pkg_dir=$(dirname "$pkg_file")
        pkg_name=$(basename "$pkg_dir")

        chown -R builder:builder "$pkg_dir"

        pkg_version=$(su builder -s /bin/bash -c "cd '$pkg_dir' && makepkg --printsrcinfo" | awk '/pkgver =/ {ver=$3} /pkgrel =/ {rel=$3} END {print ver "-" rel}')
        target_pkg="${pkg_name}-${pkg_version}-x86_64.pkg.tar.zst"
        target_any="${pkg_name}-${pkg_version}-any.pkg.tar.zst"

        if [ -f "$REPO_DIR/$target_pkg" ] || [ -f "$REPO_DIR/$target_any" ]; then
            bashio::log.info "Omite $pkg_name: La versión $pkg_version ya está en $REPO_DIR."
            continue
        fi

        bashio::log.info "Compilando nueva versión de $pkg_name ($pkg_version)..."

        if su builder -s /bin/bash -c "cd '$pkg_dir' && makepkg -s --noconfirm --needed"; then
            bashio::log.info "Compilación exitosa: $pkg_name"
            find "$pkg_dir" -maxdepth 1 -name "*.pkg.tar.zst" ! -name "*-debug-*.pkg.tar.zst" -exec mv {} "$REPO_DIR/" \;
            chown -R builder:builder "$REPO_DIR"

            su builder -s /bin/bash -c "cd '$pkg_dir' && makepkg -c --noconfirm" 2>/dev/null
        else
            bashio::log.error "Fallo al compilar el paquete: $pkg_name"
        fi
    done < <(find "$BUILDS_DIR" -maxdepth 2 -name "PKGBUILD")

    # 3. Regeneración de la base de datos de Pacman
    cd "$REPO_DIR" || exit 1
    chown -R builder:builder "$REPO_DIR"

    shopt -s nullglob
    PACKAGES=(*.pkg.tar.zst)
    shopt -u nullglob

    if [ ${#PACKAGES[@]} -gt 0 ]; then
        bashio::log.info "Actualizando base de datos pacman-cherry.db..."
        su builder -s /bin/bash -c "cd '$REPO_DIR' && repo-add -n -R pacman-cherry.db.tar.gz *.pkg.tar.zst"

        ln -sf pacman-cherry.db.tar.gz pacman-cherry.db
        ln -sf pacman-cherry.files.tar.gz pacman-cherry.files

        chmod 644 pacman-cherry.* *.pkg.tar.zst 2>/dev/null || true
        bashio::log.info "Base de datos y servidor HTTP sincronizados."
    else
        bashio::log.warning "No se encontraron archivos .pkg.tar.zst en $REPO_DIR. Se omite repo-add."
    fi

    # Limpieza de carpetas temporales
    find "$BUILDS_DIR" -type d \( -name "src" -o -name "pkg" \) -exec rm -rf {} + 2>/dev/null || true
    rm -rf /var/tmp/makepkg/* 2>/dev/null || true
    yes | pacman -Scc 2>/dev/null || true

    bashio::log.info "Sincronización finalizada con éxito."
else
    bashio::log.info "Sin cambios en Git. Repositorio al día."
fi