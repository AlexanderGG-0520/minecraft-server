# 📌 README.md

````markdown
# Minecraft Server Helm Chart

Helm Chart for deploying Minecraft servers on Kubernetes with **ArgoCD / GitOps** support.

Supports:
- Vanilla
- Fabric
- Forge
- Paper
- Purpur
- Velocity / Waterfall / BungeeCord

🌟 GPU-enabled via runtimeClassName (nvidia)

---

## 🚀 Quick Start — 5 Minutes to Launch

### 🧰 Prerequisites

✔ Kubernetes cluster  
✔ Helm 3.x  
✔ (Optional) ArgoCD installed  

---

## 🛠️ 1. Add the Chart Repository (optional)

If you publish the chart (see below), users can install like:

```bash
helm repo add mc-server https://your.github.io/mc-server-helm
helm repo update
````

---

## 📁 2. Clone the Repo

```bash
git clone https://github.com/AlexanderGG-0520/minecraft-server
cd minecraft-server/charts/minecraft-server
```

---

## 🍺 3. Install with Helm

Example: Fabric, Minecraft 1.21.10, Java 25

```bash
helm install my-mc-server . \
  --set server.type=fabric \
  --set server.minecraftVersion=1.21.10 \
  --set image.java=25 \
  --set image.tag="java25"
```

---

## 🔐 4. Expose RCON (optional)

```bash
kubectl get secret my-mc-server-minecraft-server-rcon -o jsonpath="{.data.RCON_PASSWORD}" | base64 --decode
```

---

## 🧑‍💻 5. Add Ops / Whitelist

```bash
helm upgrade my-mc-server . \
  --set players.ops[0]=YourName \
  --set players.whitelist.enabled=true \
  --set players.whitelist.users[0]=Friend1
```

---

## 📦 6. Enable S3 Sync

```bash
helm upgrade my-mc-server . \
  --set s3.enabled=true \
  --set s3.endpoint=https://minio.example.com \
  --set s3.bucket=minecraft-mods
```

---

## ✨ 7. GPU Support (nvidia)

```bash
helm upgrade my-mc-server . \
  --set gpu.enabled=true
```

---

## 📊 Check Status

```bash
kubectl get pods
kubectl logs deployment/my-mc-server-minecraft-server
```

---

## 🛠️ Overriding server.properties

Override via values.yaml:

```yaml
minecraft:
  motd: "Welcome to My MC"
  difficulty: hard
```

---

## 📁 PVC Info

```bash
kubectl get pvc
```
