# Minecraft Server Runtime for Docker & Kubernetes

![Docker Build](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-server/publish-ghcr.yml?branch=main)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--server-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Java](https://img.shields.io/badge/java-8%20%7C%2011%20%7C%2017%20%7C%2021%20%7C%2025%20%7C%2025--gpu-orange)
![Kubernetes](https://img.shields.io/badge/kubernetes-ready-blue)

---

## Minecraft Server Runtime for Reproducible, Transparent Operations

This project provides a **production-oriented Minecraft server runtime** designed for **Kubernetes-first environments**.

Unlike traditional “black-box” Minecraft images, this runtime focuses on **transparency, reproducibility, and operational safety**.  
All lifecycle logic (world initialization, mod synchronization, JVM configuration, GPU detection, and reset handling) is implemented as **readable shell scripts**, so operators can always understand *what happens and why*.

This project is ideal for:

- Kubernetes / homelab operators running **persistent Minecraft servers**
- Large or modded servers that require **safe world resets and mod synchronization**
- Users who want **itzg-like simplicity** without sacrificing **observability and control**

While Docker and Docker Compose are supported, **Kubernetes is the primary target**, with PersistentVolumes used for all server data.

---

## Architecture

```mermaid
flowchart TD
    User[Operator / GitOps] -->|deploy / update| K8s[Kubernetes Cluster]

    K8s --> Pod[Minecraft Server Pod]

    Pod --> Init1[init: fix-permissions]
    Pod --> Init2[init: migrate-data]
    Pod --> Init3[init: sync-mods-config]

    Init3 <-->|rsync| MinIO[(MinIO / S3-compatible Storage)]

    Pod --> Runtime[Minecraft Runtime Container]

    Runtime --> Data[(PersistentVolume\n/world /config /mods)]
    Runtime --> JVM[JVM Args Generator]
    Runtime --> GPU[GPU / OpenCL Detection]
    Runtime --> Reset[reset-world.flag]

    Data --> Runtime

---

## Overview

This repository provides a **production-oriented Minecraft server Docker image**
designed for **explicit, reproducible deployments**.

This project intentionally avoids heavy abstractions (such as Helm charts)
in favor of **clear configuration and predictable runtime behavior**.

### Design goals

- Single entrypoint (`entrypoint.sh`)
- Deterministic lifecycle: `preflight → install → runtime`
- ☸️ Kubernetes / Recreate strategy friendly
- ⚙️ Configuration via environment variables (itzg-compatible)
- S3 / MinIO-based mod & config synchronization
- Strictly-guarded experimental features (Java 25 / C2ME)

---

## 📦 Docker Image

## Image name

```md
ghcr.io/alexandergg-0520/minecraft-server:jre-*
```

### Available tags

| Tag                  | Description                      |
| -------------------- | -------------------------------- |
| `runtime-jre8`               | Legacy runtime                   |
| `runtime-jre11`              | Legacy LTS                       |
| `runtime-jre17`              | LTS                              |
| `runtime-jre21`              | **Recommended**                  |
| `runtime-jre25-gpu` | Experimental runtime (C2ME only) |

> ℹ️ Java version is selected **only by the image tag**.
> The container never auto-switches Java versions.

---

## Quick Start

This section shows the minimum steps to run the server, from local Docker testing
to Kubernetes deployment.
For production use, Kubernetes + PersistentVolumes is strongly recommended.

---

### 1. Docker (Local / Testing)

Use Docker for quick testing or local experimentation.

Command example:

```bash
docker run -d \
  --name mc-server \
  -p 25565:25565 \
  -e EULA=true \
  -e TYPE=fabric \
  -e VERSION=1.21.1 \
  -v mc-data:/data \
  ghcr.io/alexandergg-0520/minecraft-server:latest
```

Notes:

- Server data is stored in the mc-data volume
- Suitable for testing only
- No MinIO sync by default

---

### 2. Docker Compose (Single-Node)

For a slightly more structured setup:

Example docker-compose.yml:

```yml
services:
  minecraft:
    image: ghcr.io/alexandergg-0520/minecraft-server:latest
    ports:
      - "25565:25565"
    environment:
      EULA: "true"
      TYPE: "fabric"
      VERSION: "1.21.1"
    volumes:
      - mc-data:/data

volumes:
  mc-data:
```

This mode is still single-node and non-HA, but useful for:

- Small private servers
- Configuration testing
- Debugging startup behavior

---

### 3. Kubernetes (Recommended)

This project is designed primarily for Kubernetes environments.

Key requirements:

- A PersistentVolume for /data
- Optional MinIO or S3-compatible storage for mod/config synchronization

Minimal Deployment example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minecraft-server
spec:
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
        - name: minecraft
          image: ghcr.io/alexandergg-0520/minecraft-server:latest
          ports:
            - containerPort: 25565
          env:
            - name: EULA
              value: "true"
            - name: TYPE
              value: "fabric"
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

## Configuration

This runtime is configured entirely through environment variables.
Most variables are compatible with common Minecraft server images,
but their behavior is intentionally transparent and script-driven.

---

### Core Settings

EULA

- Required
- Set to "true" to accept the Minecraft EULA
- Server will not start unless explicitly accepted

TYPE

- Minecraft server type
- Examples: vanilla, fabric, neoforge, forge, paper
- Determines which server jar and startup logic is used

VERSION

- Minecraft version
- Example: 1.21.1
- Used to resolve the correct server binary

---

### Memory & JVM

MAX_MEMORY

- Maximum heap size for the JVM
- Example: 6G

MIN_MEMORY

- Initial heap size
- Defaults to MAX_MEMORY if not set

JAVA_VERSION

- Major Java version to use
- Default: 21

JVM_OPTS

- Additional JVM arguments appended at runtime
- Useful for tuning GC or experimental flags

---

### Mods & Content

MODS_ENABLED

- Enable mod and config synchronization from MinIO / S3
- Default: false

MODS_S3_BUCKET

- S3 bucket name used for synchronization

MODS_S3_PREFIX

- Path prefix inside the bucket
- Example: servers/fabric/main

MODS_REMOVE_EXTRA

- If true, files not present in MinIO are deleted locally
- Use with caution

---

### World Management

LEVEL

- World directory name
- Default: world

LEVEL_SEED

- World seed id

LEVEL_TYPE

- World type id
- Default: minecraft:default

GENERATE_STRUCTURES

- Generate Structures Setting
- Default: true

---

### GPU / OpenCL (Experimental)

ENABLE_C2ME

- Enable C2ME
- Default: false

ENABLE_C2ME_HARDWARE_ACCELERATION

- Enable C2ME GPU Accelerated / OpenCL detection logic
- Default: true

Note:
GPU acceleration is experimental and only applies to supported mods
such as C2ME. The server will automatically fall back to CPU mode
if no compatible device is detected.

---

### Kubernetes-Specific

UID

- UID used to run the server process
- Useful when combined with securityContext

GID

- GID used to run the server process

DATA_DIR

- Path where all persistent data is stored
- Default: /data

---

### Configuration Notes

- All configuration is evaluated at container startup
- No mutable state is stored in the image itself
- PersistentVolumes are the single source of truth
- Destructive operations always require explicit opt-in

---

## Sync Rules (MinIO / S3)

This runtime supports optional synchronization of mods and configuration files
from MinIO or any S3-compatible storage.
Synchronization is designed to be explicit, predictable, and safe.

---

### Purpose

The sync mechanism exists to:

- Distribute mods and configs reproducibly across servers
- Avoid manual file copying into PersistentVolumes
- Keep container images immutable

It is NOT intended to replace backups.
PersistentVolumes remain the primary source of truth for world data.

---

### Sync Targets

The following directories may be synchronized:

/data/mods
/data/config
/data/datapacks

The world directory is NEVER synchronized.

---

### Sync Direction

Sync is always performed in the following direction:

MinIO / S3  ->  PersistentVolume

Local changes made directly inside the container may be overwritten
on the next restart, depending on configuration.

---

### Timing

Synchronization runs:

- During pod startup
- Before the Minecraft server process is launched

No live or continuous synchronization is performed while the server is running.

---

### Deletion Behavior

By default:

- Files present in MinIO are copied to the PersistentVolume
- Extra local files are preserved

If MODS_SYNC_DELETE_EXTRA is enabled:

- Files not present in MinIO are deleted from the PersistentVolume
- This applies only to synced directories (mods, config, datapacks)

Warning:
Enabling deletion makes MinIO the authoritative source for synced content.
Use this option only when the bucket contents are strictly managed.

---

### Client-Side Mods

Client-side-only mods must NOT be placed in MinIO.
If such mods are synchronized into the server, startup failures may occur.

It is recommended to:

- Maintain a server-only mod set in MinIO
- Validate mod contents before upload

---

### Failure Handling

If synchronization fails:

- The server startup is aborted
- No partial or undefined state is allowed

This prevents starting a server with an inconsistent mod or config set.

---

### Design Guarantees

- World data is never modified by sync logic
- Destructive actions require explicit opt-in
- Sync behavior is deterministic and reproducible
- Operators can always inspect what is being synchronized

---

### Sync Rules Notes

- MinIO / S3 is a distribution source, not a backup system
- PersistentVolumes should be backed up independently
- Sync behavior is intentionally conservative by default

---

## Contributing

Contributions are welcome, but this project prioritizes
**operational safety, transparency, and reproducibility**.

Before opening an issue or pull request, please read the guidelines below.

---

### Philosophy

This project is not a generic Minecraft image.
Changes should align with the following principles:

- Kubernetes-first design
- Immutable images, persistent data
- Explicit and safe operations
- Readable, auditable startup logic

If a change makes behavior less predictable or more implicit,
it is unlikely to be accepted.

---

### Issues

Please open an issue if you:

- Encounter a reproducible bug
- Want to propose a new feature or behavior
- Need clarification on existing behavior

When opening an issue, include:

- Server type (vanilla, fabric, neoforge, etc.)
- Minecraft version
- Container image tag
- Relevant environment variables
- Startup logs, if applicable

Issues without sufficient context may be closed for clarification.

---

### Pull Requests

Pull requests are welcome, especially for:

- Bug fixes
- Documentation improvements
- Startup logic clarity and safety
- Kubernetes-related enhancements

Guidelines:

- Keep changes focused and minimal
- Avoid breaking existing behavior without discussion
- Prefer clarity over cleverness
- Add comments explaining why, not just how

Large behavioral changes should be discussed in an issue first.

---

### Scripts & Style

- Shell scripts must be POSIX-compatible where possib

---

### Persistent Data Layout

All mutable data is stored under /data:

/data
 ├─ world/
 ├─ config/
 ├─ mods/
 ├─ datapacks/
 ├─ logs/
 └─ jvm.args

This layout allows:

- Safe pod restarts
- Version upgrades without data loss
- Controlled world resets

---

### World Reset (Explicit)

To reset the world, create a flag file and restart the pod:

kubectl exec deploy/minecraft-server -- touch /data/reset-world.flag
kubectl rollout restart deploy/minecraft-server

The world will only be reset when this flag is present,
preventing accidental data loss.

---

## Supported Server Types

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

- Fabric / Forge / NeoForge: `mods/`
- Paper / Purpur: `plugins/`
- Datapacks: `world/datapacks/`

### S3 / MinIO Sync (Optional)

Supported sync targets:

- Mods
- Configs
- Plugins
- Datapacks
- Optimization mods

Rules:

- User-provided files are **never deleted**
- Optimization mods are **never synced with `--remove`**
- Sync behavior is deterministic and restart-safe

---

## Experimental: C2ME Hardware Acceleration

⚠️ **Disabled by default. Experimental feature.**

C2ME hardware acceleration is enabled **only if ALL conditions are met**:

### Requirements

- Image tag: `jre25-gpu`
- Architecture: `x86_64`
- Container runtime (Docker / Kubernetes)
- GPU device available (`/dev/dri` or NVIDIA)
- OpenCL runtime available

### Explicit user consent (ALL required)

```env
ENABLE_C2ME=true
ENABLE_C2ME_HARDWARE_ACCELERATION=true
I_KNOW_C2ME_IS_EXPERIMENTAL=true
```

If **any condition is missing**, C2ME is **forcibly disabled**.

> 🔒 CI and normal environments are always safe.

---

## GPU Notes

- GPU support is provided by the **host runtime**
- The container **does not include GPU drivers**
- Devices are injected at runtime (`--gpus` or `nvidia.com/gpu`)

This prevents:

- Driver mismatch issues
- Accidental GPU usage
- CI instability

---

## Design Philosophy

- Explicit configuration over abstraction
- One entrypoint, predictable lifecycle
- Safety over convenience
- Experimental features must be impossible to enable accidentally

---

## License

MIT License.
See [LICENSE](./LICENSE).

---

## Credits

Inspired by:

- itzg/docker-minecraft-server
- Kubernetes community
