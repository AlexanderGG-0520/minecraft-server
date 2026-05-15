# world install extraction detection

This note defines the behavior boundary for a future improvement to extracted
world directory detection in `scripts/lib/world_install.sh`.

This note is documentation-only. It does not change world install behavior.

Implementation status: design-ready only. Extracted-world detection is not
changed.

## Current Detection Behavior

`install_world` currently prepares and extracts a downloaded world archive as
follows:

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

Because `${WORLD_DIR}` is created before extraction, the fallback detection is
normally bypassed after a successful prepare step. This means current archive
layout behavior is mostly determined by what `unzip` writes into an already
existing `${DATA_DIR}/world` directory, not by the fallback finder.

## Current Layout Ambiguity

These observations describe current behavior to preserve until a dedicated
behavior PR intentionally changes it:

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

## Future Layout Policy Candidates

A future behavior PR should define supported layouts before changing code.
Candidate policies:

- Direct world directory layout: `world/level.dat`
  - Candidate behavior: support as-is.
  - Candidate validation: require `world/level.dat`.
- Single-root world layout: `MyWorld/level.dat`
  - Candidate behavior: normalize by moving exactly one validated root directory
    into `${WORLD_DIR}`.
  - Candidate validation: require exactly one top-level directory containing
    `level.dat`.
- Flat archive layout: `level.dat` at archive root
  - Candidate behavior: either support by extracting into `${WORLD_DIR}` or
    reject with an explicit error.
  - Status: behavior decision.
- Nested layout: `backups/world/level.dat`
  - Candidate behavior: reject unless a future user opt-in is added.
  - Status: behavior decision.
- Multiple candidate directories:
  - Candidate behavior: reject with a clear ambiguous layout error.
  - Candidate validation: do not pick by name order.
- Empty or invalid world layout:
  - Candidate behavior: reject with a clear error after successful unzip.
  - Malformed ZIP files should remain covered by the unzip failure path.

## Future Implementation Boundary

A future extracted-world detection implementation may:

- Extract into a temporary directory instead of directly into `${DATA_DIR}`, if
  the PR explicitly owns detection behavior.
- Inspect fixture layouts deterministically.
- Move exactly one validated world directory into `${WORLD_DIR}`.
- Reject ambiguous layouts with a clear error.
- Add fixture ZIP smoke tests.

A future extracted-world detection implementation must not:

- Change S3/MinIO behavior.
- Change `WORLD_S3_BUCKET` or `WORLD_S3_KEY` semantics.
- Change temp archive behavior unless required and documented.
- Change `rm -rf` path-safety in the same PR.
- Change `reset-world.flag` behavior in the same PR.
- Change `world_reset.sh`.
- Change `install_world` call sites.
- Combine with MinIO or `mc` dependency remediation.

## Fixture Smoke Guidance

Future detection smoke tests should:

- Use temporary `DATA_DIR` values.
- Use local fixture ZIP files.
- Use mocked `mc cp`.
- Avoid real S3 or MinIO.
- Avoid Minecraft server boot.
- Avoid server artifact downloads.
- Avoid destructive paths outside temp directories.

Recommended fixture layouts:

- Direct `world/level.dat`.
- Single-root valid world directory, such as `MyWorld/level.dat`.
- Flat valid layout with root `level.dat`, if supported.
- Multiple candidate directories.
- No `level.dat`.
- Malformed archive, which should remain covered by unzip error smoke.
