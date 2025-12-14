FROM debian:stable-slim

# ----------------------------
# Packages
# ----------------------------
RUN apt-get update && apt-get install -y \
    bash \
    ca-certificates \
    curl \
    jq \
    tini \
    openjdk-21-jre-headless \
 && rm -rf /var/lib/apt/lists/*

# ----------------------------
# Non-root user
# ----------------------------
RUN groupadd -g 1000 mc \
 && useradd -u 1000 -g 1000 -m -s /bin/bash mc

# ----------------------------
# Runtime directories
# ----------------------------
RUN mkdir -p /data \
 && chown -R 1000:1000 /data

# ----------------------------
# Entrypoint
# ----------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
 && chown 1000:1000 /entrypoint.sh

USER 1000:1000

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
