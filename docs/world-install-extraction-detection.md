# world install extraction detection

This note defines the behavior boundary for the extracted world directory
detection improvement in `scripts/lib/world_install.sh`.

This is a behavior-changing world install update.

Implementation status: deterministic extraction detection is implemented.

## Previous Detection Behavior

Before this behavior PR, `install_world` prepared and extracted a downloaded
world archive as follows:

- `WORLD_DIR` is local to `install_world` and set to `${DATA_DIR}/world`.
- Existing `${WORLD_DIR}` is removed with `rm -rf "${WORLD_DIR}"`.
- `${WORLD_DIR}` is recreated with `mkdir -p "${WORLD_DIR}"` before unzip.
- The archive is extracted directly into `${DATA_DIR}` with:
  - `unzip -q "${TMP_ZIP}" -d "${DATA_DIR}"`
- After unzip, fallback detection only runs if `${WORLD_DIR}` does not exist.
- The fallback detection is broad and name-based:
  - `find "${DATA_DIR}" -maxdepth 1 -type d -name "*world*" | head -n1`
- If that fallback finds a directory, it moves it to `${WORLD_DIR}`.
- The reset flag cleanup and success log happen after detection.

Because `${WORLD_DIR}` was created before extraction, the fallback detection was
normally bypassed after a successful prepare step. This means previous archive
layout behavior was mostly determined by what `unzip` wrote into an already
existing `${DATA_DIR}/world` directory, not by the fallback finder.

## Previous Layout Ambiguity

These observations describe the behavior that made the detection change
behavior-sensitive:

- Direct world directory layout, such as `world/level.dat`:
  - Extracts into the pre-created `${DATA_DIR}/world`.
  - Fallback detection is bypassed.
- Single-root directory with a non-world name, such as `MyServer/level.dat`:
  - Extracts to `${DATA_DIR}/MyServer`.
  - `${DATA_DIR}/world` already exists, so fallback detection is bypassed.
  - The function can still continue to cleanup and success logging.
- Single-root directory with `world` in the name, such as `MyWorld/level.dat`:
  - Extracts to `${DATA_DIR}/MyWorld`.
  - The broad `*world*` fallback would be able to match it only if
    `${DATA_DIR}/world` did not already exist.
  - Under the normal current flow, fallback detection is bypassed.
- Flat archive layout, such as `level.dat` at archive root:
  - Extracts `level.dat` directly under `${DATA_DIR}`.
  - `${DATA_DIR}/world` remains the pre-created directory.
  - The function can still continue to cleanup and success logging.
- Multiple top-level directories:
  - They extract under `${DATA_DIR}`.
  - `${DATA_DIR}/world` remains present, so fallback detection is bypassed.
  - A future detector must decide whether one candidate can be selected safely.
- Both `world/` and another `*world*` directory:
  - `world/` extracts into `${DATA_DIR}/world`.
  - Other directories also remain under `${DATA_DIR}`.
  - Fallback detection is bypassed because `${DATA_DIR}/world` exists.

If fallback detection does run in any future or unusual path, it is broad:
matching `*world*` and taking the first result can select an unexpected
directory. Changing this behavior may change which archive layouts appear to
install successfully.

## Implemented Layout Policy

`install_world` now extracts into a temporary extraction directory, detects a
supported top-level layout, and normalizes the selected contents into
`${DATA_DIR}/world`.

Supported layouts:

- Direct world directory layout: `world/level.dat`.
  - Installed as `${DATA_DIR}/world`.
- Single-root world layout: `MyWorld/level.dat`.
  - Supported only when it is the only top-level directory.
  - Single-root detection is based on exactly one top-level directory containing
    `level.dat`; unrelated top-level files are not treated as additional world
    candidates.
  - Installed as `${DATA_DIR}/world`.
- Flat archive layout: `level.dat` at archive root.
  - The extracted archive root is installed as `${DATA_DIR}/world`.

Rejected layouts:

- Multiple valid candidate world directories.
  - Fails with `Ambiguous world archive layout`.
- A flat root `level.dat` plus another valid top-level world directory.
  - Fails with `Ambiguous world archive layout`.
- A single valid non-`world` top-level directory plus other top-level
  directories.
  - Fails with `Ambiguous world archive layout`.
- Nested-only layouts such as `backups/world/level.dat`.
  - Fails with `Failed to detect world directory in archive`.
- Archives without any supported top-level `level.dat`.
  - Fail with `Failed to detect world directory in archive`.
- Malformed ZIP files remain covered by the existing unzip failure path.

## Implementation Boundary

The extracted-world detection implementation:

- Extracts into a temporary directory instead of directly into `${DATA_DIR}`.
- Inspects fixture layouts deterministically.
- Moves exactly one validated source into `${WORLD_DIR}`.
- Rejects ambiguous layouts with a clear error.
- Adds fixture ZIP smoke tests.
- Delays `rm -rf "${WORLD_DIR}"` until after download, unzip, and layout
  detection succeed. This is intentional safer behavior for this detection PR,
  not broader path-safety hardening.

This implementation does not:

- Change S3/MinIO behavior.
- Change `S3_BUCKET` or `WORLD_S3_PREFIX` semantics.
- Change temp archive behavior.
- Change `rm -rf` path-safety.
- Change `reset-world.flag` cleanup after successful install.
- Change `world_reset.sh`.
- Change `install_world` call sites.
- Combine with MinIO or `mc` dependency remediation.

## Fixture Smoke Coverage

Detection smoke tests:

- Use temporary `DATA_DIR` values.
- Use local fixture ZIP files.
- Use mocked `mc cp`.
- Avoid real S3 or MinIO.
- Avoid Minecraft server boot.
- Avoid server artifact downloads.
- Avoid destructive paths outside temp directories.
- Verify temporary archive cleanup and observable extraction temp cleanup.
- Verify failed detection does not remove `reset-world.flag`.

Fixture layouts:

- Direct `world/level.dat`.
- Single-root valid world directory: `MyWorld/level.dat`.
- Flat valid layout with root `level.dat`.
- Multiple candidate directories.
- No `level.dat`.
- Nested-only layout: `backups/world/level.dat`.
- Malformed archive remains covered by unzip error smoke.
