# **alexandergg-0520 / minecraft-server**

![Build & Publish](https://github.com/alexandergg-0520/minecraft-server/actions/workflows/docker-publish.yml/badge.svg)
![Java Versions](https://img.shields.io/badge/Java-8%20%7C%2011%20%7C%2017%20%7C%2021%20%7C%2022%20%7C%2025-blue)
![Types](https://img.shields.io/badge/Types-16%2B-green)
![GHCR Version](https://img.shields.io/github/v/release/alexandergg-0520/minecraft-server?label=GHCR)

A next-generation Minecraft server image designed to **surpass itzg/minecraft-server**,
featuring advanced **auto-installation**, **S3/MinIO syncing**, **world lifecycle controls**,
and full support for **Java 8 / 11 / 17 / 21 / 22 / 25** including **Java 25 for C2ME GPU Accelerated**.

---

## ✨ Features

### ✔ itzg-Compatible

Supports common itzg environment variables (`EULA`, `TYPE`, `VERSION`, `MEMORY`, …).

### ✔ Auto Installation for 16+ Server Types

Automatically downloads the correct JAR for major Java Edition server types
(Vanilla / Fabric / Paper / NeoForge / Velocity / Purpur / Glowstone / etc).

### ✔ S3 / MinIO Mod & Config Sync

Syncs `/data/mods/` and `/data/config/` via MinIO client (`mc mirror`), with optional cleanup.

### ✔ World Lifecycle Management

* Reset world using `/data/reset-world.flag`
* Optional `WORLD_RESET_POLICY=always_on_start`

### ✔ Kubernetes-Ready

Graceful startup/shutdown, liveness/readiness health checks, persistent storage layout.

### ✔ Java 25 support for C2ME GPU Accelerated

Automatically enables Panama / Vector API flags when running on Java 25.

---

## 🧩 **Supported Server Types (`TYPE=`)**

This image currently supports **16 Java Edition server formats**:

### **Mainline**

* `vanilla` – Official Mojang server
* `fabric` – Modern mod loader (C2ME-ready)
* `quilt` – Fabric ecosystem successor
* `paper` – High-performance modern server
* `folia` – Region-threaded Paper fork
* `purpur` – Feature-rich Paper fork
* `pufferfish` – Performance optimized
* `airplane` – Lightweight high-performance fork
* `leaves` – Ultra-light fork for low-resource servers

### **Mod Loaders**

* `forge` – Legacy / classic modloader
* `neoforge` – Modern Forge successor
* `mohist` – Forge + Bukkit hybrid
* `catserver` – Forge + Spigot hybrid

### **Proxies**

* `velocity` – The modern high-performance proxy
* `waterfall` – Maintained BungeeCord fork
* `bungeecord` – Original Minecraft proxy

### **Custom / Alternative Implementations**

* `glowstone` – Lightweight Java implementation
* `cuberite` – C++ server (requires URL override)

---

## 🚀 **Quick Start (Docker Run)**

```powershell
docker run -it \
  -p 25565:25565 \
  -v ./data:/data \
  -e EULA=true \
  -e TYPE=fabric \
  -e VERSION=1.21.1 \
  ghcr.io/yourname/minecraft-server:java21
```

---

## 🚀 **Quick Start (Docker Compose)**

```yaml
services:
  mc:
    image: ghcr.io/yourname/minecraft-server:java21
    ports:
      - "25565:25565"
    environment:
      EULA: "true"
      TYPE: "paper"
      VERSION: "1.21.1"
      MEMORY: "4G"
    volumes:
      - ./data:/data
```

---

## 📦 **Using S3 / MinIO Sync**

```md
MODS_SOURCE=s3
MODS_S3_ENDPOINT=https://minio.example.com
MODS_S3_BUCKET=minecraft-mods
MODS_S3_PREFIX=fabric-smp
MODS_S3_ACCESS_KEY=xxx
MODS_S3_SECRET_KEY=yyy
CLEAN_UNUSED_MODS=true
```

This will mirror:

```md
s3://minecraft-mods/fabric-smp/mods   → /data/mods
s3://minecraft-mods/fabric-smp/config → /data/config
```

---

## 🔄 **World Reset**

### Manual reset

```md
touch /data/reset-world.flag
```

### Reset every startup

```md
WORLD_RESET_POLICY=always_on_start
```

---

## ⚙️ **Environment Variables Overview**

| Variable             | Description                                 |
| -------------------- | ------------------------------------------- |
| `EULA`               | Must be `true`                              |
| `TYPE`               | Server type (fabric/paper/… see list above) |
| `VERSION`            | Minecraft version or `latest`               |
| `MEMORY`             | JVM memory (e.g. `6G`)                      |
| `LOG_FORMAT`         | `plain` or `json`                           |
| `WORLD_RESET_POLICY` | `never` / `always_on_start`                 |
| `MODS_SOURCE`        | `s3` to enable MinIO sync                   |
| `CLEAN_UNUSED_MODS`  | Removes local mods not in S3                |
| `SERVER_PORT`        | Override port (default 25565)               |

---

## ❤️ **Java Version Strategy**

| Tag      | Purpose                              |
| -------- | ------------------------------------ |
| `java8`  | Older Forge packs (1.7–1.12)         |
| `java11` | Older Forge / legacy hybrids         |
| `java17` | Modern Paper/Fabric baseline         |
| `java21` | Current LTS, **default**             |
| `java22` | Experimental                         |
| `java25` | **C2ME GPU Accelerated recommended** |

---

## 🔬 **Kubernetes Example**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mc
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mc
  template:
    metadata:
      labels:
        app: mc
    spec:
      containers:
      - name: server
        image: ghcr.io/yourname/minecraft-server:java21
        env:
        - name: EULA
          value: "true"
        - name: TYPE
          value: "fabric"
        - name: MEMORY
          value: "6G"
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: minecraft-data
```

---

## 📁 **Data Layout**

```md
/data/
  ├─ world/
  ├─ mods/
  ├─ config/
  ├─ server.jar
  ├─ logs/
  └─ reset-world.flag
```

---

## 📜 License

MIT License

---
