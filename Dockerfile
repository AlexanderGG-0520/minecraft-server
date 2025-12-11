# ============================================================
# Base Java Images (official, glibc, multi-arch)
# ============================================================
FROM eclipse-temurin:8-jre AS java8
FROM eclipse-temurin:11-jre AS java11
FROM eclipse-temurin:17-jre AS java17
FROM eclipse-temurin:21-jre AS java21
FROM eclipse-temurin:25-jre AS java25

# ============================================================
# Runtime Image (Debian stable-slim)
# ============================================================
FROM debian:stable-slim AS runtime

ARG JAVA_VERSION=21
ENV DEBIAN_FRONTEND=noninteractive

# Install required tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl wget jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Java runtime selection
COPY --from=java21 /opt/java/openjdk /opt/java21
COPY --from=java25 /opt/java/openjdk /opt/java25

RUN if [ "$JAVA_VERSION" = "25" ]; then \
        ln -sf /opt/java25 /opt/java ; \
    else \
        ln -sf /opt/java21 /opt/java ; \
    fi

ENV PATH="/opt/java/bin:${PATH}"

# ============================================================
# Minecraft Runtime Layout
# ============================================================
WORKDIR /opt/mc

# Scripts
COPY docker/scripts ./scripts
RUN chmod +x ./scripts/*.sh

# Base config layer
COPY docker/base ./base

# Type-specific config layers
COPY docker/fabric   ./fabric
COPY docker/forge    ./forge
COPY docker/neoforge ./neoforge
COPY docker/paper    ./paper
COPY docker/proxy    ./proxy

# Runtime directory
RUN mkdir -p /data

# Expose Minecraft ports
EXPOSE 25565 25575

# Default ENV
ENV EULA="false" \
    MEMORY="4G" \
    LOG_FORMAT="plain" \
    TYPE="fabric" \
    VERSION="latest" \
    WORLD_RESET_POLICY="never"

VOLUME ["/data"]

ENTRYPOINT ["bash", "/opt/mc/scripts/entrypoint.sh"]
