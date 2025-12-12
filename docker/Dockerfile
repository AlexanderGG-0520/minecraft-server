# ============================================================
# Base Java runtimes
# ============================================================

FROM eclipse-temurin:25-jre-noble AS java25
FROM eclipse-temurin:21-jre-noble AS java21
FROM eclipse-temurin:16-jre-noble AS java16
FROM eclipse-temurin:17-jre-noble AS java17
FROM eclipse-temurin:11-jre-noble AS java11
FROM eclipse-temurin:8-jre-noble AS java8

# ============================================================
# Runtime Image
# ============================================================

FROM debian:stable-slim AS runtime

ARG JAVA_VERSION=21
ENV JAVA_VERSION=${JAVA_VERSION}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bash curl wget jq unzip ca-certificates tar \
  && rm -rf /var/lib/apt/lists/*

# Minio CLI
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc \
  -o /usr/local/bin/mc && chmod +x /usr/local/bin/mc

# Install Java from selected version
COPY --from=java25 /opt/java/openjdk /opt/java25
COPY --from=java21 /opt/java/openjdk /opt/java21
COPY --from=java17 /opt/java/openjdk /opt/java17
COPY --from=java16 /opt/java/openjdk /opt/java16
COPY --from=java11 /opt/java/openjdk /opt/java11
COPY --from=java8  /opt/java/openjdk /opt/java8

RUN ln -sf /opt/java${JAVA_VERSION} /opt/java \
  && ln -sf /opt/java/bin/java /usr/local/bin/java


# ============================================================
# Runtime layout
# ============================================================

RUN mkdir -p /opt/mc/{scripts,base} /data

COPY scripts/ /opt/mc/scripts/
COPY base/    /opt/mc/base/
COPY types/   /opt/mc/

RUN chmod +x /opt/mc/scripts/*.sh /opt/mc/base/*.sh

WORKDIR /opt/mc
VOLUME ["/data"]

ENTRYPOINT ["bash", "/opt/mc/scripts/entrypoint.sh"]

