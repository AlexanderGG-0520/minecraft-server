# ============================================================
# mc builder (Go stdlib / x/crypto CVE 対策)
# ============================================================
ARG MC_RELEASE=RELEASE.2025-08-13T08-35-41Z
ARG GO_VERSION=1.24.11

FROM golang:${GO_VERSION}-bookworm AS mc-builder
ARG MC_RELEASE

RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch ${MC_RELEASE} https://github.com/minio/mc.git .

# x/crypto を脆弱性修正版へ（Scoutの表示: 0.43.0 以上）
RUN go get golang.org/x/crypto@v0.43.0 && go mod tidy

# なるべく小さく
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/mc .

# ============================================================
# Base (共通ツール + entrypoint)
# ============================================================
FROM debian:stable-slim AS base

ARG MCRCON_VERSION=0.7.2
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends \
    bash curl ca-certificates tini procps \
    pciutils ocl-icd-libopencl1 jq unzip \
 && rm -rf /var/lib/apt/lists/*

# --- mcrcon (static) ---
RUN set -eux; \
    curl -fsSL "https://github.com/Tiiffi/mcrcon/releases/download/v${MCRCON_VERSION}/mcrcon-${MCRCON_VERSION}-linux-x86-64-static.zip" -o /tmp/mcrcon.zip; \
    mkdir -p /tmp/mcrcon; \
    unzip -q /tmp/mcrcon.zip -d /tmp/mcrcon; \
    mcrcon_path="$(find /tmp/mcrcon -type f -name mcrcon | head -n 1)"; \
    test -n "${mcrcon_path}"; \
    install -m 0755 "${mcrcon_path}" /usr/local/bin/mcrcon; \
    rm -rf /tmp/mcrcon /tmp/mcrcon.zip; \
    /usr/local/bin/mcrcon -h || true

# ============================================================
# Java base images
# ============================================================
FROM eclipse-temurin:8-jre  AS jre8
FROM eclipse-temurin:11-jre AS jre11
FROM eclipse-temurin:17-jre AS jre17
FROM eclipse-temurin:21-jre AS jre21
FROM eclipse-temurin:25-jre AS jre25

# ============================================================
# Runtime images (CPU)
# ============================================================

# -------- Java 8 --------
FROM jre8 AS runtime-jre8
RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends jq rsync libpopt0 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=mc-builder /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /usr/local/bin/mcrcon /usr/local/bin/mcrcon
COPY entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
ARG UID=10001
ARG GID=10001

RUN groupadd -g ${GID} mc \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash mc \
 && mkdir -p /data \
 && chown -R mc:mc /data

USER mc:mc
ENV HOME=/data
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# -------- Java 11 --------
FROM jre11 AS runtime-jre11
RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends jq rsync libpopt0 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=mc-builder /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /usr/local/bin/mcrcon /usr/local/bin/mcrcon
COPY entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
ARG UID=10001
ARG GID=10001

RUN groupadd -g ${GID} mc \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash mc \
 && mkdir -p /data \
 && chown -R mc:mc /data

USER mc:mc
ENV HOME=/data
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# -------- Java 17 --------
FROM jre17 AS runtime-jre17
RUN apt-get update && apt-get install -y --no-install-recommends jq rsync libpopt0 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=mc-builder /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /usr/local/bin/mcrcon /usr/local/bin/mcrcon
COPY entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
ARG UID=10001
ARG GID=10001

RUN groupadd -g ${GID} mc \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash mc \
 && mkdir -p /data \
 && chown -R mc:mc /data

USER mc:mc
ENV HOME=/data
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# -------- Java 21 --------
FROM jre21 AS runtime-jre21
RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends jq rsync libpopt0 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=mc-builder /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /usr/local/bin/mcrcon /usr/local/bin/mcrcon
COPY entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
ARG UID=10001
ARG GID=10001

RUN groupadd -g ${GID} mc \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash mc \
 && mkdir -p /data \
 && chown -R mc:mc /data

USER mc:mc
ENV HOME=/data
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# -------- Java 25 --------
FROM jre25 AS runtime-jre25
RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends jq rsync libpopt0 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=mc-builder /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /usr/local/bin/mcrcon /usr/local/bin/mcrcon
COPY entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
ARG UID=10001
ARG GID=10001

RUN groupadd -g ${GID} mc \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash mc \
 && mkdir -p /data \
 && chown -R mc:mc /data

USER mc:mc
ENV HOME=/data
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# ============================================================
# GPU runtime (Java 25 only)
# ============================================================
FROM nvidia/cuda:13.1.0-runtime-ubuntu24.04 AS runtime-jre25-gpu

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends \
    bash ca-certificates curl tini procps \
    pciutils ocl-icd-libopencl1 clinfo jq rsync libpopt0 \
 && rm -rf /var/lib/apt/lists/*

# LWJGL expects libOpenCL.so (not only libOpenCL.so.1)
RUN set -eux; \
    if [ -e /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 ] && [ ! -e /usr/lib/x86_64-linux-gnu/libOpenCL.so ]; then \
      ln -s /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 /usr/lib/x86_64-linux-gnu/libOpenCL.so; \
    fi

# --- MinIO client (mc) (built) ---
COPY --from=mc-builder /out/mc /usr/local/bin/mc
RUN chmod +x /usr/local/bin/mc && mc --version

# --- Java 25 ---
COPY --from=eclipse-temurin:25-jre /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# --- entrypoint ---
COPY --from=mc-builder /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /usr/local/bin/mcrcon /usr/local/bin/mcrcon
COPY entrypoint.sh /entrypoint.sh

ENV RUNTIME_FLAVOR=gpu
ENV ENABLE_C2ME_OPENCL=true

ARG UID=10001
ARG GID=10001

RUN groupadd -g ${GID} mc \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash mc \
 && mkdir -p /data \
 && chown -R mc:mc /data

USER mc:mc
ENV HOME=/data
WORKDIR /data

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]
