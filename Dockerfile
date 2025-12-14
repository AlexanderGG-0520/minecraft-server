FROM debian:stable-slim

# ----------------------------
# Base packages
# ----------------------------
RUN apt-get update && apt-get install -y \
    bash \
    ca-certificates \
    curl \
    tini \
    jq \
  && rm -rf /var/lib/apt/lists/*

# ----------------------------
# Runtime directories
# ----------------------------
RUN mkdir -p /data \
 && chmod 755 /data

# ----------------------------
# Copy entrypoint
# ----------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ----------------------------
# Environment defaults
# ----------------------------
ENV EULA=false \
    TYPE=auto \
    VERSION=""

# ----------------------------
# Entrypoint
# ----------------------------
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
