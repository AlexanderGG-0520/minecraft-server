# ============================================================
# Base Java runtimes
# ============================================================

FROM eclipse-temurin:21-jdk AS java21
FROM eclipse-temurin:17-jdk AS java17
FROM eclipse-temurin:16-jdk AS java16
FROM eclipse-temurin:11-jdk AS java11
FROM eclipse-temurin:8-jdk  AS java8

# ============================================================
# Runtime Image
# ============================================================

FROM debian:stable-slim AS runtime

ARG JAVA_VERSION=21
ENV JAVA_VERSION=${JAVA_VERSION}
ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# Base packages
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    wget \
    jq \
    unzip \
    ca-certificates \
    tar \
    gettext-base \
    git \
    uuid-runtime \
    procps \
    tini \
    libopencl1 \
  && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# MinIO Client
# ------------------------------------------------------------
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc \
    -o /usr/local/bin/mc \
 && chmod +x /usr/local/bin/mc

# ------------------------------------------------------------
# Java runtimes
# ------------------------------------------------------------
COPY --from=java21 /opt/java/openjdk /opt/java21
COPY --from=java17 /opt/java/openjdk /opt/java17
COPY --from=java16 /opt/java/openjdk /opt/java16
COPY --from=java11 /opt/java/openjdk /opt/java11
COPY --from=java8  /opt/java/openjdk /opt/java8

RUN ln -sf /opt/java${JAVA_VERSION} /opt/java \
 && ln -sf /opt/java/bin/java /usr/local/bin/java

# ------------------------------------------------------------
# Minecraft runtime layout
# ------------------------------------------------------------
RUN mkdir -p /opt/mc/{scripts,base} /data

COPY scripts/ /opt/mc/scripts/
COPY base/    /opt/mc/base/
COPY types/   /opt/mc/

RUN chmod +x /opt/mc/scripts/*.sh /opt/mc/base/*.sh

WORKDIR /data
VOLUME ["/data"]

ENV JAVA_TOOL_OPTIONS="-Duser.dir=/data"

STOPSIGNAL SIGTERM

# ------------------------------------------------------------
# ENTRYPOINT (PID 1 = tini)
# ------------------------------------------------------------
ENTRYPOINT ["/usr/bin/tini", "--", "bash", "/opt/mc/scripts/entrypoint.sh"]
