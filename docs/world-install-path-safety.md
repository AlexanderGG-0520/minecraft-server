# world install path-safety boundary

This note defines a docs-only design boundary for future `DATA_DIR` /
`WORLD_DIR` path-safety hardening in `scripts/lib/world_install.sh`.

Implementation status: completed for `world_install.sh`. `world_reset.sh`
path-safety remains separate.

## Current Behavior

Current `install_world` behavior relevant to destructive paths:

- `WORLD_DIR` is local to `install_world` and derived from `DATA_DIR` as
  `${DATA_DIR}/world`.
- Existing world replacement uses:
  - `rm -rf "${WORLD_DIR}"`
- After deterministic extraction detection, existing world replacement happens
  only after the archive has downloaded, unzipped, and matched a supported
  archive layout.
- Failed archive layout detection preserves the existing world and
  `${DATA_DIR}/reset-world.flag`.
- The selected extracted source is moved into `${WORLD_DIR}` after the existing
  world directory is removed.
- Successful install removes `${DATA_DIR}/reset-world.flag` after temporary
  archive and extraction cleanup.
- Temporary archive cleanup uses `rm -f "${TMP_ZIP}"`.
- Temporary extraction cleanup uses `rm -rf "${EXTRACT_DIR}"`.
- `world_install.sh` validates `DATA_DIR` and `WORLD_DIR` before
  `rm -rf "${WORLD_DIR}"`.
- `world_reset.sh` path-safety remains separate and must not be combined with
  `world_install.sh` hardening.

## Implemented Safety Policy

`validate_world_install_paths` validates world install paths before destructive
operations.

Implemented checks:

- `DATA_DIR` must be set and non-empty.
- `WORLD_DIR` must be set and non-empty.
- `WORLD_DIR` must equal `${DATA_DIR}/world` before path resolution.
- `WORLD_DIR` must resolve to the intended `${DATA_DIR}/world` path after
  normalization.
- `WORLD_DIR` must be inside `DATA_DIR`.
- `WORLD_DIR` must not resolve to `/`, `/world`, `/tmp`, the data root itself
  such as `/data`, or another root-like path.
- `DATA_DIR` must be absolute.
- Path checks fail before `rm -rf "${WORLD_DIR}"`.

Implementation decisions:

- `DATA_DIR` is required to be absolute because the production container uses
  `/data`, and existing smoke coverage uses absolute temporary directories.
- Path normalization uses `realpath -m` so paths can be checked even before the
  final world directory exists.
- `DATA_DIR` failures use `DATA_DIR is required for world install`.
- Other unsafe path failures use `Refusing unsafe world install path`.

## Implementation Boundary

The path-safety implementation:

- Adds `validate_world_install_paths` in `scripts/lib/world_install.sh`.
- Calls the helper before creating/replacing `${WORLD_DIR}` and immediately
  before `rm -rf "${WORLD_DIR}"`.
- Adds smoke tests with harmless temporary directories.
- Preserves S3/MinIO behavior.
- Preserves `S3_BUCKET` and `WORLD_S3_KEY` semantics.
- Preserves `configure_mc_alias "world"`.
- Preserves `mc cp` source semantics.
- Preserves deterministic extraction detection behavior.
- Preserves temp archive and extraction cleanup behavior.
- Preserves `reset-world.flag` success cleanup.
- Fails before destructive operations when paths are invalid.

The implementation does not:

- Change `install_world` call sites.
- Change `world_reset.sh`.
- Change S3/MinIO behavior.
- Change archive layout detection.
- Change temp archive behavior.
- Change install dispatch or runtime launch behavior.
- Combine with `world_reset.sh` path safety.
- Combine with extracted-world detection changes.
- Combine with MinIO or `mc` dependency remediation.

## Smoke Coverage

Path-safety smoke tests cover:

- Success with a valid temporary `DATA_DIR`.
- Success where `WORLD_DIR` is derived as `${DATA_DIR}/world`.
- Existing install fixture behavior still proceeds as before for valid paths.
- Failure when `DATA_DIR` is empty or unset.
- Failure when `DATA_DIR` is relative.
- Failure when `WORLD_DIR` would be empty.
- Failure when `WORLD_DIR` would resolve outside `DATA_DIR`.
- Failure when `WORLD_DIR` would resolve to a dangerous root-like path.

Smoke tests:

- Use harmless temporary directories.
- Avoid real S3 or MinIO.
- Use mocked `mc cp`.
- Avoid Minecraft server boot.
- Avoid server artifact downloads.
- Avoid destructive paths outside temporary directories.
