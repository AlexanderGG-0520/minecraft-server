# ============================================================
# Base (共通ツール + entrypoint)
# ============================================================
FROM debian:stable-slim AS base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bash curl ca-certificates tini procps \
    pciutils ocl-icd-libopencl1 jq rsync libpopt0 rcon-cli \
 && rm -rf /var/lib/apt/lists/*

# --- MinIO client (mc) ---
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc \
      -o /usr/local/bin/mc \
 && chmod +x /usr/local/bin/mc \
 && mc --version

ENV HOME=/data
WORKDIR /data

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

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
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*
COPY --from=base /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
COPY --from=base /usr/bin/rsync /usr/bin/rsync
COPY --from=base /usr/lib/x86_64-linux-gnu/libpopt.so.0 /usr/lib/x86_64-linux-gnu/libpopt.so.0
COPY --from=base /usr/lib/rcon-cli /usr/lib/rcon-cli
ENV HOME=/data
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# -------- Java 11 --------
FROM jre11 AS runtime-jre11
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*
COPY --from=base /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
COPY --from=base /usr/bin/rsync /usr/bin/rsync
COPY --from=base /usr/lib/x86_64-linux-gnu/libpopt.so.0 /usr/lib/x86_64-linux-gnu/libpopt.so.0
COPY --from=base /usr/lib/rcon-cli /usr/lib/rcon-cli
ENV HOME=/data
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# -------- Java 17 --------
FROM jre17 AS runtime-jre17
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*
COPY --from=base /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
COPY --from=base /usr/bin/rsync /usr/bin/rsync
COPY --from=base /usr/lib/x86_64-linux-gnu/libpopt.so.0 /usr/lib/x86_64-linux-gnu/libpopt.so.0
COPY --from=base /usr/lib/rcon-cli /usr/lib/rcon-cli
ENV HOME=/data
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# -------- Java 21 --------
FROM jre21 AS runtime-jre21
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*
COPY --from=base /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
COPY --from=base /usr/bin/rsync /usr/bin/rsync
COPY --from=base /usr/lib/x86_64-linux-gnu/libpopt.so.0 /usr/lib/x86_64-linux-gnu/libpopt.so.0
COPY --from=base /usr/lib/rcon-cli /usr/lib/rcon-cli
ENV HOME=/data
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# -------- Java 25 --------
FROM jre25 AS runtime-jre25
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*
COPY --from=base /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
COPY --from=base /usr/bin/rsync /usr/bin/rsync
COPY --from=base /usr/lib/x86_64-linux-gnu/libpopt.so.0 /usr/lib/x86_64-linux-gnu/libpopt.so.0
COPY --from=base /usr/lib/rcon-cli /usr/lib/rcon-cli
ENV HOME=/data
WORKDIR /data
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# ============================================================
# GPU runtime (Java 25 only)
# ============================================================
FROM nvidia/cuda:12.2.2-runtime-ubuntu22.04 AS runtime-jre25-gpu

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bash ca-certificates curl tini procps \
    pciutils ocl-icd-libopencl1 clinfo jq rsync libpopt0 rcon-cli \
 && rm -rf /var/lib/apt/lists/*

# LWJGL expects libOpenCL.so (not only libOpenCL.so.1)
RUN set -eux; \
    if [ -e /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 ] && [ ! -e /usr/lib/x86_64-linux-gnu/libOpenCL.so ]; then \
      ln -s /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 /usr/lib/x86_64-linux-gnu/libOpenCL.so; \
    fi

# --- MinIO client (mc) ---
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc \
      -o /usr/local/bin/mc \
 && chmod +x /usr/local/bin/mc \
 && mc --version

# --- Java 25 ---
COPY --from=eclipse-temurin:25-jre /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# --- entrypoint & tini & rsync & libpopt0 & rcon-cli ---
COPY --from=base /usr/local/bin/mc /usr/local/bin/mc
COPY --from=base /entrypoint.sh /entrypoint.sh
COPY --from=base /usr/bin/tini /usr/bin/tini
COPY --from=base /usr/bin/rsync /usr/bin/rsync
COPY --from=base /usr/lib/x86_64-linux-gnu/libpopt.so.0 /usr/lib/x86_64-linux-gnu/libpopt.so.0
COPY --from=base /usr/lib/rcon-cli /usr/lib/rcon-cli

ENV HOME=/data
WORKDIR /data

ENV RUNTIME_FLAVOR=gpu
ENV ENABLE_C2ME_OPENCL=true

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]
