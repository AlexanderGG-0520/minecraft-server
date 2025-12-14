# ============================================================
# Stage 0: base selector
# ============================================================
ARG BASE_FLAVOR=cpu
ARG DEBIAN_VERSION=12
ARG CUDA_VERSION=13.0.0

# --- CPU base ---
FROM debian:stable-slim AS cpu-base

# --- GPU base ---
FROM nvidia/cuda:${CUDA_VERSION}-runtime-debian${DEBIAN_VERSION} AS gpu-base


# ============================================================
# Stage 1: runtime base
# ============================================================
FROM ${BASE_FLAVOR}-base AS runtime

ARG JAVA_MAJOR=21
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# ------------------------------------------------------------
# Base utilities + Adoptium key
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    tzdata \
    bash \
    tini \
    procps \
    jq \
    rsync \
    pciutils \
 && mkdir -p /etc/apt/keyrings \
 && curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] \
    https://packages.adoptium.net/artifactory/deb bookworm main" \
    > /etc/apt/sources.list.d/adoptium.list

# ------------------------------------------------------------
# Java (Eclipse Temurin)
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    temurin-${JAVA_MAJOR}-jre \
 && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/temurin-${JAVA_MAJOR}-jre-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# ------------------------------------------------------------
# OpenCL (GPU only)
# ------------------------------------------------------------
ARG BASE_FLAVOR
RUN if [ "${BASE_FLAVOR}" = "gpu" ]; then \
      apt-get update && apt-get install -y \
        ocl-icd-libopencl1 \
        clinfo \
      && rm -rf /var/lib/apt/lists/* ; \
    fi

# ------------------------------------------------------------
# MinIO client
# ------------------------------------------------------------
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc \
    -o /usr/local/bin/mc \
 && chmod +x /usr/local/bin/mc

# ------------------------------------------------------------
# Non-root user
# ------------------------------------------------------------
RUN groupadd -g 1000 mc \
 && useradd -u 1000 -g 1000 -m -s /bin/bash mc

# ------------------------------------------------------------
# Runtime directories
# ------------------------------------------------------------
RUN mkdir -p /data /mods-drop \
 && chown -R mc:mc /data /mods-drop

# ------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
 && chown mc:mc /entrypoint.sh

USER mc

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
