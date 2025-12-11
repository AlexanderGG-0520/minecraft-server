# Minecraft Server Runtime (Multi-TYPE, Java 21/25, S3 Sync, K8s-Ready)

A next-generation Minecraft server runtime designed to surpass the capabilities of existing images such as `itzg/minecraft-server`.

This image provides:

* **Multi-TYPE support**
  Fabric / Paper / NeoForge / Forge / Vanilla / Proxy (Velocity, BungeeCord)
* **Java version matrix**
  Java **21 (stable)** and **25 (C2ME & Vector API ready)**
* **Automatic TYPE configuration layering**
  `base → type → user (/data)` layered runtime
* **Multi-arch builds:** `linux/amd64` + `linux/arm64`
* **Automatic server.jar detection & download**
* **S3 (MinIO/R2/S3) mod/config sync**
* **Kubernetes & ArgoCD ready**
  Clean K8s manifests in `deploy/k8s/`
* **Docker Compose support** for local testing

This runtime is created for high-scale, production-grade Minecraft hosting on Kubernetes clusters such as Proxmox + k3s + Oracle Linux / Debian-based nodes.

---

## Features

### Multi-TYPE Server Support

Switch server types via environment variables:

* `TYPE=fabric`
* `TYPE=paper`
* `TYPE=forge`
* `TYPE=neoforge`
* `TYPE=vanilla`
* `TYPE=proxy`

Each TYPE has its own configuration layer under:

* `/opt/mc/<type>/`

These are merged automatically by `entrypoint.sh` while preserving user overrides in `/data`.

---

### Java 21 / 25 Runtime Selection

Select Java at build-time:

* `--build-arg JAVA_VERSION=21`
* `--build-arg JAVA_VERSION=25`

Java 25 is intended for next-generation workloads:

* Vector API
* Project Panama
* C2ME GPU acceleration (future support)

Published image tags:

* `ghcr.io/<owner>/minecraft-server:java21`
* `ghcr.io/<owner>/minecraft-server:java25`
* `ghcr.io/<owner>/minecraft-server:latest` (alias for `java21`)

---

### Config Layering System

This image introduces a layered configuration system:

1. **Base layer**
   `/opt/mc/base/*`
2. **TYPE-specific layer**
   `/opt/mc/<type>/*`
3. **User layer (`/data`)** – highest priority

The runtime copies/merges these layers in order, so you can:

* Set global defaults in `base/`
* Apply TYPE-specific tuning in `fabric/`, `paper/`, etc.
* Persist long-term customizations directly in `/data` (PVC / bind mount)

---

### S3 / MinIO Sync

Before server startup, the container can sync mods/configs automatically from S3-compatible storage:

Environment example:

* `S3_SYNC_ENABLED=true`
* `S3_ENDPOINT=https://minio.example.com`
* `S3_BUCKET=minecraft-mods`
* `S3_PREFIX=fabric-smp`
* `S3_ACCESS_KEY=...`
* `S3_SECRET_KEY=...`

`sync_s3.sh`:

* Fetches remote file list once
* Compares checksums (ETag / SHA1) with local files
* Downloads **only changed files** using parallel workers
* Deletes local files that were removed from S3
  → S3 becomes the **source of truth** for mods/config

This design is optimized for GitOps workflows and large modpacks.

---

### Automatic World Reset

If the file `/data/reset-world.flag` exists at startup, the runtime:

* Deletes the world directory
* Recreates it cleanly
* Removes the flag (optional design)

This is useful for:

* Temporary event servers
* CI / integration testing
* Controlled SMP resets managed via Git or `kubectl exec`

---

### Healthcheck

The container includes `healthcheck.sh`, which can be used with Docker or Kubernetes probes.

It performs checks such as:

* Java PID presence (server process running)
* Minecraft port responsiveness (e.g. 25565)
* Optional RCON responsiveness when `ENABLE_RCON=true`
* Crash signatures in logs (e.g. exceptions in `latest.log`)
* JVM heap usage threshold (e.g. >90% of max)

This helps Kubernetes detect:

* Hard crashes
* Soft-locks
* Out-of-memory situations

---

## Usage (Docker Compose)

Minimal Compose example:

