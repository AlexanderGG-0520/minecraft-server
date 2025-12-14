# ============================================
# Minecraft Server Base Image
# - Single Dockerfile
# - Java version selectable via ARG
# - Optional OpenCL (GPU) support
# ============================================

FROM debian:stable-slim

# ----------------------------
# Build arguments
# ----------------------------
ARG JAVA_VERSION=21
ARG ENABLE_OPENCL=false

# ----------------------------
# Environment
# ----------------------------
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# ----------------------------
# Base utilities
# ----------------------------
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    tini \
    tzdata \
    procps \
    jq \
    rsync \
    pciutils \
 && rm -rf /var/lib/apt/lists/*

# ----------------------------
# Adoptium (Eclipse Temurin)
# ----------------------------
RUN mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] \
    https://packages.adoptium.net/artifactory/deb bookworm main" \
    > /etc/apt/sources.list.d/adoptium.list

# ----------------------------
# Java Runtime (ARG selectable)
# ----------------------------
RUN apt-get update && apt-get install -y \
    temurin-${JAVA_VERSION}-jre \
 && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/temurin-${JAVA_VERSION}-jre-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# ----------------------------
# OpenCL (GPU mode only)
# NOTE:
# - NVIDIA driver & libnvidia-opencl are provided by host
# - Do NOT install nvidia-driver inside container
# ----------------------------
RUN if [ "${ENABLE_OPENCL}" = "true" ]; then \
      apt-get update && apt-get install -y \
        ocl-icd-libopencl1 \
        clinfo \
      && rm -rf /var/lib/apt/lists/* ; \
    fi

# ----------------------------
# MinIO Client
# ----------------------------
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc \
    -o /usr/local/bin/mc \
 && chmod +x /usr/local/bin/mc

# ----------------------------
# Non-root user
# ----------------------------
RUN groupadd -g 1000 mc \
 && useradd -u 1000 -g 1000 -m -s /bin/bash mc

# ----------------------------
# Runtime directories
# ----------------------------
RUN mkdir -p /data /mods-drop \
 && chown -R mc:mc /data /mods-drop

# ----------------------------
# Entrypoint
# ----------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
 && chown mc:mc /entrypoint.sh

USER mc

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
