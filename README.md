# Minecraft Server Docker Image

![Docker Build](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-server/build.yml?branch=main)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--server-blue)
![Docker Pulls](https://img.shields.io/badge/pulls-private-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)
![Java](https://img.shields.io/badge/java-8%20%7C%2011%20%7C%2016%20%7C%2017%20%7C%2021%20%7C%2025-orange)
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

## 🎮 CPU vs GPU (c2me-gpu)

This chart supports **CPU and GPU optimized images**.

| Variant | Image Tag        | Acceleration | Requirements |
| ------ | ---------------- | ------------ | ------------ |
| CPU    | `java25-cpu`     | ❌ None       | Any node |
| GPU    | `java25-gpu`     | ✅ OpenCL     | GPU + OpenCL |

### GPU Notes

- GPU acceleration is **opt-in**
- Requires OpenCL-compatible drivers
- Designed for `c2me-opts-accel-opencl`
- CPU nodes will **not crash** (separate image)

### Example (GPU)

```bash
helm install mc-gpu mc/minecraft \
  --set image.variant=gpu \
  --set performance.opencl.enabled=true \
  --set nodeSelector."nvidia\.com/gpu.present"="true"

---

## 🔁 GitOps / ArgoCD

This chart is designed to work perfectly with ArgoCD.

```yaml
source:
  repoURL: https://alexandergg-0520.github.io/minecraft-server
  chart: minecraft
```

---

## 🚀 **Unique GPU Acceleration for Minecraft**

### **Experience Lightning Fast Performance with C2ME OpenCL Optimizations**

- **GPU-Accelerated Performance**: Unlock superior performance with experimental GPU acceleration using **C2ME OpenCL optimizations**. Ideal for high-performance servers running Minecraft at scale!

- **Opt-In for OpenCL**: Easy-to-enable GPU acceleration with no need for a CPU-intensive setup. Simply set `performance.opencl.enabled=true` to boost your server with compatible GPU drivers.

- **CPU & GPU Optimized**: Choose between a **CPU-only** or **GPU-accelerated** server setup depending on your hardware needs. Great for servers running on both GPU and non-GPU nodes without any crashes.

---

## 💡 **Why GPU-Optimized Minecraft Servers?**

### **Game-Changing Performance**

By using a GPU to accelerate the server, you can handle more intensive calculations, such as chunk loading and world generation, **offloading work from the CPU**. This leads to smoother gameplay, faster world generation, and reduced lag during heavy load times.

- **OpenCL-Compatible GPUs**: With **OpenCL** support, you can take advantage of modern NVIDIA or AMD GPUs for server-side calculations. Get ready for a **reliable performance boost** and **faster server response times**.

- **No Downtime for Non-GPU Nodes**: The architecture is designed to work seamlessly whether you are using **GPU nodes** or **CPU-only** nodes. No crashing issues when switching between the two.

---

## 🖥️ **Easy to Set Up with Kubernetes**

This **Helm Chart** provides a quick and simple way to deploy your Minecraft server to Kubernetes, with support for both **GPU and CPU variants**. Here's how:

1. **Deploy GPU-Optimized Server**:

   ```bash
   helm install mc-gpu mc/minecraft \
     --set image.variant=gpu \
     --set performance.opencl.enabled=true \
     --set nodeSelector."nvidia\.com/gpu.present"="true"
   ```

2. **CPU-Only Server Setup**:

   ```bash
   helm install mc mc/minecraft \
     --set server.eula=true \
     --set server.type=FABRIC \
     --set server.version=1.21.10 \
     --set java.maxMemory=6G
   ```

Whether you want **GPU acceleration** or **classic CPU performance**, this chart makes it easy to get started!

---

## 🌐 **Mod/Plugin Sync & S3 Integration**

- Seamlessly sync **mods** and **plugins** across your Minecraft server with built-in **S3 support** for Fabric, Forge, and Paper.
- Automatically sync with **remote repositories** and eliminate manual file updates.

---

## 🎮 **Streamlined for Game Performance**

This Docker image is designed to meet the performance needs of **high-traffic servers**. By offloading the **heavy lifting to GPUs**, you ensure a **stable, lag-free gaming experience** for players.

---

## 🔄 **Fully Compatible with ArgoCD for GitOps**

- Designed with **GitOps** in mind, you can integrate this server with **ArgoCD** for **automated deployments** and **version-controlled configurations**.

```yaml
source:
  repoURL: https://alexandergg-0520.github.io/minecraft-server
  chart: minecraft
```

---

### **Get Started Quickly with Kubernetes & Helm**

Deploying a **Minecraft server with GPU support** has never been easier. Just follow the quick start steps, and you'll have your server up and running on **Kubernetes** in no time.

---

## 💬 **Join the Conversation**

Get support, report issues, and contribute to the project on GitHub:
[**Minecraft Server Docker on GitHub**](https://github.com/alexandergg-0520/minecraft-server)

---

### 💡 **Make Your Minecraft Server Faster and Smarter with GPU Acceleration**

This isn't just another Minecraft Docker image. It’s a **performance powerhouse**, designed for those who want the absolute best in server speed and scalability. Get your **GPU-ready server** today!

---

## 📜 License

This project is licensed under the **MIT License**.

See the [LICENSE](./LICENSE) file for details.

---

## ❤️ Credits

Inspired by

- itzg/docker-minecraft-server
- Kubernetes & Helm community