```yaml
services:
mc:
image: ghcr.io/<owner>/minecraft-server:java21
container_name: mc-fabric-smp
environment:
TYPE: fabric
VERSION: latest
MEMORY: 6G
EULA: "true"
S3_SYNC_ENABLED: "true"
S3_ENDPOINT: "[https://minio.example.com](https://minio.example.com)"
S3_BUCKET: "minecraft-mods"
S3_PREFIX: "fabric-smp"
S3_ACCESS_KEY: "YOUR_ACCESS_KEY"
S3_SECRET_KEY: "YOUR_SECRET_KEY"
volumes:
- ./data:/data
ports:
- "25565:25565"
restart: unless-stopped
```

This setup:

* Starts a Fabric server
* Syncs mods/config from S3
* Persists world data in `./data`

---

## Usage (Kubernetes)

The directory `deploy/k8s/` contains production-ready manifests:

* `deployment.yaml`
* `service.yaml`
* `pvc.yaml`
* `config-env.yaml` (ConfigMap)
* `secret-s3.yaml` (S3 credentials)
* optional: `backup-cronjob.yaml`, `hpa.yaml`

Example `env` section in `deployment.yaml`:

env:

```env
* name: TYPE
  value: fabric
* name: VERSION
  value: latest
* name: MEMORY
  value: 6G
* name: EULA
  value: "true"
* name: S3_SYNC_ENABLED
  value: "true"
* name: S3_ENDPOINT
  valueFrom:
  secretKeyRef:
  name: mc-s3
  key: ENDPOINT
* name: S3_BUCKET
  valueFrom:
  secretKeyRef:
  name: mc-s3
  key: BUCKET
* name: S3_PREFIX
  valueFrom:
  secretKeyRef:
  name: mc-s3
  key: PREFIX
* name: S3_ACCESS_KEY
  valueFrom:
  secretKeyRef:
  name: mc-s3
  key: ACCESS_KEY
* name: S3_SECRET_KEY
  valueFrom:
  secretKeyRef:
  name: mc-s3
  key: SECRET_KEY
```

---

## Directory Structure

docker/
base/          # base configuration layer
fabric/        # fabric-specific configs (jvm.args, mc.args, etc.)
paper/         # paper/spigot/bukkit configs
forge/
neoforge/
proxy/
scripts/       # entrypoint, server_download, sync_s3, world_reset, healthcheck

deploy/
k8s/           # Kubernetes manifests (Deployment/Service/PVC/etc.)
compose/       # docker-compose examples

.github/
workflows/     # GitHub Actions (multi-arch, Java21/25 matrix)

---

## Entry Point

`entrypoint.sh` is the core of the runtime. It:

1. Loads base environment defaults from `/opt/mc/base/base.env`
2. Applies TYPE-specific configuration from `/opt/mc/<type>/`
3. Optionally runs S3 sync for mods/config
4. Resolves and downloads `server.jar` using the best available official API
   (Paper API, Fabric meta, Mojang manifest, Forge/NeoForge Maven, Velocity, etc.)
5. Handles world reset via `/data/reset-world.flag`
6. Merges JVM arguments from:

   * `/opt/mc/base/jvm.args`
   * `/opt/mc/<type>/jvm.args`
   * `/data/jvm.override`
7. Merges Minecraft launch arguments from:

   * `/opt/mc/base/mc.args`
   * `/opt/mc/<type>/mc.args`
   * `/data/mc.override`
8. Starts the server via:

   `exec java $(cat /data/jvm.args) -jar /data/server.jar $(cat /data/mc.args)`

The process runs as PID 1, which is ideal for Kubernetes and Docker health checks.

---

## Tags

| Tag      | Description                                |
| -------- | ------------------------------------------ |
| `java21` | Stable recommended runtime                 |
| `java25` | Experimental / SIMD / Panama / C2ME future |
| `latest` | Alias for `java21`                         |

---

## Architecture Support

* `linux/amd64`
* `linux/arm64`

Images are built and pushed as multi-platform manifests using GitHub Actions.

---

## CI / CD (GitHub Actions)

The CI pipeline in `.github/workflows/docker-publish.yml`:

* Builds for both `linux/amd64` and `linux/arm64`
* Uses a matrix for Java versions `21` and `25`
* Pushes images to GHCR:

  * `ghcr.io/<owner>/minecraft-server:java21`
  * `ghcr.io/<owner>/minecraft-server:java25`
  * `ghcr.io/<owner>/minecraft-server:latest` (Java 21)

