# Fabric Docker Compose Quick Start

Fabric is for modded Minecraft servers. This example uses Minecraft **26.2** on `runtime-jre25`, the
image's Java 25 runtime tag. On first install the image resolves the current compatible Fabric loader
and installer unless you explicitly set `FABRIC_LOADER_VERSION` or `FABRIC_INSTALLER_VERSION`.

The named `/data` volume persists the world, server configuration, logs, and `/data/mods` without
requiring a host directory to be pre-owned by the container user.

## Start

```fish
git clone https://github.com/AlexanderGG-0520/minecraft-server.git
cd minecraft-server/examples/docker/fabric
docker compose config
docker compose pull
docker compose up -d
docker compose logs --follow
```

Compose creates the service container name from this directory/project and `minecraft` service. The
default image command is `run`. Wait for `Readiness file created`, then connect locally to
`localhost:25565`. The port is intentionally bound to `127.0.0.1`; change the left side of the mapping
to `25565:25565` only for a trusted LAN. Public hosting needs an intentionally configured firewall and
protected ingress, tunnel, or proxy.

## Mods and lifecycle

Put compatible server mod JARs under persistent `/data/mods`. Fabric API is commonly required by Fabric
mods, but its version must match the Minecraft version and your selected mods. Do not assume every
Fabric mod is server-side only: clients may need matching mods. Stop the server before replacing mod
files, then restart and inspect logs. Do not use `/reload` as a replacement for a clean restart.

```fish
docker compose ps
docker compose logs --tail=200
docker compose logs --follow
docker compose stop
docker compose start
docker compose restart
docker compose down
docker compose config --volumes
docker volume ls --filter label=com.docker.compose.project=fabric
docker compose port minecraft 25565
```

The configured `stop_grace_period: 240s` gives the bounded Minecraft-aware shutdown path time to run.
This example enables internal RCON for the save/stop path but does not publish its port; replace the
sample password before any broader deployment. Avoid `docker kill`. `docker compose down` preserves the named volume. `docker compose down -v`
permanently deletes the example world; it is not a backup command and must not be used casually.

## Bind-mount alternative and ownership

If direct host-file access is needed, replace the volume line with `./data:/data`. The current image
runs as UID/GID `10001`; verify it and repair only the dedicated example directory:

```fish
mkdir -p data/mods
docker run --rm --entrypoint id ghcr.io/alexandergg-0520/minecraft-server:runtime-jre25
ls -ld data
sudo chown -R 10001:10001 data
docker compose up -d
```

Use the IDs printed by `id` if a future pinned image differs. Do not use `chmod -R 777` and do not run
recursive ownership changes against a home directory or shared storage root.

## Update and troubleshooting

```fish
docker compose pull
docker compose up -d
docker compose logs --follow
```

This updates the configured image tag; changing `VERSION`, the Fabric loader, or mods is a separate
compatibility change. Create and verify a backup before any of those changes. Confirm the expected
version and readiness log after recreation.

If `/data is not writable`, use `docker compose config` to identify whether you are using the named
volume or a bind mount, inspect the container user with `id`, then inspect `ls -ld data` for the bind
mount. Apply the scoped ownership repair above only to this example's `data` directory.

For an EULA error, make sure `EULA: "true"` remains in Compose and recreate with `docker compose up -d`.
For a busy port, inspect `docker ps --format '{{.Names}} {{.Ports}}'`, change only the host-side port,
then recreate. For startup exits or memory pressure, run `docker compose ps` and
`docker compose logs --tail=200`, find the first error, and lower `JVM_XMX` conservatively. `JVM_XMS`
is initial Java heap and `JVM_XMX` is maximum Java heap; leave host memory for native/runtime overhead.
