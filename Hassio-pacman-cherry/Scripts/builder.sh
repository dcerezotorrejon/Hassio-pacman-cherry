#!/usr/bin/env bash
set -euo pipefail

# Cargar variables de entorno globales
source /env.sh

IS_STARTUP=false
HAS_GIT_CHANGES=false

# 1. Comprobar estado de la base de datos de pacman
if [ ! -e "$REPO_DIR/pacman-cherry.db" ]; then
    IS_STARTUP=true
    bashio::log.info "Ejecución inicial detectada: Se generará la base de datos de paquetes."
fi

# 2. Clonar o actualizar el repositorio de PKGBUILDs
if [ ! -d "$BUILDS_DIR/.git" ]; then
    bashio::log.info "Clonando repositorio de PKGBUILDs..."
    su -s /bin/bash builder -c "git clone '$PKGBUILD_REPO_URL' '$BUILDS_DIR'"
    HAS_GIT_CHANGES=true
else
    bashio::log.info "Comprobando actualizaciones en el repositorio Git..."
    su -s /bin/bash builder -c "git -C '$BUILDS_DIR' fetch origin"
    LOCAL_HASH=$(su -s /bin/bash builder -c "git -C '$BUILDS_DIR' rev-parse HEAD")
    REMOTE_HASH=$(su -s /bin/bash builder -c "git -C '$BUILDS_DIR' rev-parse '@{u}'")
    
    if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
        bashio::log.info "Nuevos commits detectados. Actualizando repositorio local..."
        su -s /bin/bash builder -c "git -C '$BUILDS_DIR' pull"
        HAS_GIT_CHANGES=true
    fi
fi

# 3. Compilar paquetes si es primera ejecución o hubo cambios en Git
if [ "$IS_STARTUP" = true ] || [ "$HAS_GIT_CHANGES" = true ]; then
    CHANGED=0
    REMOVED=0

    pacman -Syyu --noconfirm || true

    # 3a. Construir cada PKGBUILD encontrado (usando Process Substitution seguro)
    while IFS= read -r pkg_file || [ -n "$pkg_file" ]; do
        [ -n "$pkg_file" ] || continue
        pkg_dir=$(dirname "$pkg_file")
        pkg_name=$(basename "$pkg_dir")
        chown -R builder:builder "$pkg_dir"
        
        # Obtener versión usando makepkg de forma segura
        pkg_version=$(su -s /bin/bash builder -c "cd '$pkg_dir' && makepkg --packagelist" 2>/dev/null | head -n 1 | sed -E 's/.*-([0-9a-zA-Z._]+-[0-9]+)-(x86_64|any)\.pkg\.tar\.zst/\1/' || true)

        if [ -z "$pkg_version" ]; then
            # Fallback a srcinfo si packagelist falla
            pkg_version=$(su -s /bin/bash builder -c "cd '$pkg_dir' && makepkg --printsrcinfo" 2>/dev/null | awk '/pkgver =/ {ver=$3} /pkgrel =/ {rel=$3} END {print ver "-" rel}' || true)
        fi

        target_pkg="${pkg_name}-${pkg_version}-x86_64.pkg.tar.zst"
        target_any="${pkg_name}-${pkg_version}-any.pkg.tar.zst"
        
        if [ -n "$pkg_version" ] && { [ -f "$REPO_DIR/$target_pkg" ] || [ -f "$REPO_DIR/$target_any" ]; }; then
            bashio::log.info "Omite $pkg_name: La versión $pkg_version ya está en $REPO_DIR."
            continue
        fi
        
        bashio::log.info "Compilando nueva versión de $pkg_name ($pkg_version)..."
        if su -s /bin/bash builder -c "cd '$pkg_dir' && makepkg -s --noconfirm --needed"; then
            CHANGED=1
            bashio::log.info "Compilación exitosa: $pkg_name"
            find "$pkg_dir" -maxdepth 1 -name "*.pkg.tar.zst" ! -name "*-debug-*.pkg.tar.zst" -exec mv {} "$REPO_DIR/" \;
            chown -R builder:builder "$REPO_DIR"
            su -s /bin/bash builder -c "cd '$pkg_dir' && makepkg -c --noconfirm" 2>/dev/null || true
        else
            bashio::log.error "Fallo al compilar el paquete: $pkg_name"
        fi
    done < <(find "$BUILDS_DIR" -mindepth 2 -maxdepth 2 -name "PKGBUILD")

    # 3b. Eliminar paquetes obsoletos si su PKGBUILD ya no existe en el repo Git
    shopt -s nullglob
    OLD_PACKAGES=("$REPO_DIR"/*.pkg.tar.zst)
    shopt -u nullglob

    for pkg_file in "${OLD_PACKAGES[@]}"; do
        [ -e "$pkg_file" ] || continue
        filebase=$(basename "$pkg_file" .pkg.tar.zst)
        pkg_name=$(echo "$filebase" | sed -E 's/-[^-]+-[^-]+-[^-]+$//')

        if [ ! -d "$BUILDS_DIR/$pkg_name" ] || [ ! -f "$BUILDS_DIR/$pkg_name/PKGBUILD" ]; then
            REMOVED=1
            bashio::log.info "Eliminando paquete obsoleto: $(basename "$pkg_file")"
            rm -f "$pkg_file"
        fi
    done

    # Limpiar carpetas huérfanas en BUILDS_DIR tras borrar en Git
    find "$BUILDS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".git" | while read -r dir; do
        if [ ! -f "$dir/PKGBUILD" ]; then
            rm -rf "$dir"
        fi
    done

    # 3c. Regenerar la base de datos pacman
    cd "$REPO_DIR" || exit 1
    chown -R builder:builder "$REPO_DIR"
    
    if [ "$REMOVED" = "1" ] || [ "$CHANGED" = "1" ] || [ "$IS_STARTUP" = true ]; then
        bashio::log.info "Actualizando base de datos pacman-cherry.db..."
        
        rm -f pacman-cherry.db* pacman-cherry.files*

        shopt -s nullglob
        PACKAGES=(*.pkg.tar.zst)
        shopt -u nullglob

        if [ ${#PACKAGES[@]} -gt 0 ]; then
            su -s /bin/bash builder -c "cd '$REPO_DIR' && repo-add -n -R pacman-cherry.db.tar.gz *.pkg.tar.zst" || true
            ln -sf pacman-cherry.db.tar.gz pacman-cherry.db
            ln -sf pacman-cherry.files.tar.gz pacman-cherry.files
        else
            bashio::log.warning "No quedan archivos .pkg.tar.zst en $REPO_DIR. Base de datos vaciada."
        fi
    fi

    chmod 644 pacman-cherry.* *.pkg.tar.zst 2>/dev/null || true
    bashio::log.info "Base de datos y servidor HTTP sincronizados."

    # 3d. Limpieza de temporales en disco
    find "$BUILDS_DIR" -type d \( -name "src" -o -name "pkg" \) -prune -exec rm -rf {} + 2>/dev/null || true
    rm -rf /var/tmp/makepkg/* 2>/dev/null || true
    pacman -Scc --noconfirm 2>/dev/null || true

    bashio::log.info "Sincronización finalizada con éxito."
else
    bashio::log.info "Sin cambios en Git. Repositorio al día."
fi