# ======================================================================
#  Minecraft Unified Server — Multi TYPE Runtime
#  (Fabric / Forge / NeoForge / Paper / Purpur / Vanilla / Proxy etc.)
# ======================================================================

FROM eclipse-temurin:25-jre-noble AS base

ENV DEBIAN_FRONTEND=noninteractive

# ----------------------------------------------------------
# Install required utilities
# ----------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl wget unzip jq ca-certificates tar \
    && rm -rf /var/lib/apt/lists/*

# ----------------------------------------------------------
# Install MinIO client (mc)
# ----------------------------------------------------------
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc \
    -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc

# ----------------------------------------------------------
# Create directories
# ----------------------------------------------------------
RUN mkdir -p \
    /opt/mc/base \
    /opt/mc/scripts \
    /opt/mc/vanilla \
    /opt/mc/fabric \
    /opt/mc/forge \
    /opt/mc/neoforge \
    /opt/mc/paper \
    /opt/mc/purpur \
    /opt/mc/velocity \
    /opt/mc/waterfall \
    /opt/mc/bungeecord \
    /data


# ======================================================================
#  Copy Project Files
# ======================================================================

# entrypoint
COPY ./scripts/entrypoint.sh /opt/mc/scripts/entrypoint.sh
RUN chmod +x /opt/mc/scripts/entrypoint.sh

# Main modules
COPY ./scripts/sync_s3.sh                /opt/mc/scripts/sync_s3.sh
COPY ./scripts/reset_world.sh            /opt/mc/scripts/reset_world.sh
COPY ./base/make_args.sh                 /opt/mc/base/make_args.sh

RUN chmod +x /opt/mc/scripts/*.sh /opt/mc/base/make_args.sh

# Detect/download scripts（各 TYPE ごと）
COPY ./scripts/detect_or_download_*.sh   /opt/mc/scripts/
RUN chmod +x /opt/mc/scripts/detect_or_download_*.sh

# Default base config
COPY ./base/base.env                     /opt/mc/base/base.env
COPY ./base/server.properties.base       /opt/mc/base/server.properties.base
COPY ./base/jvm.args                     /opt/mc/base/jvm.args
COPY ./base/mc.args                      /opt/mc/base/mc.args

# TYPE-specific config (empty OK)
COPY ./types/vanilla/     /opt/mc/vanilla/
COPY ./types/fabric/      /opt/mc/fabric/
COPY ./types/forge/       /opt/mc/forge/
COPY ./types/neoforge/    /opt/mc/neoforge/
COPY ./types/paper/       /opt/mc/paper/
COPY ./types/purpur/      /opt/mc/purpur/
COPY ./types/velocity/    /opt/mc/velocity/
COPY ./types/waterfall/   /opt/mc/waterfall/
COPY ./types/bungeecord/  /opt/mc/bungeecord/

# ======================================================================
#  Final image configuration
# ======================================================================

WORKDIR /data

# Allow LD_LIBRARY_PATH overrides (GPU OpenCL など)
ENV LD_LIBRARY_PATH="/usr/local/opencl:/usr/local/nvidia/lib:/usr/local/nvidia/lib64"

# S3 defaults
ENV S3_TLS_ENABLED=true

# Container runtime
EXPOSE 25565 25575

ENTRYPOINT [ "/opt/mc/scripts/entrypoint.sh" ]
CMD []
# ======================================================================