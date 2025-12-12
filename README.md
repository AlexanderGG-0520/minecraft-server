# Minecraft Server Docker Image

![Docker Build](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-server/build.yml?branch=main)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--server-blue)
![Docker Pulls](https://img.shields.io/badge/pulls-private-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)
![Java](https://img.shields.io/badge/java-8%20%7C%2011%20%7C%2016%20%7C&2017%20%7C%2021%20%7C%2025-orange)
![Kubernetes](https://img.shields.io/badge/kubernetes-ready-blue)
![Helm](https://img.shields.io/badge/helm-supported-0f1689)

---

## 📘 Documentation

You will find things like:

- 🚀 Quick start with **Helm**
- 🔄 Switching **Minecraft versions & server types**
- ⚙️ Configuring `server.properties` via **environment variables**
- 📦 Mods / Plugins sync (Fabric / Forge / Paper / Purpur)
- ☁️ S3-based mod & config synchronization
- 🎮 GPU-ready (OpenCL / CUDA aware)
- 🔁 GitOps-ready with **ArgoCD**

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

That’s it.
Your Minecraft server is now running on Kubernetes 🎉

---

## 🧱 Supported Server Types

| Type       | Supported |
| ---------- | --------- |
| Vanilla    | ✅         |
| Fabric     | ✅         |
| Forge      | ✅         |
| NeoForge   | ✅         |
| Paper      | ✅         |
| Purpur     | ✅         |
| Velocity   | ✅         |
| BungeeCord | ✅         |
| Waterfall  | ✅         |

---

## ☕ Java Version

Java version is selected by the **Docker image tag**.

Supported tags:

- `java8`
- `java11`
- `java17`
- `java21` (recommended)
- `java25` (C2ME GPU Accelerated)

Example:

```yaml
image:
  tag: java21
```

---

## ⚙️ Configuration

> ℹ️ `server.type` is case-insensitive  
> (`fabric`, `FABRIC`, `Fabric` are all valid)
>
> Recommended: use **uppercase** values (FABRIC, FORGE, PAPER).

All configuration is done via **values.yaml** or Helm `--set`.

```yaml
server:
  type: FABRIC
  version: 1.21.10
  eula: true
  motd: "Hello Kubernetes!"

java:
  maxMemory: 6G
```

Most `server.properties` options are supported via environment variables
(compatible with itzg/docker-minecraft-server).

> 📄 See `values.yaml` for all available configuration options and defaults.

---

## 📦 Mods & Plugins

- Fabric / Forge / NeoForge: mods auto-detected
- Paper / Purpur: plugins directory
- Optional **S3 sync** for mods & configs

---

## ⚡ GPU Acceleration (Experimental)

This chart supports **experimental GPU acceleration** using  
**C2ME OpenCL optimizations**.

> ⚠️ Disabled by default  
> Requires OpenCL runtime and compatible GPU drivers

### Enable OpenCL acceleration

```bash
helm install mc mc/minecraft \
  --set performance.opencl.enabled=true

---

## 🔁 GitOps / ArgoCD

This chart is designed to work perfectly with ArgoCD.

```yaml
source:
  repoURL: https://alexandergg-0520.github.io/minecraft-server
  chart: minecraft
```

---

## 📜 License

This project is licensed under the **MIT License**.

See the [LICENSE](./LICENSE) file for details.

---

## ❤️ Credits

Inspired by

- itzg/docker-minecraft-server
- Kubernetes & Helm community
