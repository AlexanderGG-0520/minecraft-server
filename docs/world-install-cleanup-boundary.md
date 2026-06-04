# world_install.sh cleanup boundary

This note defines safe PR boundaries for future cleanup of temporary-file and
extraction handling in `scripts/lib/world_install.sh`.

This note records current behavior and cleanup boundaries for world install
archive handling.

Implementation status: fixed temp archive cleanup, unzip error-message cleanup,
deterministic extracted-world detection, `world_install.sh` DATA_DIR/WORLD_DIR
path-safety hardening, and separate `world_reset.sh` path-safety hardening are
completed. Separate `world_reset.sh` obvious function-local variable
localization and backup/temp/atomic handling are also completed. Other reset
behavior changes remain separate.

## Current behavior to preserve

`world_install.sh` currently defines `install_world`. The library is sourced by
`entrypoint.sh` and included in source-smoke checks. Current call-site
inspection did not find `install_world` called from the main `install()` flow;
changing when it runs would be an orchestration behavior change and is outside
this cleanup boundary.

Inside `install_world`, current behavior is:

- `WORLD_DIR` is local to the function and set to `${DATA_DIR}/world`.
- If `WORLDS_ENABLED` is unset or is not `true`, world install logs
  `Worlds disabled` and returns.
- If `${WORLD_DIR}` already exists and `${DATA_DIR}/reset-world.flag` is not
  present, world install logs that the world already exists and returns.
- If `${DATA_DIR}/reset-world.flag` is present, the existing-world skip guard
  does not return early.
- If either `WORLDS_S3_BUCKET` or `WORLDS_S3_PREFIX` is empty or unset, world
  install logs that the S3 world settings are missing and returns.
- When installation proceeds, it logs `Installing world from S3`.
- The archive path is created with `mktemp /tmp/world.XXXXXX.zip`.
- The extraction directory is created with `mktemp -d /tmp/world-extract.XXXXXX`.
- The MinIO client alias is configured with `configure_mc_alias "world"`.
- The direct child objects under `WORLDS_S3_BUCKET` and `WORLDS_S3_PREFIX` are
  listed without recursive traversal.
- Exactly one direct child `.zip` archive is selected and downloaded to
  `${TMP_ZIP}`.
- Zero direct child `.zip` archives or multiple direct child `.zip` archives
  fail before download.
- Download failure calls `die "Failed to download world archive"`.
- Extraction runs into the temporary extraction directory:
  - `unzip -q "${TMP_ZIP}" -d "${EXTRACT_DIR}"`
- Unzip failure removes the temporary archive, logs
  `Failed to extract world archive with unzip`, and returns failure.
- Detection supports direct `world/level.dat`, single-root `MyWorld/level.dat`,
  and flat root `level.dat` layouts.
- Multiple valid world candidates fail with `Ambiguous world archive layout`.
- Missing supported top-level `level.dat` layouts fail with
  `Failed to detect world directory in archive`.
- Existing `${WORLD_DIR}` is removed with `rm -rf "${WORLD_DIR}"` only after the
  archive has downloaded, extracted, and matched a supported layout.
- `validate_world_install_paths` validates `DATA_DIR` and `WORLD_DIR` before
  creating/replacing `${WORLD_DIR}` and immediately before
  `rm -rf "${WORLD_DIR}"`.
- The selected extracted source is moved to `${WORLD_DIR}`.
- The temporary archive path and extraction directory are removed after
  extraction detection and install complete.
- `${DATA_DIR}/reset-world.flag` is removed after the archive cleanup.
- Success logs `World installed successfully`.

Current failure behavior is also part of the boundary:

- A failed `mc cp` fails with the existing download error message.
- A failed `unzip` logs the explicit extract failure message.
- Failed layout detection logs an explicit detection or ambiguity message,
  removes temporary files, returns failure, and does not remove
  `${DATA_DIR}/reset-world.flag`.
- Temp archive and extraction directory cleanup is attempted after failed
  download, failed unzip, or failed layout detection.

Current S3/MinIO dependency behavior:

- World install uses the shared S3 client setup through `configure_mc_alias`.
- It does not call `ensure_s3_source_nonempty_for_remove`.
- It depends on the existing MinIO alias and environment behavior owned by
  `scripts/lib/s3_client.sh`.

