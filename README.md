# Minecraft Server (Performance-first)

![Docker Build](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-server/publish.yml?branch=main)
[![Docker Pulls](https://img.shields.io/docker/pulls/alecjp02/minecraft-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-server/)
[![Docker Stars](https://img.shields.io/docker/stars/alecjp02/minecraft-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-server/)
[![GitHub Issues](https://img.shields.io/github/issues-raw/alexandergg-0520/minecraft-server.svg)](https://github.com/alexandergg-0520/minecraft-server/issues)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--server-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Java](https://img.shields.io/badge/java-8%20%7C%2011%20%7C%2017%20%7C%2021%20%7C%2025%20%7C%2025--gpu-orange)
![Kubernetes](https://img.shields.io/badge/kubernetes-ready-blue)

A **minimal, explicit, and predictable** Minecraft server Docker image.

This project is for people who already know *why* feature-rich images sometimes feel slow.

---

## What this is

This repository provides a **performance-first Minecraft server runtime** designed with the following assumptions:

* You understand Docker and Minecraft server internals
* You prefer **explicit configuration over abstraction**
* You value **predictability and speed** over convenience
* You are fine with the server **failing fast** instead of auto-fixing silently

It is especially well-suited for:

* Kubernetes / GitOps environments
* Long-running or frequently recreated servers
* Performance-sensitive world generation
* Advanced modded setups

---

## Kubernetes shutdown recommendations

For reliable shutdown behavior (including Citizens save), we recommend:

* Set `terminationGracePeriodSeconds` to **120s or higher**.
* Add a `preStop` hook when possible (e.g., call `entrypoint.sh rcon-stop`).
* Set `ENABLE_RCON=true` and provide a non-default `RCON_PASSWORD` so shutdown commands can run.

`ENABLE_RCON` defaults to `false`. The image refuses an empty RCON password and also refuses
`RCON_PASSWORD=changeme`.

Minimal Kubernetes pattern:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: minecraft-rcon
type: Opaque
stringData:
  password: replace-with-a-strong-password
---
containers:
  - name: minecraft
    env:
      - name: ENABLE_RCON
        value: "true"
      - name: RCON_PASSWORD
        valueFrom:
          secretKeyRef:
            name: minecraft-rcon
            key: password
    lifecycle:
      preStop:
        exec:
          command: ["/entrypoint.sh", "rcon-stop"]
    readinessProbe:
      exec:
        command: ["test", "-f", "/data/.ready"]
      periodSeconds: 10
      failureThreshold: 3
    volumeMounts:
      - name: data
        mountPath: /data
terminationGracePeriodSeconds: 120
```

The `.ready` file is created only after the runtime survives `READY_DELAY` and is removed during
shutdown. Keep world data on a single-writer PVC and prefer `strategy.type: Recreate` for
Deployments that mount the same world volume.

## Startup hooks (new)

You can run custom scripts at controlled lifecycle points.

Environment variables:

* `HOOKS_ENABLED` (`false` by default)
* `HOOKS_DIR` (`/hooks` by default)
* `HOOKS_STRICT` (`true` by default; if false, failed hooks only log warnings)
* `HOOKS_TIMEOUT_SEC` (`0` by default; if > 0, each hook is terminated after timeout)

Supported hook phases (directory names under `HOOKS_DIR`):

* `pre-install.d` — before install phase starts
* `post-install.d` — after install phase completes
* `pre-runtime.d` — right before launching the server runtime

Only executable files are run.

## Install-only mode (new)

If you only want to execute the install phase and then stop (for pre-warming volumes or CI checks),
set:

* `INSTALL_ONLY=true`

Behavior:

* Runs normal preflight + install
* Skips runtime server launch
* Exits with code `0` when install succeeds

## Server type and flavor notes

Prefer an explicit `TYPE` for new installs. `TYPE=auto` is intended for existing `/data` volumes: it
checks for `velocity.jar`, `fabric-server-launch.jar`, Forge/NeoForge `run.sh`, then `server.jar`, and
falls back to `vanilla` when no known artifact is present. It does not infer the Minecraft `VERSION`.

Set `VERSION` for install and install-only workflows. The runtime fails fast when it cannot safely
match the requested server artifact to the requested `TYPE` and `VERSION`.

Managed install artifact expectations:

* `vanilla`, `paper`, and `purpur` use `/data/server.jar`.
* `fabric` uses `/data/fabric-server-launch.jar`.
* `forge` and `neoforge` install and run through `/data/run.sh`.
* `velocity` uses `/data/velocity.jar` and does not use `server.properties`.

`spigot` appears in runtime-oriented paths that expect `/data/server.jar`, but the entrypoint does not
currently provide a managed Spigot installer. Do not use `TYPE=spigot` for new install workflows unless
you have validated the image behavior for your existing volume.

The installer writes `/data/.server-install.json` for managed artifacts. If an existing artifact has a
marker for a different `TYPE`, `VERSION`, or artifact name, the entrypoint refuses to replace it
automatically. Existing artifacts without a marker are left in place with a warning, so verify legacy
volumes before changing `TYPE` or `VERSION`.

## S3 sync safety notes

The image uses the MinIO `mc` client for S3-backed mods, plugins, configs, datapacks, resourcepacks,
and world archives. `MC_CONFIG_DIR` defaults to `/tmp/mc-config`, so `mc` credentials are not written
under `/data/.mc` on persistent world volumes.

For asset syncs, `*_REMOVE_EXTRA=true` maps to `mc mirror --remove`: local files that are not present
under the selected S3 prefix may be removed. Before running a remove sync, the entrypoint lists the
remote source and fails fast if it is empty, which helps catch bucket or prefix mistakes before local
content is pruned.

Keep S3 prefixes stable for a given world. When changing a prefix, first run with `*_REMOVE_EXTRA=false`
or verify the new prefix contains the expected files. `*_SYNC_ONCE=true` skips a sync when the local
target already has content and remove-extra is not enabled; enabling remove-extra always performs the
sync safety check and mirror operation.

---

## What this is NOT

This project is intentionally **not**:

* Beginner-friendly
* Feature-heavy
* Auto-healing or self-repairing
* A drop-in replacement for general-purpose Minecraft images

If you want a server that "just works" with minimal understanding, this is probably not for you.

## Documentation (Wiki)

This project has **extensive documentation** in the GitHub Wiki.

The Wiki explains not only *how* to run the server, but *why* it is designed this way —  
including lifecycle separation, persistent storage strategy, and world safety guarantees.

### Start here

[Wiki Home](https://github.com/AlexanderGG-0520/minecraft-server/wiki)

### Recommended reading order

1. **Getting Started / Quick Start**  
   Fastest way to run the server safely

2. **Lifecycle Design (Install Phase / Runtime Phase)**  
   Core design philosophy and safety guarantees

3. **Environment Variables**  
   How configuration is classified and applied

4. **World Reset Mechanism**  
   How destructive changes are made explicit and safe

5. **Storage & Persistence**  
   PVC, volume strategy, and migration

6. **FAQ**  
   Differences vs itzg/minecraft-server and common pitfalls

> ⚠️ If you skip the lifecycle documentation,  
> you may misunderstand why some environment variables are intentionally ignored.

### Install-only mode

Run `entrypoint.sh install-only` to execute the install phase and exit without starting the server.
This is intended for explicit init workflows such as Kubernetes init containers.

---

## Credits

This project is inspired by existing Minecraft server images and the broader container ecosystem.

It exists to provide **another option** — not to replace anything.
