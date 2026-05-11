# Shutdown, RCON, and lifecycle boundary

This document defines proposed boundaries for the remaining shutdown, RCON, and
lifecycle hook responsibilities in `entrypoint.sh`.

It is a design plan only. Do not move functions, change shutdown behavior,
change RCON behavior, change signal handling, change lifecycle hook timing,
change command-line mode selection, or change install-only behavior as part of
this document.

## Proposed boundaries

Use one design document first because shutdown, RCON, lifecycle hooks, runtime
launch, signal handling, and command modes are currently coupled. Split
implementation later only after the coupling is documented and each move can be
kept mechanical.

Recommended future files:

- `scripts/lib/lifecycle.sh`
  - Own lifecycle hook discovery and execution.
- `scripts/lib/rcon.sh`
  - Own RCON command execution helpers and RCON stop behavior if separable.
- `scripts/lib/shutdown.sh`
  - Own graceful shutdown and server process shutdown policy if separable.

Avoid moving these as one large implementation PR. The safer path is lifecycle
first, then pure RCON helpers, then shutdown orchestration last.

`entrypoint.sh` should continue to answer:

- Which command mode was requested.
- When install-only mode exits.
- When install, runtime launch, and process shutdown are orchestrated.
- Where signal trap registration belongs until a dedicated shutdown PR decides
  otherwise.

## Current state

The remaining shutdown, signal, and command-mode behavior is implemented in
`entrypoint.sh`. `run_phase_hooks` has moved mechanically to
`scripts/lib/lifecycle.sh`, and the pure RCON command helpers have moved to
`scripts/lib/rcon.sh`.

Still in `entrypoint.sh` for now:

- `rcon_stop`
- `rcon_stop_once`
- `acquire_rcon_stop_lock`
- `cleanup_rcon_lock_on_boot`
- `graceful_shutdown`
- `wait_for_server_exit`
- signal trap registration
- command-line mode selection

Current lifecycle hook behavior:

- `run_phase_hooks`
  - Implemented in `scripts/lib/lifecycle.sh`.
  - Uses `HOOKS_ENABLED` to enable or skip hooks.
  - Builds the hook directory from `HOOKS_DIR` and the phase name:
    `${HOOKS_DIR}/${phase}.d`.
  - Logs when hooks are enabled but a phase directory is missing.
  - Iterates executable files in the phase directory.
  - Skips non-executable files with a warning.
  - Runs hooks with `HOOK_PHASE="${phase}"`.
  - Uses `HOOKS_TIMEOUT_SEC` with `timeout` when it is a positive integer.
  - Uses `HOOKS_STRICT`, defaulting to true, to decide whether hook failures are
    fatal.
  - Logs when no executable hooks are found.
- Current call sites found:
  - `install` calls `run_phase_hooks "pre-install"`.
  - `install` calls `run_phase_hooks "post-install"`.
  - `runtime` in `scripts/lib/runtime_launch.sh` calls
    `run_phase_hooks "pre-runtime"`.

Current RCON behavior:

- `rcon_client`
  - Implemented in `scripts/lib/rcon.sh`.
  - Prefers `rcon-cli` when available.
  - Falls back to `mcrcon` when available.
- `rcon_exec`
  - Implemented in `scripts/lib/rcon.sh`.
  - Builds a command from its arguments.
  - Requires `ENABLE_RCON=true`.
  - Requires non-empty `RCON_PASSWORD`.
  - Uses `RCON_HOST`, `RCON_PORT`, `RCON_PASSWORD`, and `RCON_TIMEOUT`.
  - Retries according to `RCON_RETRIES` and `RCON_RETRY_DELAY`.
  - Logs final failure after retries are exhausted.
- `rcon_say`
  - Implemented in `scripts/lib/rcon.sh`.
  - Calls `rcon_exec "say $*"`.
- `rcon_tellraw_all`
  - Implemented in `scripts/lib/rcon.sh`.
  - JSON-escapes the message.
  - Tries `tellraw @a` first.
  - Falls back to `say` if tellraw fails.
- `rcon_stop`
  - Requires `ENABLE_RCON=true`.
  - Uses `STOP_SERVER_ANNOUNCE_DELAY`.
  - Checks the Citizens save file at
    `${DATA_DIR}/plugins/Citizens/saves.yml`.
  - Announces shutdown through RCON.
  - Runs `citizens save`, `save-all`, and `stop` through `rcon_exec`.

Current RCON stop lock behavior:

