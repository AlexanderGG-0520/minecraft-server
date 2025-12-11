# ─────────────────────────────────────────────
#  Minecraft Server Docker Image
#  Multi-Java Version Build (8 / 11 / 17 / 21 / 22 / 25)
#  C2ME GPU Accelerated Ready
# ─────────────────────────────────────────────

# Java version is injected from CI/CD:
#   --build-arg JAVA_VERSION=21
# Default = 21 (current Minecraft LTS)
ARG JAVA_VERSION=21
FROM eclipse-temurin:${JAVA_VERSION}-jre-jammy

LABEL maintainer="alexandergg-0520"
LABEL description="Next-generation Minecraft server image with S3 sync, auto-installers, and multi-Java support."

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

# ─────────────────────────────────────────────
# Base System
# ─────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash curl jq unzip ca-certificates dumb-init && \
    rm -rf /var/lib/apt/lists/*

# MinIO client (for S3 sync)
RUN curl -s https://dl.min.io/client/mc/release/linux-amd64/mc \
      -o /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc

# Create runtime user
RUN useradd -m -u 1000 -d /data mc && \
    mkdir -p /data && chown -R mc:mc /data

WORKDIR /data

# ─────────────────────────────────────────────
# Scripts
# ─────────────────────────────────────────────
COPY scripts/ /opt/mc/
RUN chmod +x /opt/mc/*.sh

USER mc

EXPOSE 25565
VOLUME ["/data"]

# Health check
HEALTHCHECK --interval=20s --timeout=5s --start-period=45s --retries=3 \
  CMD /opt/mc/healthcheck.sh

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/opt/mc/entrypoint.sh"]
