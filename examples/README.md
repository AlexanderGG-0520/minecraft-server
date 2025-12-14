# GPU / OpenCL Example (C2ME + Minecraft Server)

This directory contains **example configurations and notes** for running  
a Minecraft server with **C2ME OpenCL acceleration** inside containers.

> ⚠️ This setup is **practical-first**, not theoretical.
> If it runs stably and accelerates worldgen, it is considered **successful**.

---

## TL;DR

- **`clinfo` failing ≠ OpenCL unusable**
- **Host provides the NVIDIA driver**
- **Container provides CUDA / OpenCL runtime**
- **The final judge is the Minecraft server log**, not preflight tools

---

## Architecture Overview

```text
Host OS
 └─ NVIDIA Driver (kernel + user-space)
     └─ container runtime (CRI-O / containerd / Docker)
         └─ CUDA Runtime Image
             └─ OpenCL ICD loader (libOpenCL.so)
                 └─ Minecraft + C2ME OpenCL
````

**Responsibility split matters**:

| Layer     | Responsibility                                    |
| --------- | ------------------------------------------------- |
| Host      | NVIDIA driver, kernel modules                     |
| Runtime   | GPU device injection (`nvidia-container-runtime`) |
| Container | CUDA, OpenCL loader, Java                         |
| App       | C2ME OpenCL usage                                 |

---

## About `clinfo`

### Important ⚠️

`clinfo` is **NOT a reliable success indicator** in containerized GPU setups.

Observed behavior:

- `clinfo` may:

  - segfault
  - report no platforms
  - exit with non-zero status
- **Minecraft + LWJGL OpenCL may still work perfectly**

Why?

- `clinfo` uses a different OpenCL discovery path
- NVIDIA OpenCL ICD is optimized for CUDA-facing workloads
- LWJGL loads OpenCL dynamically and more defensively

✅ **If Minecraft logs show OpenCL devices, you’re good.**

---

## What Actually Matters

### ✅ Good (This means success)

Minecraft log contains lines like:

```text
Found OpenCL platform NVIDIA CUDA
Found OpenCL device NVIDIA GeForce GTX 1660 SUPER
OpenCL codegen for world minecraft:overworld finished
Compiling program for device OpenCL Device NVIDIA GeForce GTX 1660 SUPER
```

### ❌ Bad (This is a real failure)

- JVM crash in native code
- `libOpenCL.so` missing entirely
- No OpenCL logs **inside Minecraft**

---

## CUDA Version Notes

- **Do NOT blindly use the latest CUDA image**
- New CUDA runtimes can crash with older-but-stable drivers
- This is especially visible with:

  - `libnvidia-ptxjitcompiler.so`
  - OpenCL JIT compilation

### Recommendation

- Keep **host driver stable**
- Pin **CUDA runtime image** to a known-good version
- Treat CUDA updates as **breaking changes**

> Stability > novelty

---

## Kubernetes Notes

- `runtimeClassName: nvidia` is required
- `nvidia.com/gpu` resource must be requested
- Works with **CRI-O**, **containerd**, and **Docker**

Example snippet:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
runtimeClassName: nvidia
```

---

## Philosophy

This setup intentionally prioritizes:

- Real-world stability
- Deterministic behavior
- Clear failure boundaries

It is **not** designed to:

- Pass every diagnostic tool
- Maximize theoretical GPU feature coverage
- Chase the newest CUDA release

If your server boots, worldgen is accelerated, and it stays up:

**You already won.**

---

## Known Trade-offs

- `clinfo` may be unreliable
- OpenCL feature set may be partially disabled
- Some GPU generations lack full OpenCL 3.0 support

These are acceptable compromises for **production servers**.

---

## Directory

```text
example/
├── README.md
└── kubernetes/
    └── fabric-hardcore-smp-gpu.yaml
```

---

## `example/kubernetes/fabric-hardcore-smp-gpu.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fabric-hardcore-smp-gpu
  namespace: mc-server
