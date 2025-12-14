# ============================================================
# Base (共通)
# ============================================================
FROM debian:stable-slim AS base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bash curl ca-certificates tini procps \
    pciutils ocl-icd-libopencl1 \
 && rm -rf /var/lib/apt/lists/*

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
FROM runtime-jre25 AS runtime-jre25-gpu

RUN apt-get update && apt-get install -y \
    clinfo \
 && rm -rf /var/lib/apt/lists/*

ENV RUNTIME_FLAVOR=gpu
ENV ENABLE_C2ME_OPENCL=true
