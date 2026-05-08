# entrypoint.sh staged responsibility plan

`entrypoint.sh` is currently both the orchestration layer and the implementation
home for unrelated bootstrapping concerns. The immediate goal is to define stable
responsibility boundaries before moving substantial behavior.

This is not a literal MVC split. The useful analogy is:

- `entrypoint.sh`: controller/orchestration. It should make the boot order easy to
  read: preflight, type resolution, install/bootstrap, optional install-only exit,
  then runtime launch.
- `scripts/lib/*.sh`: service/domain responsibilities. Each file should answer how
  one bootstrapping area works.
- environment variables and filesystem state: runtime configuration/state.

## Current pain points

- Cross-cutting helpers such as logging, S3 client setup, runtime type decisions,
  server property bootstrap, world reset, and world install are mixed with install
  order and runtime launch.
- Related behavior is split across distant locations. For example,
  `ensure_server_properties`, `bootstrap_server_properties`, `install_world`,
  `reset_world`, and runtime dispatch are far apart from their surrounding policy.
- Some functions are too coupled to move safely in one step because they share
  globals such as `TYPE`, `DATA_DIR`, `JVM_ARGS_FILE`, `MC_CONFIG_DIR`, and the log
  helpers.
- Docker packaging copied only `/entrypoint.sh` before the first extraction, so
  any library split must keep image packaging updated at the same time.

## Proposed boundaries

### Logging / timestamps

Suggested file: `scripts/lib/logging.sh`

Status: completed. `entrypoint.sh` now sources `scripts/lib/logging.sh`, and
Docker image packaging includes `scripts/lib`.

Owns:

- `LOG_TZ` and `LOG_TS_FORMAT` defaults.
- timestamp formatting via `ts`.
- `log` and `die`.

This is the safest first extraction because it has no dependency on install state,
server type, S3 configuration, or filesystem layout.

### Runtime type resolution

Suggested file: `scripts/lib/runtime.sh`

Owns:

- Supported runtime type lists and validation.
- `TYPE=auto` marker/artifact resolution.
- Runtime-specific launch command selection.

Do not move all runtime behavior immediately. `runtime` currently depends on
`run_server`, shutdown/RCON state, `JVM_ARGS_FILE`, and install marker helpers.
Extract after introducing small helper functions such as `is_supported_type` and
`server_runtime_family`, then move dispatch once call sites are stable.

### Server properties bootstrap

Suggested file: `scripts/lib/server_properties.sh`

Owns:

- Deciding whether a runtime uses `server.properties`.
- `ensure_server_properties`.
- `bootstrap_server_properties`.
- Server-property diff/application helpers once their env contract is documented.

Move cautiously because property bootstrap intentionally launches server artifacts
with short timeouts and has runtime-specific behavior for vanilla, Paper-family,
Fabric, Forge, and NeoForge.

### World install

Suggested file: `scripts/lib/world_install.sh`

Status: current staged boundary completed for world installation only.
`install_world` has moved, but `reset_world` and `handle_reset_world_flag` have
not moved and reset behavior remains owned by `entrypoint.sh` for now.

Owns:

- World zip download/extract/install behavior.
- Validation of extracted world layout.

`reset_world` and `handle_reset_world_flag` should move later as their own staged
boundary. They delete and recreate directories, so that migration should include
a focused smoke test around missing flags, expired flags, and existing world skip
behavior.

### S3 / MinIO client handling

Suggested file: `scripts/lib/s3_client.sh`

Status: completed current staged boundary. This extraction is limited to the
client mechanics needed by existing call sites; world install and reset behavior
remain in `entrypoint.sh` until the later world-install boundary.

Owns:

- `mc` alias configuration.
- S3 endpoint/access/secret validation.
- Shared S3 source safety checks before remove sync.
- Future MinIO `mc` dependency remediation boundary.

This is a good second extraction after logging. It is small, but it is used by
mods, plugins, configs, datapacks, resourcepacks, and world install, so the first
move should be mechanical only.

## Suggested migration order

1. Extract logging/timestamps and package the new library in Docker images. Done.
2. Extract S3 client helpers with no call-site behavior changes. Done.
3. Extract world installation only; leave reset behavior in `entrypoint.sh`. Done.
4. Introduce runtime type predicate helpers in `runtime.sh`, then migrate
   preflight validation and `TYPE=auto` resolution.
5. Move server property bootstrap functions after the runtime predicates exist.
6. Move world reset handling separately, with extra smoke coverage.
7. Revisit larger install/runtime groupings only after the above boundaries are
   stable.

## Risks and compatibility checks

- Keep `set -Eeuo pipefail` in `entrypoint.sh`; libraries must be source-safe
  under those options.
- Source paths must work both from the repository and from `/entrypoint.sh` inside
  the image.
- Preserve log line format unless a change is explicitly documented.
- Avoid changing S3 alias names, bucket/key layouts, or `mc` command behavior
  during extraction.
- Avoid moving destructive world reset logic until tests cover existing skip and
  flag behavior.
- Run `bash -n entrypoint.sh scripts/lib/*.sh`.
- Run `shellcheck -x -s bash entrypoint.sh scripts/lib/*.sh` when ShellCheck is
  available.
- Keep the existing Docker/runtime smoke checks as the regression gate for
  Kubernetes/container startup behavior.