- `RCON_STOP_RESULT`
  - Stores the result of the first `rcon_stop` attempt.
- `RCON_STOP_LOCK`
  - Defaults to `/tmp/.rcon-stop.lockdir`.
  - Is intentionally on ephemeral storage rather than `/data`.
- `RCON_STOP_IN_PROGRESS`
  - Prevents re-entrance within the same process.
- `cleanup_rcon_lock_on_boot`
  - Removes a stale RCON stop lock best-effort.
  - Is called by `run_server` in `scripts/lib/runtime_launch.sh`.
- `acquire_rcon_stop_lock`
  - Creates the lock directory.
- `rcon_stop_once`
  - Prevents duplicate RCON stop execution across preStop/trap paths.
  - Calls `rcon_stop` once and stores the result.

Current shutdown behavior:

- `wait_for_server_exit`
  - Polls `SERVER_PID` until the process exits or a timeout is reached.
- `graceful_shutdown`
  - Logs shutdown start.
  - Skips `rcon_stop` when `TYPE=velocity`.
  - Otherwise calls `rcon_stop_once`.
  - If RCON stop fails or is unavailable, sends `TERM` to `SERVER_PID`.
  - Waits up to `SHUTDOWN_WAIT_TIMEOUT`.
  - Sends `TERM` after timeout.
  - Waits up to `SHUTDOWN_TERM_WAIT`.
  - Sends `KILL` if the process still has not exited.
  - Exits after shutdown handling.
- Signal handling
  - Uses a single `trap 'graceful_shutdown' TERM INT QUIT`.

Current command-mode behavior:

- The top-level command-mode `case` supports:
  - `run`
  - `install-only`
  - `rcon`
  - `rcon-say`
  - `rcon-stop`
- `install-only` sets `INSTALL_ONLY=true` and continues through `main`.
- `main` exits after `install` when `INSTALL_ONLY` is true, before runtime
  launch.
- `rcon` calls `rcon_exec "$@"` and exits with that status.
- `rcon-say` calls `rcon_say "$@"` and exits with that status.
- `rcon-stop` calls `rcon_stop_once` and exits `0`.

## Future lifecycle ownership

Future `scripts/lib/lifecycle.sh` may own:

- `run_phase_hooks`.
- Lifecycle hook discovery.
- Lifecycle hook execution.
- Hook directory and environment handling.
- Hook timeout handling.
- Hook strict/failure policy as currently implemented.
- Hook phase naming/validation if added later.

Future `scripts/lib/lifecycle.sh` should not own:

- Runtime launch commands.
- Shutdown or RCON behavior.
- Command-line mode selection.
- Install-only orchestration.

## Future RCON ownership

Future `scripts/lib/rcon.sh` may own:

- `rcon_client`.
- `rcon_exec`.
- `rcon_say`.
- `rcon_stop`.
- `rcon_tellraw_all`.
- RCON connection argument handling.
- RCON retry and timeout behavior.
- RCON stop lock/result helpers only if they are not inseparable from shutdown.

Future `scripts/lib/rcon.sh` should not own:

- Runtime launch command dispatch.
- Signal trap registration.
- Non-RCON shutdown fallback policy.
- Install-only orchestration.
- Server artifact installation.

## Future shutdown ownership

Future `scripts/lib/shutdown.sh` may own:

- `graceful_shutdown`.
- `wait_for_server_exit`.
- Signal-driven shutdown orchestration.
- `cleanup_rcon_lock_on_boot` if it remains shutdown/RCON lock cleanup.
- `SERVER_PID` shutdown behavior.
- Fallback `TERM` and `KILL` behavior.
- RCON stop integration if it remains part of shutdown policy.
- Signal trap registration if a dedicated shutdown PR decides it belongs with
  shutdown implementation rather than `entrypoint.sh` orchestration.

Future `scripts/lib/shutdown.sh` should not own:

- Runtime launch command dispatch.
- `run_server` unless a later PR proves it belongs with shutdown.
- Server artifact installation.
- Velocity TOML generation.
- World install or world reset.
- `server.properties` bootstrap.
- S3/MinIO setup.
- Plugin, mod, config, datapack, or resourcepack installation.
- Command-line mode selection unless a dedicated CLI boundary is created.
- Install-only orchestration.

## Current coupling

Current coupling to preserve during future mechanical moves:

- `runtime_launch.sh` `run_server` calls `cleanup_rcon_lock_on_boot`, which
  still lives in `entrypoint.sh`.
