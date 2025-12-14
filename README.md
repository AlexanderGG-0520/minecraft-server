# Minecraft Server Docker Image

![Docker Build](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-server/publish-ghcr.yml?branch=main)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--server-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Java](https://img.shields.io/badge/java-8%20%7C%2011%20%7C%2017%20%7C%2021%20%7C%2025%20%7C%2025--gpu-orange)
![Kubernetes](https://img.shields.io/badge/kubernetes-ready-blue)

---

## 📘 Overview

This repository provides a **production-oriented Minecraft server Docker image**
designed for **explicit, reproducible deployments**.

This project intentionally avoids heavy abstractions (such as Helm charts)
in favor of **clear configuration and predictable runtime behavior**.

### Design goals

* 🧱 Single entrypoint (`entrypoint.sh`)
* 🔁 Deterministic lifecycle: `preflight → install → runtime`
* ☸️ Kubernetes / Recreate strategy friendly
* ⚙️ Configuration via environment variables (itzg-compatible)
* ☁️ S3 / MinIO-based mod & config synchronization
* 🧪 Strictly-guarded experimental features (Java 25 / C2ME)

---

## 📦 Docker Image

## Image name

```md
ghcr.io/alexandergg-0520/minecraft-server:jre-*
```

### Available tags

| Tag                  | Description                      |
| -------------------- | -------------------------------- |
| `jre8`               | Legacy runtime                   |
| `jre11`              | Legacy LTS                       |
| `jre17`              | LTS                              |
| `jre21`              | **Recommended**                  |
| `jre25-experimental` | Experimental runtime (C2ME only) |

> ℹ️ Java version is selected **only by the image tag**.
> The container never auto-switches Java versions.

---

## 🚀 Quick Start (Docker)

```bash
docker run -d \
  -p 25565:25565 \
  -v ./data:/data \
  -e EULA=true \
  -e TYPE=FABRIC \
  -e VERSION=1.21.1 \
  ghcr.io/alexandergg-0520/minecraft-server:jre21
```

---

## 🧩 docker-compose (Recommended for local testing)

```yaml
services:
  minecraft:
    image: ghcr.io/alexandergg-0520/minecraft-server:jre21
    container_name: minecraft
    volumes:
      - ./data:/data
    environment:
      EULA: "true"
      TYPE: FABRIC
      VERSION: 1.21.1
      JVM_XMX: 6G
    ports:
      - "25565:25565"
    restart: unless-stopped
```

---

## ☸️ Kubernetes (YAML-first)

This image is designed for **plain Kubernetes manifests**
and works well with **GitOps tools such as ArgoCD**.

Example (Deployment, Recreate strategy):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minecraft
spec:
  strategy:
    type: Recreate
  replicas: 1
  selector:
    matchLabels:
      app: minecraft
  template:
    metadata:
      labels:
        app: minecraft
    spec:
      containers:
        - name: mc
          image: ghcr.io/alexandergg-0520/minecraft-server:jre21
          env:
            - name: EULA
              value: "true"
            - name: TYPE
              value: FABRIC
            - name: VERSION
              value: "1.21.1"
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: minecraft-data
```

---

## 🧱 Supported Server Types

| Type     | Supported |
| -------- | --------- |
| Vanilla  | ✅         |
| Fabric   | ✅         |
| Forge    | ✅         |
| NeoForge | ✅         |
| Paper    | ✅         |
| Purpur   | ✅         |

---

## ⚙️ Configuration

All configuration is done via **environment variables**.

Example:

```env
EULA=true
TYPE=FABRIC
VERSION=1.21.1
MOTD=Hello Kubernetes
MAX_PLAYERS=20
```

Most `server.properties` options are supported
and mapped automatically at startup.

---

## 📦 Mods / Plugins / Datapacks

* Fabric / Forge / NeoForge: `mods/`
* Paper / Purpur: `plugins/`
* Datapacks: `world/datapacks/`

### S3 / MinIO Sync (Optional)

Supported sync targets:

* Mods
* Configs
* Plugins
* Datapacks
* Optimization mods

Rules:

* User-provided files are **never deleted**
* Optimization mods are **never synced with `--remove`**
* Sync behavior is deterministic and restart-safe

---

## 🧪 Experimental: C2ME Hardware Acceleration

⚠️ **Disabled by default. Experimental feature.**

C2ME hardware acceleration is enabled **only if ALL conditions are met**:

### Requirements

* Image tag: `jre25-experimental`
* Architecture: `x86_64`
* Container runtime (Docker / Kubernetes)
* GPU device available (`/dev/dri` or NVIDIA)
* OpenCL runtime available

### Explicit user consent (ALL required)

```env
ENABLE_C2ME=true
ENABLE_C2ME_HARDWARE_ACCELERATION=true
I_KNOW_C2ME_IS_EXPERIMENTAL=true
```

If **any condition is missing**, C2ME is **forcibly disabled**.

> 🔒 CI and normal environments are always safe.

---

## 🎮 GPU Notes

* GPU support is provided by the **host runtime**
* The container **does not include GPU drivers**
* Devices are injected at runtime (`--gpus` or `nvidia.com/gpu`)

This prevents:

* Driver mismatch issues
* Accidental GPU usage
* CI instability

---

## 🧠 Design Philosophy

* Explicit configuration over abstraction
* One entrypoint, predictable lifecycle
* Safety over convenience
* Experimental features must be impossible to enable accidentally

---

## 📜 License

MIT License.
See [LICENSE](./LICENSE).

---

## ❤️ Credits

Inspired by:

* itzg/docker-minecraft-server
* Kubernetes community
