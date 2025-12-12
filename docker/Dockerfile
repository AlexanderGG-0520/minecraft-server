# ============================================================
# Base Java Runtime (multi-arch Temurin)
# ============================================================
FROM eclipse-temurin:8-jre AS java8
FROM eclipse-temurin:11-jre AS java11
FROM eclipse-temurin:17-jre AS java17
FROM eclipse-temurin:21-jre AS java21
FROM eclipse-temurin:25-jre AS java25

# ============================================================
# Final Runtime Image — Debian stable-slim
# ============================================================
FROM debian:stable-slim AS runtime

ARG JAVA_VERSION=21
ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# Required Tools
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl wget jq ca-certificates unzip \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Install MinIO Client (mc) inside the image
# ------------------------------------------------------------
RUN wget -q https://dl.min.io/client/mc/release/linux-amd64/mc \
    -O /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc

# ------------------------------------------------------------
# Java Runtimes
# ------------------------------------------------------------
COPY --from=java21 /opt/java/openjdk /opt/java21
COPY --from=java25 /opt/java/openjdk /opt/java25

RUN if [ "$JAVA_VERSION" = "25" ]; then \
        ln -sf /opt/java25 /opt/java ; \
    else \
        ln -sf /opt/java21 /opt/java ; \
    fi

ENV PATH="/opt/java/bin:${PATH}"

# ------------------------------------------------------------
# Minecraft Runtime Directory Layout
# ------------------------------------------------------------
WORKDIR /opt/mc

# Scripts
COPY docker/scripts ./scripts
RUN chmod +x ./scripts/*.sh

# Base ENV (default values: disabled S3 etc)
COPY docker/base/ /opt/mc/base

# Type-specific layers
COPY docker/fabric   ./fabric
COPY docker/forge    ./forge
COPY docker/neoforge ./neoforge
COPY docker/paper    ./paper
COPY docker/proxy    ./proxy

# Data directory
RUN mkdir -p /data

# ------------------------------------------------------------
# Default Environment Variables
# ------------------------------------------------------------
ENV EULA="false" \
    TYPE="fabric" \
    VERSION="latest" \
    MEMORY="4G" \
    LOG_FORMAT="plain" \
    S3_SYNC_ENABLED="false" \
    WORLD_RESET_POLICY="never"

VOLUME ["/data"]

EXPOSE 25565 25575

ENTRYPOINT ["bash", "/opt/mc/scripts/entrypoint.sh"]