- `runtime_launch.sh` `runtime` calls `run_phase_hooks "pre-runtime"`, which
  still lives in `entrypoint.sh`.
- `run_phase_hooks` depends on `HOOKS_ENABLED`, `HOOKS_DIR`,
  `HOOKS_TIMEOUT_SEC`, `HOOKS_STRICT`, `is_true`, `log`, and `die`.
- `graceful_shutdown` depends on `TYPE`, `SERVER_PID`, `rcon_stop_once`,
  `wait_for_server_exit`, `SHUTDOWN_WAIT_TIMEOUT`, and `SHUTDOWN_TERM_WAIT`.
- `wait_for_server_exit` polls `SERVER_PID`.
- `rcon_stop_once` depends on `RCON_STOP_LOCK`, `RCON_STOP_IN_PROGRESS`,
  `RCON_STOP_RESULT`, `acquire_rcon_stop_lock`, and `rcon_stop`.
- `rcon-stop` command mode shares `rcon_stop_once` with `graceful_shutdown`.
- Signal trap registration calls `graceful_shutdown`.
- Install-only behavior exits before `runtime` and should remain
  orchestration-owned for now.
- Velocity intentionally skips `rcon_stop` in `graceful_shutdown`.

## Staged migration order

Recommended implementation PRs:

1. Add this docs-only boundary plan.
   - Status: completed for the lifecycle hook helper move only.
2. Move lifecycle hook helpers mechanically into `scripts/lib/lifecycle.sh` if
   they remain mostly pure.
   - Preserve `run_phase_hooks` behavior.
   - Preserve `pre-install`, `post-install`, and `pre-runtime` phase timing.
   - Let `runtime_launch.sh` continue to call `run_phase_hooks` by Bash runtime
     name resolution.
3. Move pure RCON command helpers into `scripts/lib/rcon.sh` if separable.
   - Status: completed for the pure command helpers only.
   - Preserve `rcon`, `rcon-say`, and `rcon-stop` command-mode behavior.
   - Preserve env var behavior, retries, timeouts, log messages, and error
     messages.
4. Move shutdown orchestration into `scripts/lib/shutdown.sh` last.
   - Preserve `graceful_shutdown` behavior.
   - Preserve `SERVER_PID` behavior.
   - Preserve RCON stop lock behavior.
   - Preserve Velocity shutdown behavior that skips `rcon_stop`.
   - Preserve signal trap registration timing, or keep trap registration in
     `entrypoint.sh` if that remains more clearly orchestration-owned.
5. Only after those boundaries stabilize, consider command-line mode selection
   or a dedicated CLI boundary.
6. Do not combine these moves with cleanup backlog items.

## Risk notes

Specific risks to avoid during extraction:

- Changing signal handling.
- Changing shutdown ordering.
- Changing RCON stop behavior.
- Changing RCON retry or timeout behavior.
- Changing RCON lock behavior.
- Changing `SERVER_PID` handling.
- Changing wait behavior.
- Changing lifecycle hook timing.
- Changing hook environment or path behavior.
- Changing hook strict/failure behavior.
- Changing command-line mode behavior.
- Changing install-only behavior.
- Accidentally mixing runtime launch with shutdown policy.
- Accidentally breaking Velocity shutdown behavior that intentionally skips
  RCON stop.

## Test and smoke guidance

For future implementation PRs, use focused checks:

- Run `bash -n entrypoint.sh scripts/lib/*.sh`.
- Run `shellcheck -x -s bash entrypoint.sh scripts/lib/*.sh` when ShellCheck is
  installed.
- Add or run source smoke tests for future `scripts/lib/lifecycle.sh`,
  `scripts/lib/rcon.sh`, and `scripts/lib/shutdown.sh`.
- Use mocked lifecycle hook smoke tests in a temporary hook directory.
- Use mocked RCON command smoke tests where practical without connecting to a
  real server.
- Use shutdown smoke with a harmless short-lived process if practical.
- Avoid real Minecraft server boot.
- Do not make network calls.
- Do not require S3 credentials.
- Do not trigger destructive world reset behavior.
- Preserve command-mode behavior unless a dedicated behavior PR changes it.

## Guardrails

- Keep each implementation PR small and mechanical.
- Do not move lifecycle, RCON, shutdown, and CLI handling together.
- Do not change shutdown policy while moving ownership.
- Do not change hook timing or RCON command semantics while moving ownership.
