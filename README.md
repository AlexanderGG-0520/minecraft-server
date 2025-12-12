# Minecraft Server on Kubernetes

````md
<p align="center">
  <img src="https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-server/build.yml?label=Build&logo=github" />
  <img src="https://img.shields.io/github/license/AlexanderGG-0520/minecraft-server" />
  <img src="https://img.shields.io/github/stars/AlexanderGG-0520/minecraft-server?style=social" />
</p>

<p align="center">
  <b>Production-ready Minecraft Server for Kubernetes</b><br/>
  Helm-native · ArgoCD-friendly · Multi-loader support
</p>

---

## 📘 Documentation

<p align="center">
  <a href="https://alexandergg-0520.github.io/minecraft-server">
    <img src="https://raw.githubusercontent.com/itzg/docker-minecraft-server/master/docs/assets/documentation.png" alt="Documentation"/>
  </a>
</p>

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

## ⚙️ Configuration

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

---

## 📦 Mods & Plugins

* Fabric / Forge / NeoForge: mods auto-detected
* Paper / Purpur: plugins directory
* Optional **S3 sync** for mods & configs

---

## 🔁 GitOps / ArgoCD

This chart is designed to work perfectly with ArgoCD.

```yaml
source:
  repoURL: https://alexandergg-0520.github.io/minecraft-server
  chart: minecraft
```

---

## 🛡 License

MIT License

---

## ❤️ Credits

Inspired by

* itzg/docker-minecraft-server
* Kubernetes & Helm community

