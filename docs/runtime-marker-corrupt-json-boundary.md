# runtime.sh corrupt marker JSON boundary

This note records the boundary and implementation for corrupt
`${DATA_DIR}/.server-install.json` handling in `scripts/lib/runtime.sh`.

Implementation status: completed. Runtime behavior now fails fast when an
existing server install marker is corrupt or incomplete. Marker format, marker
write behavior, install dispatch, server artifact download behavior, and the
`TYPE=auto` marker-supported type list are unchanged.

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

`assert_server_install_matches` now behaves as follows:

- It is called by server artifact installers when the expected artifact already
  exists.
- If the artifact exists but the marker file is missing, it logs a warning and
  leaves the artifact in place.
- If the marker exists, it validates the marker as a JSON object and reads the
  required `artifact`, `type`, `version`, and `build` fields.
- If any read value differs from the requested artifact, type, or version, it
  fails with the existing artifact mismatch error rather than replacing the
  artifact automatically.
- If marker JSON is corrupt or unreadable as JSON, it fails with
  `Corrupt server install marker`.
- If marker JSON is valid but missing a required field or has a null required
  field, it fails with `Incomplete server install marker`.
- An empty `build` field remains valid when the field exists.

`resolve_type_auto` now behaves as follows:

- It only runs when `TYPE` is `auto` or `AUTO`.
- If the marker exists, it validates the marker as a JSON object and reads the
  required `artifact`, `type`, `version`, and `build` fields.
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
  `resolve_type_auto` behavior decision. See
  [`docs/runtime-spigot-marker-boundary.md`](runtime-spigot-marker-boundary.md).
- If the marker type is supported and the marker artifact exists under
  `${DATA_DIR}`, `TYPE` is set from the marker and auto resolution returns.
- If the marker artifact is missing, marker type is empty, or marker type is
  unsupported, it logs a warning and falls back to artifact detection.
- If the marker is missing, it goes directly to artifact detection.
- Artifact detection checks `velocity.jar`, `fabric-server-launch.jar`,
  Forge/NeoForge `run.sh`, and `server.jar`, then falls back to `vanilla`.
- If marker JSON is corrupt or unreadable as JSON, it fails with
  `Corrupt server install marker` and does not continue to artifact detection.
- If marker JSON is valid but missing a required field or has a null required
  field, it fails with `Incomplete server install marker` and does not continue
  to artifact detection.
- An empty `build` field remains valid when the field exists.

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

## Implemented policy

The implementation follows Option A: fail fast.

The project generally favors explicit, predictable failure for ambiguous install
state. A corrupt marker is different from a missing marker: missing marker
behavior is already non-fatal in some paths, but an existing corrupt marker
claims to be authoritative install state and should not be silently ignored.

Current policy:

- Missing marker remains non-fatal where currently non-fatal.
- Existing corrupt marker fails fast with `Corrupt server install marker`.
- Existing marker with missing or null required fields fails fast with
  `Incomplete server install marker`.
- Valid marker mismatch continues to fail as today.
- `TYPE=auto` does not silently ignore a corrupt or incomplete marker.
- The implementation does not delete, rewrite, or quarantine corrupt markers.
- The implementation does not change marker write behavior.
- The implementation does not change marker temporary-file handling.

## Implementation boundary

The implementation:

- Adds a small marker-reading helper in `scripts/lib/runtime.sh`.
- Centralizes server install marker reads for `assert_server_install_matches`
  and `resolve_type_auto`.
- Detects invalid JSON explicitly.
- Detects missing required marker fields explicitly.
- Emits stable error messages.
- Adds offline smoke tests for corrupt marker JSON and missing required fields.
- Preserves existing valid marker behavior.
- Preserves existing missing marker behavior.

The implementation does not:

- Change server install marker write format.
- Change marker temporary-file handling.
- Change `install_server` dispatch.
- Change server artifact download behavior.
- Change the `TYPE=auto` marker-supported type list.
- Add Spigot marker support in the same PR.
- Change S3/MinIO behavior.
- Combine with unrelated cleanup.

## Smoke coverage

Smoke tests cover:

- Valid marker matching expected artifact, type, version, and build.
- Valid marker mismatch failing as before.
- Missing marker behavior remaining non-fatal where currently non-fatal.
- Corrupt marker JSON failing with `Corrupt server install marker`.
- Valid JSON missing required fields failing with
  `Incomplete server install marker`.
- `TYPE=auto` with a valid marker resolving as before.
- `TYPE=auto` with corrupt marker failing with
  `Corrupt server install marker`.
- `TYPE=auto` with incomplete marker failing with
  `Incomplete server install marker`.
- Avoid Minecraft server boot.
- Avoid artifact downloads.
- Avoid S3/MinIO.
