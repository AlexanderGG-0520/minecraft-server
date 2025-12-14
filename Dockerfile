# ============================================================
# Base (共通)
# ============================================================
FROM debian:stable-slim AS base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bash curl ca-certificates tini procps \
    pciutils ocl-icd-libopencl1 \
 && rm -rf /var/lib/apt/lists/*

 # --- MinIO client (mc) ---
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc \
 && chmod +x /usr/local/bin/mc \
 && mc --version


ENV HOME=/data

WORKDIR /app

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]

# ============================================================
# Java runtimes
# ============================================================

FROM eclipse-temurin:8-jre  AS jre8
FROM eclipse-temurin:11-jre AS jre11
FROM eclipse-temurin:17-jre AS jre17
FROM eclipse-temurin:21-jre AS jre21
FROM eclipse-temurin:25-jre AS jre25

# ============================================================
# Merge base + Java
# ============================================================

FROM jre8  AS runtime-jre8
COPY --from=base / /

FROM jre11 AS runtime-jre11
COPY --from=base / /

FROM jre17 AS runtime-jre17
COPY --from=base / /

FROM jre21 AS runtime-jre21
COPY --from=base / /

FROM jre25 AS runtime-jre25
COPY --from=base / /

# ============================================================
# GPU runtime (ONLY jre25)
# ============================================================
FROM nvidia/cuda:13.1.0-runtime-ubuntu24.04 AS runtime-jre25-gpu

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bash ca-certificates curl tini procps \
    pciutils ocl-icd-libopencl1 clinfo \
 && rm -rf /var/lib/apt/lists/*

# --- MinIO client (mc) ---
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc \
 && chmod +x /usr/local/bin/mc \
 && mc --version

ENV HOME=/data


# --- Java 25 ---
COPY --from=eclipse-temurin:25-jre /opt/java/openjdk /opt/java/openjdk
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# --- your runtime files ---
COPY --from=base / /

# --- flags ---
ENV RUNTIME_FLAVOR=gpu
ENV ENABLE_C2ME_OPENCL=true

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run"]
