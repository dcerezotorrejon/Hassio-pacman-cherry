#!/usr/bin/env bash

# Directorios globales
export REPO_DIR="/data/pacman-cherry/builds"
export BUILDS_DIR="/data/pacman-cherry/pkgbuilds-repo"

# Configuración leída desde Bashio
export PKGBUILD_REPO_URL=$(bashio::config 'pkgbuild_repo_url')