# Hassio Pacman Cherry 

![pacman-cherry](Hassio-pacman-cherry/icon.png)

A **Home Assistant** add-on based on **Arch Linux** that acts as a custom **Pacman** package repository, automating the compilation of `PKGBUILD` recipes hosted in a Git repository (such as [custom-AUR](https://github.com/dcerezotorrejon/custom-AUR)) and serving them via a **Caddy** web server.

---

## 🚀 Key Features

- **Automated Compilation:** Clones and monitors a Git repository of `PKGBUILD` recipes. If new commits are detected or on first startup, it automatically compiles new or updated packages.
- **Security & Privacy:** Builds are executed under an unprivileged user (`builder`) using dedicated temporary directories (`/data/pacman-cherry`).
- **Built-in Web Server:** Uses **Caddy** on port `8034` to serve `.pkg.tar.zst` packages and Pacman databases quickly and efficiently.
- **Dynamic Database:** Automatically updates and generates the repository database (`pacman-cherry.db`) using `repo-add`.
- **Periodic Synchronization:** Checks for updates in the background based on the configured interval.
- **Base Support:** Built on top of `archlinux:latest`, supporting `s6-overlay v3` and `bashio`.

---

## 📥 Installation

1. Add this repository to your Home Assistant add-ons:
   [![Add Repository](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdcerezotorrejon%2FHassio-pacman-cherry)
2. Search for the **Pacman Cherry** add-on in the add-on store.
3. Click **Install**.

---

## ⚙️ Configuration

Configure the add-on from the **Configuration** tab in Home Assistant:

```yaml
pkgbuild_repo_url: "https://github.com/your_username/your_pkgbuilds_repo.git"
poll_interval: 30
log_level: "info"
```

| Parameter | Type | Description |
| :--- | :--- | :--- |
| `pkgbuild_repo_url` | URL | URL of the Git repository containing the folders with `PKGBUILD` recipes to compile. |
| `poll_interval` | Integer (1-1440) | Time in minutes between Git repository change checks. |
| `log_level` | List | Detail level of logs (`trace`, `debug`, `info`, `notice`, `warning`, `error`, `fatal`). |

---

## 🐳 Despliegue en Docker / Portainer (Stand-alone)

Este proyecto también se puede ejecutar como un contenedor Docker independiente en cualquier servidor o en **Portainer**, configurando los parámetros mediante variables de entorno y un volumen persistente.

### 1. Variables de Entorno

| Variable | Descripción | Por defecto |
| :--- | :--- | :--- |
| `PKGBUILD_REPO_URL` | URL del repositorio Git con las recetas `PKGBUILD`. | *(Obligatorio)* |
| `POLL_INTERVAL` | Intervalo en minutos entre comprobaciones de cambios en Git. | `30` |
| `LOG_LEVEL` | Nivel de detalle de los logs (`info`, `debug`, etc.). | `info` |
| `PORT` | Puerto HTTP en el que Caddy sirve los paquetes compilados. | `8034` |

### 2. Despliegue con Docker Compose / Portainer Stacks

Puedes desplegarlo fácilmente usando el archivo `docker-compose.yml` incluido en el repositorio, o creando una **Stack** en Portainer con el siguiente contenido:

```yaml
version: '3.8'

services:
  pacman-cherry:
    image: ghcr.io/dcerezotorrejon/hassio-pacman-cherry:latest
    # O puedes construirlo localmente usando: build: .
    container_name: pacman-cherry
    restart: unless-stopped
    ports:
      - "8034:8034"
    environment:
      - PKGBUILD_REPO_URL=https://github.com/tu_usuario/tu_repo_pkgbuilds.git
      - POLL_INTERVAL=30
      - LOG_LEVEL=info
      - PORT=8034
    volumes:
      - pacman_data:/data

volumes:
  pacman_data:
```

### 3. Despliegue manual con `docker run`

```bash
docker run -d \
  --name pacman-cherry \
  -p 8034:8034 \
  -e PKGBUILD_REPO_URL="https://github.com/tu_usuario/tu_repo_pkgbuilds.git" \
  -e POLL_INTERVAL=30 \
  -v pacman_data:/data \
  --restart unless-stopped \
  ghcr.io/dcerezotorrejon/hassio-pacman-cherry:latest
```

---

Once the add-on is started, you can configure any Arch Linux or compatible system to install packages from your Home Assistant server by adding the following entry to `/etc/pacman.conf`:

```ini
[pacman-cherry]
SigLevel = Optional TrustAll
Server = http://<HOME_ASSISTANT_IP>:8034/
```

---

## 📋 Changelog

Check the [Full Changelog](Hassio-pacman-cherry/CHANGELOG.md) for recent changes.

---

## 📄 License

This project is distributed under the terms specified in the repository.
