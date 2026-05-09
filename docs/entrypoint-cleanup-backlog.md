# entrypoint.sh cleanup and hardening backlog

This backlog captures non-mechanical cleanup and hardening items observed while
splitting `entrypoint.sh` responsibilities into `scripts/lib/*.sh`.

These items were intentionally not fixed during the mechanical boundary
extraction PRs. Each item may change behavior, error handling, logging, or
failure timing. Handle them in dedicated PRs with focused smoke tests, and do
not mix them into future mechanical moves.

Preserve existing runtime behavior unless a PR explicitly chooses and documents
a behavior change.

## logging.sh

- Review `die` argument handling.
- Consider whether `die` should support multiple arguments safely, for example
  `die "$@"` or explicit message handling.
- Preserve current log format semantics unless intentionally changed.

## s3_client.sh

- Harden temporary-file cleanup in `ensure_s3_source_nonempty_for_remove`.
- Prefer safer temp handling and/or `trap` where appropriate.
- Keep S3 environment variable names unchanged.
- Keep the MinIO alias name `s3` unchanged.
- Preserve existing behavior unless intentionally changed in a dedicated
  hardening PR.

## world_install.sh

- Improve `unzip` error handling with an explicit `die` or log message.
- Review the fixed `/tmp/world.zip`; consider `mktemp` to avoid collisions.
- Harden `DATA_DIR` / `WORLD_DIR` path safety before `rm -rf`.
- Improve extracted world directory detection instead of broad matching such as
  `find "${DATA_DIR}" -maxdepth 1 -type d -name "*world*" | head -n1`.
- Preserve current behavior until a dedicated non-mechanical improvement PR.

## server_properties.sh

- Review `TYPE` access under `set -u`.
- Make `TYPE` handling consistently safe where practical.
- Preserve bootstrap behavior and log semantics unless intentionally changed.

## runtime.sh

- Review the inconsistency where `is_supported_runtime_type` includes `spigot`,
  while the `resolve_type_auto` marker-supported type list did not include
  `spigot` in the original moved code.
- Decide in a dedicated behavior PR whether Spigot marker resolution should be
  supported.
- Consider safer marker temp-file handling in `write_server_install_marker`
  instead of `tmp="${marker}.tmp.$$"`.
- Improve handling of invalid or corrupt marker JSON in:
  - `assert_server_install_matches`
  - `resolve_type_auto`
- Preserve marker path and JSON format unless intentionally changed.

## world_reset.sh

- Localize variables in `reset_world` / `handle_reset_world_flag`, including:
  - `FLAG_FILE`
  - `WORLD_DIR`
  - `MODS_DIR`
  - `MAX_AGE`
  - `FLAG`
  - `NOW`
  - `MTIME`
  - `TS`
  - `BACKUP_DIR`
- Harden `DATA_DIR` / `WORLD_DIR` safety checks.
- Guard against empty or unset `DATA_DIR`.
- Add path sanity checks before `rm -rf`.
- Consider safer temp/atomic handling where applicable.
- Preserve existing reset behavior until a dedicated non-mechanical improvement
  PR.

## Recommended execution order

1. Safety-only shell hygiene:
   - localize variables
   - safer temp files
   - safer cleanup traps
2. Destructive operation hardening:
   - world reset path guards
   - world install path guards
3. Error-message improvements:
   - unzip failure
   - corrupt marker JSON
4. Behavior-decision PRs:
   - Spigot marker support
   - improved extracted world detection

## Guardrails

- These items were intentionally deferred during mechanical boundary extraction.
- Each item may change behavior or error handling.
- Handle each cleanup area in a dedicated PR with focused smoke tests.
- Do not mix these fixes into future mechanical moves.
- Keep marker paths, marker JSON format, S3 environment variable names, MinIO
  alias names, install order, and world-reset behavior unchanged unless the PR
  explicitly targets that behavior.
