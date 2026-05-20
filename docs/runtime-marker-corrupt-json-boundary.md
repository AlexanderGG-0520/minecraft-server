# runtime.sh corrupt marker JSON boundary

This note defines a docs-only boundary for future corrupt
`${DATA_DIR}/.server-install.json` handling in `scripts/lib/runtime.sh`.

Implementation status: design-ready, not implemented. Runtime behavior, marker
format, install behavior, and `TYPE=auto` behavior are unchanged.

## Current marker behavior

`runtime.sh` owns server install marker helpers used by managed server artifact
installation and `TYPE=auto` resolution.

- `server_install_marker` returns `${DATA_DIR}/.server-install.json`.
- The marker records the installed server artifact state so future installer
  runs can avoid replacing an existing server artifact automatically.
- `write_server_install_marker` writes a JSON object with these fields:
  - `artifact`
  - `type`
  - `version`
  - `build`
- The marker is written with `jq -n` and installed by replacing the final
  marker path after the temporary file has been written.
- Missing `build` input is written as `"build": ""`.
- Marker temporary-file cleanup is already handled by the separate
  [`docs/runtime-marker-cleanup-boundary.md`](runtime-marker-cleanup-boundary.md)
  cleanup and is outside this boundary.

`assert_server_install_matches` currently behaves as follows:

- It is called by server artifact installers when the expected artifact already
  exists.
- If the artifact exists but the marker file is missing, it logs a warning and
  leaves the artifact in place.
- If the marker exists, it reads `.type`, `.version`, and `.artifact` with
  `jq -r '.field // empty'`.
- Those `jq` reads do not suppress parse errors in this path.
- If any read value differs from the requested artifact, type, or version, it
  fails with the existing artifact mismatch error rather than replacing the
  artifact automatically.
- If marker JSON is valid but a required field is missing, that field reads as
  empty and the existing mismatch path fails with `unknown` for empty type or
  version values.
- If marker JSON is corrupt or unreadable, the current behavior is not a stable
  project-level policy. Under the normal `entrypoint.sh` `set -e` execution
  context, the unsuppressed `jq` failure is expected to stop execution before
  the custom marker mismatch message. Other sourced test contexts may expose
  raw `jq` failure behavior.

`resolve_type_auto` currently behaves as follows:

- It only runs when `TYPE` is `auto` or `AUTO`.
- If the marker exists, it reads `.type` and `.artifact` with `jq`, suppressing
  parse errors with `2>/dev/null || true`.
- Marker-supported types in this path are currently:
  - `fabric`
  - `forge`
  - `mohist`
  - `neoforge`
  - `paper`
  - `purpur`
  - `quilt`
  - `taiyitist`
  - `vanilla`
  - `velocity`
  - `youer`
- `spigot` marker support is not part of this boundary and remains a separate
  `resolve_type_auto` behavior decision.
- If the marker type is supported and the marker artifact exists under
  `${DATA_DIR}`, `TYPE` is set from the marker and auto resolution returns.
- If the marker artifact is missing, marker type is empty, or marker type is
  unsupported, it logs a warning and falls back to artifact detection.
- If the marker is missing, it goes directly to artifact detection.
- Artifact detection checks `velocity.jar`, `fabric-server-launch.jar`,
  Forge/NeoForge `run.sh`, and `server.jar`, then falls back to `vanilla`.
- If marker JSON is valid but missing `.type`, the current behavior is the
  empty-type warning followed by artifact detection.
- If marker JSON has a supported `.type` but missing `.artifact`, the current
  behavior is the artifact-missing warning with `unknown`, followed by artifact
  detection.
- If marker JSON is corrupt or unreadable, suppressed `jq` errors currently
  produce empty marker values, log the empty-type fallback warning, and continue
  to artifact detection.

## Future policy candidates

### Option A: fail fast

If `.server-install.json` exists but is invalid JSON, fail with an explicit
error such as:

```text
Corrupt server install marker
```

Rationale: the marker exists as install state. Corrupt install state should not
be silently ignored because it may lead to the wrong server type or artifact
being used.

Risk: users with a corrupt marker must repair or remove the marker explicitly
before recovery.

### Option B: ignore corrupt marker and fall back

If the marker is corrupt, ignore it and continue to artifact detection or
normal `TYPE=auto` fallback behavior.

Rationale: this may improve recovery when the marker is damaged but artifacts
are otherwise usable.

Risk: it may hide state corruption, boot the wrong server type, or make later
artifact mismatch behavior harder to understand.

### Option C: quarantine corrupt marker, then fall back

Move or rename the corrupt marker for inspection, then continue to artifact
detection or normal `TYPE=auto` fallback behavior.

Rationale: this preserves the corrupt marker while allowing recovery.

Risk: it changes filesystem state during read/validation, may surprise users,
and introduces naming, retention, and collision behavior that would need its
own policy.

## Recommended future policy

Prefer Option A: fail fast.

The project generally favors explicit, predictable failure for ambiguous install
state. A corrupt marker is different from a missing marker: missing marker
behavior is already non-fatal in some paths, but an existing corrupt marker
claims to be authoritative install state and should not be silently ignored.

Recommended policy for a future implementation:

- Missing marker remains non-fatal where currently non-fatal.
- Existing corrupt marker fails fast with an explicit error.
- Existing marker with missing required fields fails fast with an explicit
  error.
- Valid marker mismatch continues to fail as today.
- `TYPE=auto` does not silently ignore a corrupt marker.
- The first implementation PR does not delete, rewrite, or quarantine corrupt
  markers.
- The first implementation PR does not change marker write behavior.
- The first implementation PR does not change marker temporary-file handling.

## Future implementation boundary

A future implementation PR may:

- Add a small marker-reading helper in `scripts/lib/runtime.sh`.
- Centralize `jq` marker reads.
- Detect invalid JSON explicitly.
- Detect missing required marker fields explicitly.
- Emit stable error messages.
- Add smoke tests for corrupt marker JSON and missing required fields.
- Preserve existing valid marker behavior.
- Preserve existing missing marker behavior.

A future implementation PR must not:

- Change server install marker write format unless intentionally scoped.
- Change marker temporary-file handling.
- Change `install_server` dispatch.
- Change server artifact download behavior.
- Change the `TYPE=auto` marker-supported type list.
- Add Spigot marker support in the same PR.
- Change S3/MinIO behavior.
- Combine with unrelated cleanup.

## Smoke guidance

Future implementation smoke tests should:

- Use a temporary `DATA_DIR`.
- Source `scripts/lib/runtime.sh` under `set -euo pipefail`.
- Verify a valid marker matching expected artifact, type, version, and build
  behaves as before.
- Verify a valid marker mismatch fails as before.
- Verify missing marker behavior remains as currently expected.
- Verify corrupt marker JSON fails with an explicit error.
- Verify valid JSON missing required fields fails with an explicit error.
- Verify `TYPE=auto` with a valid marker resolves as before.
- Verify `TYPE=auto` with a corrupt marker fails explicitly.
- Avoid Minecraft server boot.
- Avoid artifact downloads.
- Avoid S3/MinIO.
