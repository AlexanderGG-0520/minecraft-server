# world reset path-safety boundary

This note defines the `DATA_DIR` / `WORLD_DIR` path-safety hardening boundary
for `scripts/lib/world_reset.sh`.

Implementation status: completed for `world_reset.sh`. `world_install.sh`
path-safety remains separate and is documented in
[`docs/world-install-path-safety.md`](world-install-path-safety.md).

## Current Behavior

`world_reset.sh` currently defines `reset_world` and
`handle_reset_world_flag`. The library is sourced by `entrypoint.sh`, and
`handle_reset_world_flag` runs from the main install flow before
server-properties install, mods install, mod activation, and later startup
preparation.

Current reset behavior relevant to destructive paths:

- `handle_reset_world_flag` derives `FLAG` as `${DATA_DIR}/reset-world.flag`.
- If the flag is absent, reset handling logs that no flag was detected and
  returns.
- If the flag is present, it compares the current time from `date +%s` with the
  flag mtime from `stat -c %Y`.
- If the flag is older than `MAX_AGE=1800`, reset handling logs an expiration
  error, validates the reset flag path with `validate_world_reset_flag_path`,
  removes the flag with `rm -f "$FLAG"`, and returns.
- If the flag is fresh, reset handling logs that reset will proceed, calls
  `reset_world`, then removes the flag with `rm -f "$FLAG"` and logs that the
  flag was consumed.
- `reset_world` derives `FLAG_FILE` as `${DATA_DIR}/reset-world.flag`.
- `reset_world` returns without resetting when `FLAG_FILE` is missing.
- `WORLD_DIR` is derived as `${DATA_DIR}/world`.
- `MODS_DIR` is derived as `${DATA_DIR}/mods`.
- If `WORLD_DIR` is not a directory, reset logs that there is nothing to reset
  and returns.
- The original path sanity checks still reject `WORLD_DIR` when it is exactly
  `/` or exactly `${DATA_DIR}`.
- `validate_world_reset_paths` also validates reset paths before `.ready`
  cleanup, backup creation, world deletion, optional mods deletion, and
  successful reset flag cleanup.
- Reset removes `${DATA_DIR}/.ready` with `rm -f`.
- When `RESET_WORLD_BACKUP` is unset or `true`, reset creates
  `BACKUP_DIR="${DATA_DIR}/backups"` and writes
  `world-${TS}.tar.gz`, where `TS="$(date -u +'%Y%m%d-%H%M%S')"`.
- Backup uses `tar -czf "${BACKUP_DIR}/world-${TS}.tar.gz" -C "${DATA_DIR}" world`.
- Backup failure calls `die "World backup failed; refusing to delete world"`
  before world deletion.
- Reset deletes the world with `rm -rf "${WORLD_DIR}"`, then recreates it with
  `mkdir -p "${WORLD_DIR}"`.
- If `RESET_WORLD_REMOVE_MODS=true`, reset deletes `MODS_DIR` with
  `rm -rf "${MODS_DIR}"`, then recreates it with `mkdir -p "${MODS_DIR}"`.
- On successful reset, `reset_world` removes `FLAG_FILE` with
  `rm -f "${FLAG_FILE}"` and logs completion.

Current failure and cleanup behavior:

- Missing reset flag is non-fatal.
- Missing world directory is non-fatal and leaves the reset flag cleanup to the
  caller when reset was entered through `handle_reset_world_flag`.
- Expired reset flags are removed by `handle_reset_world_flag`.
- Backup failure stops before world deletion.
- `reset_world` and `handle_reset_world_flag` both remove the reset flag on the
  successful reset path.
- There is no dedicated cleanup for partially recreated world or mods
  directories after a failure during `mkdir -p`.

Current destructive operations:

- `rm -f "${DATA_DIR}/.ready"`
- `rm -f "$FLAG"`
- `rm -f "${FLAG_FILE}"`
- `rm -rf "${WORLD_DIR}"`
- `rm -rf "${MODS_DIR}"` when `RESET_WORLD_REMOVE_MODS=true`
- `tar -czf "${BACKUP_DIR}/world-${TS}.tar.gz" -C "${DATA_DIR}" world`

## Implemented Safety Policy

The implementation uses two validation scopes.

### Narrow flag-path validation

`validate_world_reset_flag_path` is used before expired flag cleanup in
`handle_reset_world_flag`. It intentionally does not require `WORLD_DIR`,
`BACKUP_DIR`, or `MODS_DIR` validation just to remove an expired flag.

Implemented checks:

- `DATA_DIR` must be set, non-empty, and absolute.
- `DATA_DIR` must not be `/`.
- The flag path must be set and non-empty.
- The flag path must equal `${DATA_DIR}/reset-world.flag`.
- The resolved flag path must remain inside resolved `DATA_DIR`.
- The resolved flag basename must be `reset-world.flag`.
- The resolved flag path must not be `/`, `/reset-world.flag`,
  `/tmp/reset-world.flag`, `/data`, or resolved `DATA_DIR` itself.
- Validation uses `realpath -m` and fails safely if `realpath` is unavailable.

Failures use:

