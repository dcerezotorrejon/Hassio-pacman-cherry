# Hassio Pacman Cherry 🍒

![pacman-cherry](Hassio-pacman-cherry/icon.png)

Add-on de **Home Assistant** basado en **Arch Linux** que actúa como un repositorio de paquetes **Pacman** personalizado, automatizando la compilación de recetas `PKGBUILD` alojadas en un repositorio Git y sirviéndolas mediante un servidor web **Caddy**.

---

## 🚀 Características Principales

- **Compilación Automatizada:** Clona y monitoriza un repositorio Git de recetas `PKGBUILD`. Si detecta nuevos commits o es la primera ejecución, compila automáticamente los paquetes nuevos o actualizados.
- **Seguridad y Privacidad:** Las compilaciones se ejecutan bajo un usuario sin privilegios (`builder`) utilizando directorios temporales dedicados (`/data/pacman-cherry`).
- **Servidor Web Incorporado:** Utiliza **Caddy** en el puerto `8034` para servir de forma rápida y eficiente los paquetes `.pkg.tar.zst` y las bases de datos de Pacman.
- **Base de Datos Dinámica:** Actualiza y genera automáticamente la base de datos del repositorio (`pacman-cherry.db`) empleando `repo-add`.
- **Sincronización Periódica:** Comprueba actualizaciones en segundo plano según el intervalo configurado.
- **Soporte Base:** Construido sobre `archlinux:latest`, con soporte para `s6-overlay v3` y `bashio`.

---

## 📥 Instalación

1. Añade este repositorio a tus add-ons de Home Assistant:
   [![Añadir repositorio](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdcerezotorrejon%2FHassio-pacman-cherry)
2. Busca el add-on **Pacman Cherry** en la tienda de add-ons.
3. Haz clic en **Instalar**.

---

## ⚙️ Configuración

Configura el add-on desde la pestaña de **Configuración** en Home Assistant:

```yaml
pkgbuild_repo_url: "https://github.com/tu_usuario/tu_repo_pkgbuilds.git"
poll_interval: 30
log_level: "info"
```

| Parámetro | Tipo | Descripción |
| :--- | :--- | :--- |
| `pkgbuild_repo_url` | URL | URL del repositorio Git que contiene las carpetas con las recetas `PKGBUILD` a compilar. |
| `poll_interval` | Entero (1-1440) | Tiempo en minutos entre cada comprobación de cambios en el repositorio Git. |
| `log_level` | Lista | Nivel de detalle de los logs (`trace`, `debug`, `info`, `notice`, `warning`, `error`, `fatal`). |

---

## 🌐 Consumo del Repositorio Pacman

Una vez iniciado el add-on, puedes configurar cualquier sistema Arch Linux o compatible para instalar paquetes desde tu servidor Home Assistant añadiendo la siguiente entrada en `/etc/pacman.conf`:

```ini
[pacman-cherry]
SigLevel = Optional TrustAll
Server = http://<IP_DE_HOME_ASSISTANT>:8034/
```

---

## 📋 Changelog

Consulta el [Changelog completo](Hassio-pacman-cherry/CHANGELOG.md) para ver los cambios recientes.

---

## 📄 Licencia

Este proyecto se distribuye bajo los términos especificados en el repositorio.