It uses `buildx` and registry-backed build cache to speed up subsequent builds.

---

## Advanced Usage

### GitOps with ArgoCD

This image is designed to fit naturally into a GitOps workflow.

Basic ArgoCD `Application` example:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
name: minecraft-smp
namespace: argocd
spec:
project: default
source:
repoURL: [https://github.com/](https://github.com/)<owner>/<repo>.git
targetRevision: main
path: deploy/k8s
destination:
server: [https://kubernetes.default.svc](https://kubernetes.default.svc)
namespace: mc-smp
syncPolicy:
automated:
prune: true
selfHeal: true
syncOptions:
- CreateNamespace=true
```

Any changes to the manifests (TYPE, VERSION, MEMORY, S3 profile, etc.) are detected by ArgoCD and applied automatically.

---

### ApplicationSet: Mass-Deploy Multiple Servers

For large setups, you can use ArgoCD ApplicationSet to manage many servers from a single Git repository.

Example directory layout:

deploy/
k8s/          # shared k8s manifests
servers/
smp.yaml
lobby.yaml
snapshot.yaml
hardcore.yaml

Each file under `deploy/servers/` describes a server:\

```yaml
name: smp
type: fabric
version: 1.21.4
memory: 6G
java: 21
s3Profile: fabric-smp

name: lobby
type: paper
version: 1.20.6
memory: 2G
java: 21
s3Profile: paper-lobby

Example ApplicationSet:

apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
name: minecraft-servers
namespace: argocd
spec:
generators:
- git:
repoURL: [https://github.com/](https://github.com/)<owner>/<repo>.git
revision: main
directories:
- path: deploy/servers
template:
metadata:
name: mc-{{name}}
spec:
project: default
source:
repoURL: [https://github.com/](https://github.com/)<owner>/<repo>.git
targetRevision: main
path: deploy/k8s
destination:
server: [https://kubernetes.default.svc](https://kubernetes.default.svc)
namespace: mc-{{name}}
syncPolicy:
automated:
prune: true
selfHeal: true
syncOptions:
- CreateNamespace=true
```

In this model:

* Adding `deploy/servers/new-world.yaml` automatically creates a new server.
* Removing a file deletes the corresponding server.
* Editing YAML updates TYPE / VERSION / MEMORY / Java version.

---

### S3 Layout for Modpacks (Recommended Structure)

Recommended S3 layout (MinIO, R2, or S3):

minecraft-mods/
fabric-smp/
mods/
config/
paper-lobby/
mods/
config/
snapshot/
mods/
config/

Then in your environment:

* `S3_BUCKET=minecraft-mods`
* `S3_PREFIX=fabric-smp` (or `paper-lobby`, `snapshot`, etc.)

This allows you to:

* Reuse the same image for many different modpacks
* Manage all modpacks declaratively via S3 + Git
* Use the same deployment templates and only change `S3_PREFIX`

---

### Backup & Restore Strategy (Kubernetes)

You can define a `CronJob` that archives the world directory and uploads it to S3:

* Run daily at off-peak hours (e.g. `0 4 * * *`)
* tar.gz `/data/world`
* Upload to `s3://minecraft-backups/<server-name>/YYYY-MM-DD_HH-MM-SS.tar.gz`

Restore can be performed by:

1. Stopping the server (scale Deployment to 0)
2. Extracting the backup into `/data/world`
3. Scaling back up (Deployment to 1)

This pairs well with:

* `WORLD_RESET_POLICY` flags
* `/data/reset-world.flag`

---

### JVM Flags & Tuning

You can:

* Put default JVM flags into `/opt/mc/base/jvm.args`
* TYPE-specific tuning into `/opt/mc/<type>/jvm.args`
* User-specific or advanced overrides into `/data/jvm.override`

The final JVM flags will be:

base/jvm.args + type/jvm.args + /data/jvm.override

Examples:

* Use G1GC for Paper
* Use ZGC or Shenandoah for Fabric + C2ME
* Enable Vector API / Panama for Java 25

---

## License

MIT License.
You may freely fork, modify, host, or redistribute.