- `DATA_DIR is required for world reset` when `DATA_DIR` is empty or unset.
- `Refusing unsafe reset flag path` for unsafe flag paths.

### Full reset-path validation

`validate_world_reset_paths` is used in `reset_world` before destructive reset
operations.

Implemented checks:

- `DATA_DIR` must be set and non-empty.
- `DATA_DIR` must be absolute and must not be `/`.
- `WORLD_DIR` must be set and non-empty.
- `WORLD_DIR` must equal `${DATA_DIR}/world` before resolution.
- Resolved `WORLD_DIR` must equal resolved `${DATA_DIR}/world`.
- Resolved `WORLD_DIR` must stay inside resolved `DATA_DIR`.
- Resolved `WORLD_DIR` basename must be `world`.
- Resolved `WORLD_DIR` must not be `/`, `/world`, `/tmp`, `/data`,
  `DATA_DIR` itself, or another root-like path.
- `FLAG_FILE` must equal `${DATA_DIR}/reset-world.flag`.
- Resolved `FLAG_FILE` must equal resolved `${DATA_DIR}/reset-world.flag` and
  remain inside resolved `DATA_DIR`.
- `BACKUP_DIR` must equal `${DATA_DIR}/backups`.
- Resolved `BACKUP_DIR` must equal resolved `${DATA_DIR}/backups` and remain
  inside resolved `DATA_DIR`.
- When backups are enabled, the backup archive path must remain inside resolved
  `BACKUP_DIR`.
- When `RESET_WORLD_REMOVE_MODS=true`, `MODS_DIR` must equal
  `${DATA_DIR}/mods`.
- When mods cleanup is enabled, resolved `MODS_DIR` must equal resolved
  `${DATA_DIR}/mods`, stay inside resolved `DATA_DIR`, have basename `mods`,
  and must not be `/`, `/mods`, `/tmp`, `/data`, `DATA_DIR` itself, or
  `WORLD_DIR`.
- Validation uses `realpath -m` and fails safely if `realpath` is unavailable.

Failures use:

- `DATA_DIR is required for world reset` when `DATA_DIR` is empty or unset.
- `Refusing unsafe reset flag path` for unsafe reset flag paths.
- `Refusing unsafe world reset path` for other unsafe reset paths.

Validation failures happen before `.ready` cleanup, backup creation,
`rm -rf "${WORLD_DIR}"`, optional `rm -rf "${MODS_DIR}"`, and successful reset
flag cleanup.

## Implementation Boundary

The implementation:

- Adds `validate_world_reset_flag_path` in `scripts/lib/world_reset.sh`.
- Adds `validate_world_reset_paths` in `scripts/lib/world_reset.sh`.
- Uses narrow flag-path validation before removing expired reset flags.
- Uses full reset-path validation in `reset_world` before destructive reset
  operations.
- Preserves reset trigger behavior for valid paths.
- Preserves `reset-world.flag` age semantics.
- Preserves backup naming and timestamp format.
- Preserves backup failure behavior:
  `World backup failed; refusing to delete world`.
- Preserves `RESET_WORLD_BACKUP` and `RESET_WORLD_REMOVE_MODS` semantics.
- Adds smoke tests using harmless temporary directories.

The implementation does not:

- Change `world_install.sh`.
- Change `install_world` behavior.
- Change S3/MinIO behavior.
- Change `WORLD_S3_BUCKET` or `WORLD_S3_KEY` behavior.
- Change install dispatch or runtime launch behavior.
- Change backup retention semantics unless documented.
- Change reset trigger semantics.
- Change reset flag age semantics.
- Change `RESET_WORLD_BACKUP` or `RESET_WORLD_REMOVE_MODS` semantics.
- Combine with extracted-world detection.
- Combine with MinIO or `mc` remediation.
- Combine with unrelated cleanup or variable-localization refactors.
  Existing uppercase function temporaries remain a separate cleanup item.

## Smoke Coverage

Path-safety smoke tests cover success with:

- Valid temporary absolute `DATA_DIR`.
- Fresh `reset-world.flag` present.
- Existing world directory reset according to current behavior.
- Backup creation according to current behavior when backups are enabled.
- Reset flag handling remaining correct on the successful path.
- Optional mods cleanup preserving current behavior when
  `RESET_WORLD_REMOVE_MODS=true`.
- Expired flag cleanup using narrow flag-path validation without requiring a
  world directory.

Path-safety smoke tests cover failure with:

- `DATA_DIR` empty.
- Relative `DATA_DIR`.
- Empty `WORLD_DIR`.
- `WORLD_DIR` outside `DATA_DIR`.
- `WORLD_DIR` resolving to `/`, `/world`, `/tmp`, `/data`, `DATA_DIR` itself,
  or another root-like path.
- Unsafe reset flag paths.
- Backup directory or backup archive path outside the allowed location.
- Unsafe mods path when mods cleanup validation is enabled.
- Validation failure preserving existing world data and the reset flag.

Smoke tests must:

- Use harmless temporary directories.
- Avoid real S3 or MinIO.
- Avoid Minecraft server boot.
- Avoid server artifact downloads.
- Avoid destructive paths outside temporary directories.
- Assert existing world data and reset flags are preserved when validation
  fails before destructive reset work.
