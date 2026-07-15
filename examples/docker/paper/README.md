# Paper Docker Compose Quick Start

Paper is the simplest recommended start for a plugin-based Minecraft server. This example uses
Minecraft **1.21.8** on the image's Java 21 runtime tag, `runtime-jre21`.

It uses a Docker **named volume** at `/data`, so the world, configuration, logs, and plugins survive
container recreation without requiring a host directory to be pre-owned by the container user.

## Start

From a fresh clone, run these fish-compatible commands:

```fish
git clone https://github.com/AlexanderGG-0520/minecartainer.git
cd minecartainer/examples/docker/paper
docker compose config
docker compose pull
docker compose up -d
docker compose logs --follow
```

Compose generates the container name from the directory/project and service name (normally similar to
`paper-minecraft-1`). The service starts the image's default `run` command. Wait for `Readiness file
created` in the logs, then connect from the same computer to `localhost:25565`.

The default binding is deliberately local-only: `127.0.0.1:25565:25565`. For a trusted LAN, change the
left side to your intended host binding, for example `25565:25565`, then run `docker compose up -d`.
Do not expose a beginner server directly to the public Internet; use an intentionally configured
firewall and protected ingress, tunnel, or proxy.

## Everyday commands

```fish
docker compose ps
docker compose logs --tail=200
docker compose logs --follow
docker compose stop
docker compose start
docker compose restart
docker compose down
docker compose config --volumes
docker volume ls --filter label=com.docker.compose.project=paper
docker compose port minecraft 25565
```

`stop`, `restart`, and `down` use the Compose `stop_grace_period: 240s`. This example enables internal
RCON so the image receives TERM, saves through its bounded Minecraft-aware shutdown path, then exits.
RCON is not published as a host port; replace the sample password before any broader deployment. Do not
use `docker kill`. `docker compose down` removes only this Compose project's container and network;
it does **not** remove the named volume. `docker compose down -v` permanently deletes the example
world and is not a backup command—do not use it casually.

## Plugins

Place plugin JAR files in the persistent `/data/plugins` directory. Stop the server before manually
adding or replacing a plugin unless that plugin explicitly documents a safe procedure. `/reload` is
not a substitute for a clean restart.

For direct host access, replace the Compose volume line with `./data:/data`, create only this dedicated
directory, and ensure it belongs to the image runtime user. The current image user is UID/GID `10001`:

```fish
mkdir -p data/plugins
docker run --rm --entrypoint id ghcr.io/alexandergg-0520/minecraft-server:runtime-jre21
ls -ld data
sudo chown -R 10001:10001 data
docker compose up -d
```

Use the IDs printed by `id` if a future pinned image differs. The ownership command is deliberately
scoped to this example's `data` directory. Do not run recursive ownership changes on a home directory
or storage root, and do not use `chmod -R 777`.

## Update safely

```fish
docker compose pull
docker compose up -d
docker compose logs --follow
```

This updates the configured container image tag only. Changing `VERSION` upgrades Minecraft, and
replacing plugins changes server behavior; neither is risk-free. Create and verify a backup before
changing Minecraft versions, plugins, or other server content. Confirm the requested version and
`Readiness file created` in the logs after every change.

## Troubleshooting

### `/data is not writable`

Confirm the active mount with `docker compose config` and inspect the container user with the `id`
command above. The default named volume is initialized from the image's `/data` ownership. If you use
the bind-mount alternative, inspect `ls -ld data` and repair only that directory with the scoped
`sudo chown -R 10001:10001 data` command above. Do not use broad ownership changes or `chmod -R 777`.

### EULA rejected

`EULA` must be exactly `"true"` in `compose.yml`. After changing it, run `docker compose up -d` so
Compose recreates the container configuration.

### Port already allocated

Run `docker compose port minecraft 25565` and inspect the conflicting listener with
`docker ps --format '{{.Names}} {{.Ports}}'`. Change only the host-side port in the mapping, for
example `127.0.0.1:25566:25565`, then run `docker compose up -d` and connect to port `25566`.

### Container exits during startup or lacks memory

Run `docker compose ps` and `docker compose logs --tail=200`; find the first meaningful error instead
of repeatedly restarting. If memory is tight, lower `JVM_XMX` conservatively and restart. `JVM_XMS`
is Java's initial heap and `JVM_XMX` is its maximum heap. Keep `JVM_XMX` below host memory; Java and
native runtime overhead require additional space. If you later add a Compose memory limit, keep it
above the heap plus that overhead.
