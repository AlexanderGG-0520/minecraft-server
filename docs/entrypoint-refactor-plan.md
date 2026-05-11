# entrypoint.sh staged responsibility plan

`entrypoint.sh` is currently both the orchestration layer and the implementation
home for unrelated bootstrapping concerns. The immediate goal is to define stable
responsibility boundaries before moving substantial behavior.

Deferred non-mechanical cleanup and hardening items are tracked in
[`docs/entrypoint-cleanup-backlog.md`](entrypoint-cleanup-backlog.md). Keep those
items out of future mechanical moves.
That backlog is the next phase after the responsibility split; do not fold its
behavior-changing items into more mechanical moves.

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

Status: completed for runtime type and install marker helpers. Small runtime
type predicates, install marker path/write/validation helpers, and
`resolve_type_auto` have moved. Server artifact installation has moved to
`scripts/lib/server_install.sh`; `run_server` has moved to
`scripts/lib/runtime_launch.sh`; runtime dispatch has not moved and remains in
`entrypoint.sh`.

Owns:

- Supported runtime type lists and validation.
- Runtime install marker path, write, and validation helpers.
- `TYPE=auto` marker/artifact resolution.

Do not move all runtime behavior immediately. Runtime dispatch currently depends
on `run_server`, shutdown/RCON state, and `JVM_ARGS_FILE`. Move dispatch only
after call sites are stable.

The proposed server artifact installation boundary is documented in
[`docs/server-artifact-install-boundary.md`](server-artifact-install-boundary.md).
The proposed Velocity config generation boundary is documented in
[`docs/velocity-config-boundary.md`](velocity-config-boundary.md).
The proposed runtime launch boundary is documented in
[`docs/runtime-launch-boundary.md`](runtime-launch-boundary.md).
The proposed shutdown/RCON/lifecycle boundary is documented in
[`docs/shutdown-rcon-lifecycle-boundary.md`](shutdown-rcon-lifecycle-boundary.md).
The refined RCON stop and shutdown coupling is documented in
[`docs/shutdown-rcon-lifecycle-boundary.md`](shutdown-rcon-lifecycle-boundary.md).
`rcon_stop` has moved mechanically into `scripts/lib/rcon.sh`, and the
RCON stop lock/de-dupe helpers now live in `scripts/lib/shutdown.sh`; the
remaining shutdown orchestration stays in `entrypoint.sh` for now.
`wait_for_server_exit` has also moved into `scripts/lib/shutdown.sh`.
Initial extraction has started: pure server artifact download helpers now live in
`scripts/lib/server_install.sh`. Vanilla, Fabric, Quilt, Forge, NeoForge, Paper,
Purpur, Mohist, Taiyitist, and Youer artifact install helpers plus the Spigot
existing-artifact validation helper have also moved there. Velocity artifact
installation and `install_server` dispatch have moved there too. `run_server`
and runtime launch dispatch have moved to `scripts/lib/runtime_launch.sh`.
Shutdown/RCON/signal handling, lifecycle hook implementation, command-line mode
selection, and install-only orchestration remain in `entrypoint.sh`.
`generate_velocity_toml` has moved to `scripts/lib/velocity_config.sh` without
changing its call timing.

### Server properties bootstrap

Suggested file: `scripts/lib/server_properties.sh`

Status: completed. `ensure_server_properties` and `bootstrap_server_properties`
have moved. Runtime type resolution and world reset behavior have separate
completed boundaries.

Owns:

- Deciding whether a runtime uses `server.properties`.
- `ensure_server_properties`.
- `bootstrap_server_properties`.
- Server-property diff/application helpers once their env contract is documented.

Moved cautiously because property bootstrap intentionally launches server
artifacts with short timeouts and has runtime-specific behavior for vanilla,
Paper-family, Fabric, Forge, and NeoForge. Broader server-property diff and
application helpers remain in `entrypoint.sh` for now.

### World install

Suggested file: `scripts/lib/world_install.sh`

Status: completed for world installation only.
`install_world` has moved. World reset handling has moved separately to
`scripts/lib/world_reset.sh`.

Owns:

- World zip download/extract/install behavior.
- Validation of extracted world layout.

### World reset

Suggested file: `scripts/lib/world_reset.sh`

Status: completed. `reset_world` and `handle_reset_world_flag` have moved.
`entrypoint.sh` still decides when reset handling runs relative to world install
and the rest of startup.

Owns:

