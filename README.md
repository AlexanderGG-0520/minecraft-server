# Minecraft Server Docker Image

![Docker Build](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-server/build.yml?branch=main)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--server-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Java](https://img.shields.io/badge/java-8%20%7C%2011%20%7C%2017%20%7C%2021%20%7C%2025--experimental-orange)
![Kubernetes](https://img.shields.io/badge/kubernetes-ready-blue)
![Helm](https://img.shields.io/badge/helm-supported-0f1689)

---

## 📘 Overview

This repository provides a **production-oriented Minecraft server Docker image**
designed for **Kubernetes-first deployments**.

Key goals:

* 🧱 Safe, reproducible runtime (`preflight → install → runtime`)
* ☸️ Kubernetes / Recreate strategy friendly
* ⚙️ Configuration via environment variables (itzg-compatible)
* ☁️ S3 / MinIO-based mod & config synchronization
* 🧪 Strictly-guarded experimental features (C2ME, Java 25)

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
| `jre11`              | Legacy runtime                   |
| `jre17`              | LTS                              |
| `jre21`              | **Recommended (default)**        |
| `jre25-experimental` | Experimental runtime (C2ME only) |

> ℹ️ Java version is selected **only by the image tag**.
> The container does not auto-upgrade or downgrade Java.

---

## 🚀 Quick Start (Helm)

### 1. Add Helm Repository

```bash
helm repo add mc https://alexandergg-0520.github.io/minecraft-server
helm repo update
```

### 2. Install a Server (Fabric example)

```bash
helm install mc mc/minecraft \
  --set server.eula=true \
  --set server.type=FABRIC \
  --set server.version=1.21.10 \
  --set java.maxMemory=6G
```

Your Minecraft server will start using the **Recreate strategy** on Kubernetes.

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

> Proxy servers (Velocity / BungeeCord / Waterfall) are **out of scope**
> and intentionally not handled by this image.

---

## ⚙️ Configuration

All configuration is done via **environment variables**
(either through Helm `values.yaml` or `--set`).

Example:

```yaml
server:
  type: FABRIC
  version: 1.21.10
  eula: true
  motd: "Hello Kubernetes!"

java:
  maxMemory: 6G
```

Most `server.properties` options are supported and mapped automatically.

> 📄 See `values.yaml` for the full list of supported options.

---

## 📦 Mods / Plugins / Datapacks

* Fabric / Forge / NeoForge: `mods/`
* Paper / Purpur: `plugins/`
* Datapacks: `world/datapacks/`

### S3 / MinIO Sync (Optional)

The image supports **read-only sync from S3-compatible storage**:

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

⚠️ **This feature is EXPERIMENTAL and DISABLED by default.**

C2ME hardware acceleration is available **only** when **all** of the following conditions are met:

### Hard requirements

* Image tag: `jre25-experimental`
* Architecture: `x86_64`
* Container runtime (Docker / Kubernetes)
* GPU device available (`/dev/dri` or NVIDIA)
* OpenCL runtime available

### Explicit user consent (ALL required)

```yaml
env:
  ENABLE_C2ME: "true"
  ENABLE_C2ME_HARDWARE_ACCELERATION: "true"
  I_KNOW_C2ME_IS_EXPERIMENTAL: "true"
```

If **any** condition is missing, **C2ME is forcibly disabled**.

> 🔒 The image will never auto-enable C2ME.
> 🔒 CI and normal environments are always safe.

---

## 🎮 GPU Usage Notes

* GPU support is provided by the **host / Kubernetes runtime**
* The container **does not include NVIDIA drivers**
* GPU devices are injected at runtime (`--gpus` or `nvidia.com/gpu`)

This design prevents:

* Driver mismatch issues
* CI instability
* Accidental GPU activation

---

## 🔁 GitOps / ArgoCD

The image and chart are designed to work seamlessly with **ArgoCD**.

```yaml
source:
  repoURL: https://alexandergg-0520.github.io/minecraft-server
  chart: minecraft
```

All behavior is deterministic and restart-safe.

---

## 🧠 Design Philosophy

* **entrypoint.sh only** (no script sprawl)
* Explicit over implicit
* Safety > performance
* Experimental features must be impossible to enable by accident

---

## 📜 License

This project is licensed under the **MIT License**.
See the [LICENSE](./LICENSE) file for details.

---

## ❤️ Credits

Inspired by:

* itzg/docker-minecraft-server
* Kubernetes & Helm community
