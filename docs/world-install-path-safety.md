# world install path-safety boundary

This note defines a docs-only design boundary for future `DATA_DIR` /
`WORLD_DIR` path-safety hardening in `scripts/lib/world_install.sh`.

Implementation status: design-ready only. This note does not change runtime
behavior.

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
- Current code does not yet explicitly validate empty or unset `DATA_DIR`, nor
  the resolved `${WORLD_DIR}` path, before `rm -rf "${WORLD_DIR}"`.
- `world_reset.sh` path-safety remains separate and must not be combined with
  this future `world_install.sh` hardening.

## Future Safety Policy

A future implementation should validate world install paths before destructive
operations.

Required checks:

- `DATA_DIR` must be set and non-empty.
- `WORLD_DIR` must be set and non-empty.
- `WORLD_DIR` must equal `${DATA_DIR}/world` before path resolution.
- `WORLD_DIR` must resolve to the intended `${DATA_DIR}/world` path after
  normalization.
- `WORLD_DIR` must be inside `DATA_DIR`.
- `WORLD_DIR` must not resolve to `/`, `/world`, `/tmp`, the data root itself
  such as `/data`, or another root-like path unless a future PR explicitly
  documents why that target is intended.
- Path checks should fail fast with a clear error before
  `rm -rf "${WORLD_DIR}"`.

Design decisions for the implementation PR:

- Decide whether `DATA_DIR` must be absolute. The production container normally
  uses an absolute data path, but tests and local invocation patterns should be
  checked before making this a hard requirement.
- Decide which path normalization primitive to use, such as `realpath` or
  `readlink -f`, based on what is available in the runtime image.
- Decide exact error text and keep it stable enough for smoke tests.

## Future Implementation Boundary

A future path-safety implementation may:

- Add a small helper local to `scripts/lib/world_install.sh`, such as
  `validate_world_install_paths`.
- Call that helper before `rm -rf "${WORLD_DIR}"`.
- Add smoke tests with harmless temporary directories.
- Preserve S3/MinIO behavior.
- Preserve `WORLD_S3_BUCKET` and `WORLD_S3_KEY` semantics.
- Preserve `configure_mc_alias "world"`.
- Preserve `mc cp` source semantics.
- Preserve deterministic extraction detection behavior.
- Preserve temp archive and extraction cleanup behavior.
- Preserve `reset-world.flag` success cleanup.
- Fail before destructive operations when paths are invalid.

A future path-safety implementation must not:

- Change `install_world` call sites.
- Change `world_reset.sh`.
- Change S3/MinIO behavior.
- Change archive layout detection.
- Change temp archive behavior.
- Change install dispatch or runtime launch behavior.
- Combine with `world_reset.sh` path safety.
- Combine with extracted-world detection changes.
- Combine with MinIO or `mc` dependency remediation.

## Smoke Guidance

Future path-safety smoke tests should cover:

- Success with a valid temporary `DATA_DIR`.
- Success where `WORLD_DIR` is derived as `${DATA_DIR}/world`.
- Existing install fixture behavior still proceeds as before for valid paths.
- Failure when `DATA_DIR` is unset.
- Failure when `DATA_DIR` is empty.
- Failure when `DATA_DIR` is relative, if absolute paths become required.
- Failure when `WORLD_DIR` would be empty.
- Failure when `WORLD_DIR` would resolve outside `DATA_DIR`.
- Failure when `WORLD_DIR` would resolve to a dangerous root-like path.

Smoke tests must:

- Use harmless temporary directories.
- Avoid real S3 or MinIO.
- Use mocked `mc cp` if `install_world` is exercised.
- Avoid Minecraft server boot.
- Avoid server artifact downloads.
- Avoid destructive paths outside temporary directories.
