# Examples

These manifests are provided as **copy-paste ready examples**.

- No Helm
- No templating
- Explicit configuration only

## Kubernetes

- `fabric-basic.yaml`  
  Minimal Fabric server (CPU)

- `fabric-hardcore-smp.yaml`  
  Hardcore SMP with CPU optimization mods

- `fabric-hardcore-smp-gpu-c2me.yaml`  
  ⚠️ Experimental GPU-accelerated server using C2ME  
  Requires Java 25, GPU node, and explicit consent env vars.

## Docker

- `docker-compose.fabric.yml`  
  Local testing setup

### Mods & Configs

This image does not bundle mods or configs.

All mods and configs are expected to be synced from S3-compatible storage
(e.g. MinIO) using environment variables.

This design avoids accidental deletion, enables GitOps-style asset management,
and is safe for production Kubernetes environments.