- `reset-world.flag` validation and expiration handling.
- Destructive world directory reset behavior.
- Optional world backup and mods removal behavior during reset.

### S3 / MinIO client handling

Suggested file: `scripts/lib/s3_client.sh`

Status: completed. This extraction is limited to the client mechanics needed by
existing call sites.

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
4. Extract server.properties bootstrap helpers. Done.
5. Introduce runtime type predicate helpers in `runtime.sh`. Done.
6. Migrate `TYPE=auto` resolution into `runtime.sh`. Done.
7. Move runtime install marker helpers into `runtime.sh`. Done.
8. Move world reset handling separately, with extra smoke coverage. Done.
9. Revisit larger install/runtime groupings only after the above boundaries are
   stable.

## Entrypoint orchestration responsibilities

`entrypoint.sh` should continue to own orchestration and top-level process
control:

- source libraries in dependency order.
- initialize process-global defaults and state that other helpers read.
- select command mode (`run`, `install-only`, `rcon`, `rcon-say`, `rcon-stop`).
- call install and runtime in the correct order.
- exit early for `install-only` before runtime launch.
- register the shutdown signal trap.
- keep top-level `main()` execution and sourced guard behavior.

These are not problems to solve by default. They are often the right things to
keep in `entrypoint.sh` unless a future dedicated CLI, state, or signal PR has a
clear reason to move them.

Do not casually move:

- signal trap registration
- command-mode selection
- install-only orchestration
- source order
- process-global initialization for `SERVER_PID`, `RCON_STOP_RESULT`,
  `RCON_STOP_LOCK`, and `RCON_STOP_IN_PROGRESS`
- `main()` call/guard logic

Possible future dedicated boundaries, if needed:

- CLI / command-mode boundary
- process-state/global initialization boundary
- signal-trap boundary

Treat those as optional follow-on work, not a default continuation of the helper
extractions.

## Risks and compatibility checks

- Keep `set -Eeuo pipefail` in `entrypoint.sh`; libraries must be source-safe
  under those options.
- Source paths must work both from the repository and from `/entrypoint.sh` inside
  the image.
- Preserve log line format unless a change is explicitly documented.
- Avoid changing S3 alias names, bucket/key layouts, or `mc` command behavior
  during extraction.
- Keep destructive world reset checks scoped to temporary directories.
- Run `bash -n entrypoint.sh scripts/lib/*.sh`.
- Run `shellcheck -x -s bash entrypoint.sh scripts/lib/*.sh` when ShellCheck is
  available.
- Keep the existing Docker/runtime smoke checks as the regression gate for
  Kubernetes/container startup behavior.

## Current status

The helper-splitting phase is substantially complete.

Most reusable behavior now lives in `scripts/lib/*.sh`:

- `logging.sh`: logging and timestamp helpers.
- `runtime.sh`: runtime type resolution and install marker helpers.
- `lifecycle.sh`: lifecycle hook execution.
- `rcon.sh`: RCON command helpers and the raw `rcon_stop` implementation;
  `rcon_tellraw_all` still depends on `json_escape` from `entrypoint.sh`.
- `shutdown.sh`: RCON stop sequencing plus lock/de-dupe helpers,
  `wait_for_server_exit`, and `graceful_shutdown`.
- `s3_client.sh`: S3/MinIO client mechanics.
- `server_install.sh`: server artifact download/install helpers and
  `install_server`.
- `velocity_config.sh`: Velocity config generation.
- `runtime_launch.sh`: `run_server` and runtime dispatch.
- `world_install.sh`: world install helpers.
- `world_reset.sh`: world reset helpers.
- `server_properties.sh`: server.properties bootstrap helpers.

`entrypoint.sh` is now primarily orchestration. That is expected. Not every
remaining line is refactor debt.

What intentionally remains in `entrypoint.sh`:

- source order.
- process-global initialization and defaults.
- command-mode selection.
- install/runtime orchestration.
- install-only early exit behavior.
- signal trap registration.
- `main()` execution and sourced-guard behavior.

What should not be moved casually:

- source order.
- command-mode selection.
- install-only orchestration.
- process-global initialization for `SERVER_PID`, `RCON_STOP_RESULT`,
  `RCON_STOP_LOCK`, and `RCON_STOP_IN_PROGRESS`.
- signal trap timing.
- top-level `main()`/sourced guard behavior.

Cleanup backlog and behavior-specific hardening should be handled in dedicated
PRs. Do not mix those with the mechanical responsibility split.