spec:
  replicas: 1

  # World data + GPU workloads should not be parallelized blindly
  strategy:
    type: Recreate

  selector:
    matchLabels:
      app: fabric-hardcore-smp-gpu

  template:
    metadata:
      labels:
        app: fabric-hardcore-smp-gpu

    spec:
      # --------------------------------------------------
      # NVIDIA runtime (CRI-O / containerd / Docker)
      # --------------------------------------------------
      runtimeClassName: nvidia

      # --------------------------------------------------
      # Security context
      # --------------------------------------------------
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000

      # --------------------------------------------------
      # GPU node selection
      # --------------------------------------------------
      nodeSelector:
        nvidia.com/gpu.present: "true"

      containers:
        - name: minecraft
          image: ghcr.io/alexandergg-0520/minecraft-server:runtime-jre25-gpu
          imagePullPolicy: Always

          ports:
            - containerPort: 25565

          # --------------------------------------------------
          # Environment variables
          # --------------------------------------------------
          env:
            # --- Required ---
            - name: EULA
              value: "true"

            - name: TYPE
              value: "fabric"

            - name: VERSION
              value: "1.21.10"

            - name: HARDCORE
              value: "true"

            - name: SERVER_PORT
              value: "25565"

            - name: MAX_MEMORY
              value: "15Gi"

            - name: MOTD
              value: "§a[Fabric Hardcore SMP] §cOne death. One chance."

            # --------------------------------------------------
            # JVM tuning
            # --------------------------------------------------
            - name: JVM_XMS
              value: "8G"
            - name: JVM_XMX
              value: "8G"

            # --------------------------------------------------
            # S3 / MinIO (mods & configs)
            # --------------------------------------------------
            - name: S3_ENDPOINT
              value: https://minio.example.com

            - name: S3_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: minio-minecraft-creds
                  key: access-key

            - name: S3_SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: minio-minecraft-creds
                  key: secret-key

            # --------------------------------------------------
            # Mods
            # --------------------------------------------------
            - name: MODS_ENABLED
              value: "true"
            - name: MODS_S3_BUCKET
              value: minecraft-assets
            - name: MODS_S3_PREFIX
              value: fabric/hardcore/mods
            - name: MODS_SYNC_ONCE
              value: "true"
            - name: MODS_REMOVE_EXTRA
              value: "false"

            # --------------------------------------------------
            # Configs
            # --------------------------------------------------
            - name: CONFIGS_ENABLED
              value: "true"
            - name: CONFIGS_S3_BUCKET
              value: minecraft-assets
            - name: CONFIGS_S3_PREFIX
              value: fabric/hardcore/config
            - name: CONFIGS_SYNC_ONCE
              value: "true"

            # --------------------------------------------------
            # Optimization mods (CPU-side)
            # --------------------------------------------------
            - name: OPTIMIZE_MODE
              value: force
            - name: OPTIMIZE_S3_BUCKET
              value: minecraft-assets
            - name: OPTIMIZE_S3_PREFIX
              value: optimize/fabric

            # --------------------------------------------------
            # C2ME OpenCL (EXPERIMENTAL)
            # --------------------------------------------------
            - name: ENABLE_C2ME
              value: "true"
            - name: ENABLE_C2ME_HARDWARE_ACCELERATION
              value: "true"
            - name: I_KNOW_C2ME_IS_EXPERIMENTAL
              value: "true"

            # --------------------------------------------------
            # NVIDIA / OpenCL runtime
            # --------------------------------------------------
            - name: NVIDIA_VISIBLE_DEVICES
              value: "all"
            - name: NVIDIA_DRIVER_CAPABILITIES
              value: "all"
            - name: LD_LIBRARY_PATH
              value: /usr/lib/x86_64-linux-gnu:/usr/local/nvidia/lib:/usr/local/nvidia/lib64

          # --------------------------------------------------
          # Volumes
          # --------------------------------------------------
          volumeMounts:
            - name: data
              mountPath: /data

            # Host OpenCL vendor ICDs (required for NVIDIA OpenCL)
            - name: opencl-vendors
              mountPath: /etc/OpenCL/vendors
              readOnly: true

          # --------------------------------------------------
          # Resources
          # --------------------------------------------------
          resources:
            requests:
              cpu: "4"
              memory: "8Gi"
              nvidia.com/gpu: "1"
            limits:
              cpu: "8"
              memory: "16Gi"
              nvidia.com/gpu: "1"

      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: fabric-hardcore-smp-gpu-data

        # Host-provided OpenCL ICDs
        - name: opencl-vendors
          hostPath:
            path: /etc/OpenCL/vendors
            type: Directory
```

---

## `example/README.md`（Kubernetes Example用）

````md
# Kubernetes GPU Example (Minecraft + C2ME OpenCL)

This example demonstrates how to run a **Fabric Minecraft server**
with **C2ME OpenCL acceleration** on Kubernetes.

It is designed for **real-world stability**, not theoretical purity.

---

## Requirements

- NVIDIA GPU node
- NVIDIA driver installed on host
- NVIDIA Device Plugin running
- `runtimeClassName: nvidia`
- Host provides `/etc/OpenCL/vendors`

Tested with:
- CRI-O
- containerd
- NVIDIA Container Runtime

---

## Why `/etc/OpenCL/vendors` Is Mounted

NVIDIA OpenCL requires an **ICD vendor file** such as:

```text
/etc/OpenCL/vendors/nvidia.icd
````

This file is provided by the **host driver**, not the container.

Without this mount:

- `libOpenCL.so` may exist
- OpenCL platforms will NOT be discovered

---

## About clinfo

`clinfo` may:

- crash
- report no platforms
- exit with non-zero status

This is **expected** in some container + CUDA combinations.

**Do not use clinfo as a success check.**

Instead, check Minecraft logs for:

```text
Found OpenCL platform NVIDIA CUDA
Compiling program for device OpenCL Device NVIDIA ...
```

---

## CUDA Version Strategy

- Host driver: **keep stable**
- CUDA image: **pin to known-good version**
- Avoid newest CUDA unless tested

Newer CUDA runtimes can break:

- OpenCL JIT
- `libnvidia-ptxjitcompiler.so`

---

## Warning

C2ME OpenCL is **experimental**.

Use at your own risk.

---

## Final Note

If you are debugging this setup:

> Trust **Minecraft logs**, not auxiliary tools.

Everything else is just noise.
