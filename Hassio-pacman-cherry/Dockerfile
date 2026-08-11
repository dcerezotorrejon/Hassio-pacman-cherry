ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest
FROM ${BUILD_FROM}


ENV DEBIAN_FRONTEND=noninteractive

# 1. Asegurar dependencias necesarias en la imagen base Debian (wget, tar, zstd)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    tar \
    zstd \
    caddy \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. Descargar y descomprimir el bootstrap de Arch Linux
RUN mkdir -p /opt/arch && \
    wget -qO- https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.zst | \
    tar --zstd -x -C /opt/arch --strip-components=1

# Configurar el mirrorlist de pacman dentro del entorno Arch
RUN echo "Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch" > /opt/arch/etc/pacman.d/mirrorlist

# 3. Crear usuario builder para tareas que exigen no ser root (makepkg/repo-add)
RUN useradd -m builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 4. Copiar script de ejecución
COPY Scripts/run.sh /run.sh
COPY Scripts/builder.sh /builder.sh
RUN chmod +x /run.sh /builder.sh

CMD [ "/run.sh" ]