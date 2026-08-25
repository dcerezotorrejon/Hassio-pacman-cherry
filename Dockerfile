FROM archlinux:latest

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 1. Actualizar llaves e instalar dependencias
RUN pacman -Sy --noconfirm archlinux-keyring && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
    base-devel \
    git \
    caddy \
    jq \
    curl \
    bash \
    ca-certificates \
    tar \
    xz && \
    pacman -Scc --noconfirm

# 2. Instalar S6 Overlay v3 (Solo lo usará Home Assistant Add-on)
ARG TARGETARCH
ARG S6_OVERLAY_VERSION=3.1.6.2

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz && rm -f /tmp/s6-overlay-noarch.tar.xz

RUN if [ "$TARGETARCH" = "arm64" ]; then S6_ARCH="aarch64"; else S6_ARCH="x86_64"; fi && \
    curl -sSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" -o /tmp/s6-arch.tar.xz && \
    tar -C / -Jxpf /tmp/s6-arch.tar.xz && rm -f /tmp/s6-arch.tar.xz

RUN ln -s /command/with-contenv /usr/bin/with-contenv

# 3. Instalar Bashio
RUN mkdir -p /tmp/bashio /usr/lib/bashio && \
    curl -sSL https://github.com/hassio-addons/bashio/archive/v0.16.2.tar.gz | tar xz -C /tmp/bashio --strip-components=1 && \
    mv /tmp/bashio/lib/* /usr/lib/bashio/ && \
    rm -rf /tmp/bashio && \
    printf '#!/usr/bin/env bash\nsource /usr/lib/bashio/bashio.sh\nif [ -n "$1" ]; then\n  source "$1"\nfi\n' > /usr/bin/bashio && \
    chmod -R +x /usr/lib/bashio /usr/bin/bashio

# 4. Crear usuario 'builder' y ajustar makepkg
RUN useradd -m -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 440 /etc/sudoers.d/builder && \
    mkdir -p /var/tmp/makepkg && \
    chown builder:builder /var/tmp/makepkg && \
    echo 'BUILDDIR=/var/tmp/makepkg' >> /etc/makepkg.conf && \
    sed -i 's/OPTIONS=(/OPTIONS=(!strip !debug /' /etc/makepkg.conf

# 5. Copiar scripts y dar permisos
COPY Scripts/entrypoint.sh /entrypoint.sh
COPY Scripts/env.sh /env.sh
COPY Scripts/run.sh /run.sh
COPY Scripts/builder.sh /builder.sh
RUN sed -i 's/\r$//' /entrypoint.sh /env.sh /run.sh /builder.sh && \
    chmod +x /entrypoint.sh /env.sh /run.sh /builder.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/run.sh"]