## Future PR boundaries

### A. Behavior-preserving temp archive cleanup

A focused implementation PR may:

- Replace the fixed `/tmp/world.zip` path with `mktemp` or a temporary
  directory.
- Preserve archive download semantics.
- Preserve `mc cp` source path semantics.
- Preserve unzip/extract semantics.
- Preserve existing world replacement behavior.
- Add temp archive cleanup on success and failure.
- Keep the cleanup scoped to `scripts/lib/world_install.sh`.

Status: completed for the fixed temp archive path cleanup.

That PR must not:

- Change extracted-world detection.
- Change `WORLDS_ENABLED`, `WORLDS_S3_BUCKET`, or `WORLDS_S3_PREFIX` semantics.
- Change S3/MinIO behavior.
- Change `rm -rf` target behavior.
- Change install order or runtime launch behavior.

### B. Unzip error-message cleanup

A separate PR may:

- Add an explicit `die` or log message for unzip failure.
- Preserve failure timing and install behavior where practical.
- Add an unzip failure smoke test with a local fixture archive.

Keep this separate unless it is trivially and clearly part of the temp archive
cleanup without changing behavior.

Status: completed with explicit `Failed to extract world archive with unzip`
messaging.

### C. Extracted world directory detection improvement

Design boundary:
[`docs/world-install-extraction-detection.md`](world-install-extraction-detection.md).

A dedicated behavior-sensitive PR may:

- Replace the broad `find ... -name "*world*" | head -n1` fallback.
- Define expected archive layouts before changing detection.
- Add fixture ZIP archives for direct `world/`, single-root, nested, and
  ambiguous layouts.

Treat detection changes as behavior-changing unless proven otherwise.

Status: completed with deterministic temporary extraction detection.

### D. DATA_DIR/WORLD_DIR path-safety hardening

Design boundary:
[`docs/world-install-path-safety.md`](world-install-path-safety.md).

A separate high-risk PR may:

- Harden empty or unset `DATA_DIR` and `WORLD_DIR` checks before `rm -rf`.
- Validate resolved paths with harmless temporary directories.
- Add strict path-safety smoke tests.

Do not combine this with temp archive cleanup or extracted-world detection
changes.

Status: completed for `world_install.sh`. The implementation requires an
absolute non-empty `DATA_DIR`, validates the derived and resolved `WORLD_DIR`,
and fails before `rm -rf "${WORLD_DIR}"` when paths are unsafe.

### E. world_reset.sh cleanup

Keep `world_reset.sh` work separate from `world_install.sh` cleanup.
Do not combine reset flag behavior, reset backups, reset path safety, or reset
timing changes with world archive handling.

Path-safety design boundary:
[`docs/world-reset-path-safety.md`](world-reset-path-safety.md).

Status: completed for `world_reset.sh` path-safety, separate obvious
function-local variable localization, and backup/temp/atomic handling. Other
reset behavior changes remain separate.

## Guardrails

Future implementation must not casually:

- Change `WORLDS_ENABLED`, `WORLDS_S3_BUCKET`, or `WORLDS_S3_PREFIX` semantics.
- Change S3/MinIO alias or credential behavior.
- Change `DATA_DIR` or `WORLD_DIR` semantics.
- Change `rm -rf` target behavior outside a dedicated path-safety PR.
- Change extracted world detection in a temp-file-only PR.
- Change install order or runtime launch behavior.
- Combine with MinIO or `mc` dependency remediation.
- Combine with server artifact installation.
- Combine with world reset cleanup.

## Smoke guidance

Future implementation smoke tests should:

- Use temporary `DATA_DIR` values.
- Use local fixture ZIP archives.
- Mock `configure_mc_alias` and `mc cp` when testing without S3.
- Avoid real S3 or MinIO network calls.
- Verify temp archive cleanup after success.
- Verify temp archive cleanup after download or unzip failure where practical.
- Verify unzip failure messaging only in the dedicated unzip-message PR.
- Verify extracted world detection with controlled fixture layouts only in the
  detection PR.
- Verify path-safety checks with harmless temp directories only in the
  path-safety PR.
- Avoid Minecraft server boot.
- Avoid server artifact downloads.
