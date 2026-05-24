# Minecraft Server

![Docker Build](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-server/publish.yml?branch=main)
[![Docker Pulls](https://img.shields.io/docker/pulls/alecjp02/minecraft-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-server/)
[![Docker Stars](https://img.shields.io/docker/stars/alecjp02/minecraft-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-server/)
[![GitHub Issues](https://img.shields.io/github/issues-raw/alexandergg-0520/minecraft-server.svg)](https://github.com/alexandergg-0520/minecraft-server/issues)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--server-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Java](https://img.shields.io/badge/java-8%20%7C%2011%20%7C%2017%20%7C%2021%20%7C%2025%20%7C%2025--gpu-orange)
![Kubernetes](https://img.shields.io/badge/kubernetes-ready-blue)

Predictable Minecraft server Docker image for Kubernetes, GitOps, and S3/MinIO-backed asset workflows.

This image is built for operators who want Minecraft server containers to behave predictably when pods
are recreated, volumes are reused, and assets are supplied from object storage. It favors explicit
configuration, a clear install/runtime lifecycle, safe persistent volume handling, RCON-based graceful
shutdown, and fail-fast errors instead of silent auto-repair.

It can sync mods, plugins, configs, datapacks, resourcepacks, and world archives from S3-compatible
storage such as MinIO. The goal is not to be the most feature-heavy Minecraft image; the goal is to make
operational state, lifecycle boundaries, and unsafe conditions visible enough for Kubernetes and GitOps
workflows.

---

## Why this image?

| Operational need | How this image handles it |
|---|---|
| Kubernetes pod recreation | Separates install-time work from runtime launch so recreated pods behave predictably. |
| Persistent world volumes | Treats existing world data cautiously and fails fast on unsafe or mismatched state. |
| S3/MinIO asset management | Syncs mods, plugins, configs, datapacks, resourcepacks, and world archives from S3-compatible storage. |
| Graceful shutdown | Supports RCON-based shutdown flows for safer saves before container termination. |
| GitOps workflows | Uses explicit environment-driven behavior instead of hidden auto-repair. |
| Advanced server types | Supports managed or bring-your-own workflows for common Java server types. |

This image is intended for operators who care more about predictable lifecycle behavior than maximum
automatic convenience.

---

## Quick links

* [Examples](examples/README.md)
* [Wiki](https://github.com/AlexanderGG-0520/minecraft-server/wiki)
* [Environment Variables](https://github.com/AlexanderGG-0520/minecraft-server/wiki/Environment-Variables)
* [S3/MinIO safety notes](#s3-sync-safety-notes)
* [Kubernetes shutdown recommendations](#kubernetes-shutdown-recommendations)
* [Install-only mode](#install-only-mode-new)

---

## Why this exists

General-purpose Minecraft Docker images are convenient, especially for local Docker Compose or
single-host servers where the container is configured once and then left running. Kubernetes makes
different trade-offs more visible: repeated pod recreation, GitOps-driven redeploys, persistent volume
safety, lifecycle hook ordering, graceful shutdown timing, and object-storage-backed asset delivery.

This image optimizes for explicit lifecycle, reproducibility, and safe failure modes. Install-time work
is separated from runtime launch, persistent world data is treated cautiously, destructive actions are
made explicit, and mismatched or unsafe state should fail loudly before the server mutates important
data.

This is an alternative for advanced/containerized operations, not a universal replacement for every
Minecraft server image. If another image matches your workflow better, that is a valid choice; this
project exists for teams and operators who prefer explicit configuration and predictable failures over
large amounts of hidden automation.

---

## Who should use this

This project is a good fit when you:

* Run Minecraft servers on Kubernetes or through GitOps workflows.
* Reuse persistent volumes and need conservative world-data handling.
* Sync mods, plugins, configs, datapacks, resourcepacks, or world archives from S3/MinIO.
* Operate advanced modded servers and want lifecycle behavior to be explicit.
* Prefer predictable errors over silent repair when configuration or storage state is unsafe.

This project is probably not the best fit when you:

* Are new to Minecraft server hosting and want the shortest path to a working server.
* Want every feature automatically detected, installed, or repaired for you.
* Prefer silent auto-repair over fail-fast errors that require manual review.

## CI and smoke coverage

CI is split by responsibility:

* **Lint and Static Smoke** runs `bash -n entrypoint.sh` and `shellcheck -x -s bash entrypoint.sh`.
* **Runtime Smoke CI** builds `runtime-jre21`, checks `/entrypoint.sh` inside the image, and runs
  runtime behavior regressions for install-only, RCON safety, `TYPE=auto`, Spigot bring-your-own
  artifacts, and install marker mismatch handling.

---

## Experimental Modrinth `.mrpack`

Modrinth `.mrpack` install support is being introduced in phases. The current
experimental path supports local `file://` test downloads only when
`MODPACK_ALLOW_FILE_URL=true` is explicitly set. Production HTTPS downloads are
planned for a later PR.

`MODPACK_REMOVE_EXTRA=true`, CurseForge packs, direct zip packs, world installs,
and TYPE/VERSION inference are not supported. Modpack paths are restricted so
world data, `server.properties`, `eula.txt`, `ops.json`, and `whitelist.json`
are not written by this feature.

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
uses `/data/.server-install.json` when a managed install marker and its artifact are present. Without a
usable marker, it checks for `velocity.jar`, `fabric-server-launch.jar`, Forge/NeoForge `run.sh`, then
`server.jar`, and falls back to `vanilla` when no known artifact is present. It does not infer the
Minecraft `VERSION`.

Set `VERSION` for install and install-only workflows. The runtime fails fast when it cannot safely
match the requested server artifact to the requested `TYPE` and `VERSION`.

Managed install artifact expectations:

* `vanilla`, `paper`, and `purpur` use `/data/server.jar`.
* `fabric` uses `/data/fabric-server-launch.jar`.
* `forge` and `neoforge` install and run through `/data/run.sh`.
* `velocity` uses `/data/velocity.jar` and does not use `server.properties`.

`TYPE=spigot` can run an existing `/data/server.jar`, but the entrypoint does not currently provide a
managed Spigot installer. It fails fast if `TYPE=spigot` is selected without an existing artifact.

The installer writes `/data/.server-install.json` for managed artifacts. If an existing artifact has a
marker for a different `TYPE`, `VERSION`, or artifact name, the entrypoint refuses to replace it
automatically. Existing artifacts without a marker are left in place with a warning, so verify legacy
volumes before changing `TYPE` or `VERSION`.

## UUID cache safety notes

`OPS_USERS` and `WHITELIST_USERS` generation uses `/data/uuid_cache.json` to cache Mojang UUID lookups.
The cache must be a JSON object. If the file is corrupted or contains another JSON type, startup fails
fast with the cache path and does not print the file contents. Fix the JSON manually or remove the cache
file to let it be regenerated; the entrypoint does not auto-repair it.

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

## Documentation

This project has **extensive documentation** in the GitHub Wiki.

The Wiki explains not only *how* to run the server, but *why* it is designed this way:
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

The lifecycle documentation is recommended reading before changing install or runtime environment
variables, because some variables are intentionally scoped to only one phase.

### Install-only mode

Run `entrypoint.sh install-only` to execute the install phase and exit without starting the server.
This is intended for explicit init workflows such as Kubernetes init containers.

---

## Credits

This project is inspired by existing Minecraft server images and the broader container ecosystem.

It exists to provide **another option** — not to replace anything.
