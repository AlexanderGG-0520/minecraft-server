# world reset path-safety boundary

This note defines a docs-only design boundary for future `DATA_DIR` /
`WORLD_DIR` path-safety hardening in `scripts/lib/world_reset.sh`.

Implementation status: design-ready, not implemented. `world_install.sh`
path-safety is completed separately in
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
  error, removes the flag with `rm -f "$FLAG"`, and returns.
- If the flag is fresh, reset handling logs that reset will proceed, calls
  `reset_world`, then removes the flag with `rm -f "$FLAG"` and logs that the
  flag was consumed.
- `reset_world` derives `FLAG_FILE` as `${DATA_DIR}/reset-world.flag`.
- `reset_world` returns without resetting when `FLAG_FILE` is missing.
- `WORLD_DIR` is derived as `${DATA_DIR}/world`.
- `MODS_DIR` is derived as `${DATA_DIR}/mods`.
- If `WORLD_DIR` is not a directory, reset logs that there is nothing to reset
  and returns.
- Current path sanity checks only reject `WORLD_DIR` when it is exactly `/` or
  exactly `${DATA_DIR}`.
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

`world_reset.sh` does not yet have path-safety validation equivalent to
`validate_world_install_paths`.

## Future Safety Policy

Future implementation should validate reset paths before destructive reset
operations. The policy should be finalized in the implementation PR before shell
code changes are made.

Likely validation rules:

- `DATA_DIR` must be set and non-empty.
- `DATA_DIR` should likely be absolute, matching `world_install.sh`, unless the
  implementation PR documents a current reset behavior that requires relative
  paths.
- `WORLD_DIR` must be set and non-empty.
- `WORLD_DIR` should equal `${DATA_DIR}/world` before resolution if reset keeps
  the current derived-world behavior.
- Resolved `WORLD_DIR` should equal resolved `${DATA_DIR}/world`.
- Resolved `WORLD_DIR` must stay inside resolved `DATA_DIR`.
- Resolved `WORLD_DIR` must not be `/`, `/world`, `/tmp`, `/data`,
  `DATA_DIR` itself, or another root-like path.
- The reset flag path must remain inside resolved `DATA_DIR`.
- The backup directory must remain inside resolved `DATA_DIR`, unless a future
  PR explicitly documents another safe backup location.
- The backup archive path must remain inside the validated backup directory.
- If mods cleanup remains supported, resolved `MODS_DIR` must be
  `${DATA_DIR}/mods`, must stay inside resolved `DATA_DIR`, and must not be a
  root-like path.
- Path validation must fail before `rm -rf`, destructive `rm -f`, or destructive
  backup/move operations that depend on unsafe paths.

Design decisions to resolve in the implementation PR:

- Whether `DATA_DIR` must be absolute for reset exactly as it is for
  `world_install.sh`.
- Whether `reset_world` and `handle_reset_world_flag` share one validation
  helper or validate separately at their destructive boundaries.
- Whether an expired flag removal should require the same full reset path
  validation or only a narrower flag-path validation.
- Whether validation failure should return like the existing unsafe-path guard
  or call `die`.
- Whether duplicated reset flag removal should remain unchanged or be cleaned up
  in a later behavior-preserving PR.

## Implementation Boundary

A future path-safety implementation may:

- Add a small helper local to `world_reset.sh`, such as
  `validate_world_reset_paths`.
- Reuse logic conceptually similar to `validate_world_install_paths`.
- Keep helper coupling local unless sharing code clearly reduces risk without
  increasing library dependency complexity.
- Call validation before destructive reset operations.
- Add smoke tests using harmless temporary directories.
- Preserve reset trigger behavior for valid paths.
- Preserve `reset-world.flag` behavior where paths are valid.
- Preserve backup naming and timestamp behavior unless intentionally changed.
- Preserve backup failure behavior.
- Preserve mods cleanup behavior where paths are valid.
- Preserve current log messages unless the implementation PR explicitly scopes
  an error-message update.

Future implementation must not:

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

## Smoke Guidance

Future implementation smoke tests should cover success with:

- Valid temporary absolute `DATA_DIR`.
- Fresh `reset-world.flag` present.
- Existing world directory reset according to current behavior.
- Backup creation according to current behavior when backups are enabled.
- Reset flag handling remaining correct on the successful path.
- Optional mods cleanup preserving current behavior when
  `RESET_WORLD_REMOVE_MODS=true`.

Future implementation smoke tests should cover failure with:

- `DATA_DIR` unset.
- `DATA_DIR` empty.
- Relative `DATA_DIR`, if absolute paths are required.
- Empty `WORLD_DIR`.
- `WORLD_DIR` outside `DATA_DIR`.
- `WORLD_DIR` resolving to `/`, `/world`, `/tmp`, `/data`, `DATA_DIR` itself,
  or another root-like path.
- Backup directory or backup archive path outside the allowed location, if the
  helper accepts or derives those paths.
- Unsafe mods path, if mods cleanup validation is included.

Smoke tests must:

- Use harmless temporary directories.
- Avoid real S3 or MinIO.
- Avoid Minecraft server boot.
- Avoid server artifact downloads.
- Avoid destructive paths outside temporary directories.
- Assert existing world data and reset flags are preserved when validation
  fails before destructive reset work.
