# runtime.sh marker temporary-file cleanup boundary

This note defines the boundary for a future behavior-preserving cleanup of
temporary-file handling in `scripts/lib/runtime.sh`, especially
`write_server_install_marker`.

This note is documentation-only. It records current marker behavior to preserve
before any implementation PR changes marker temporary-file handling.

Implementation status: design-ready only. No runtime behavior has changed.

## Current behavior to preserve

`runtime.sh` owns the server install marker helpers used by server artifact
installation and `TYPE=auto` resolution.

- `server_install_marker` returns `${DATA_DIR}/.server-install.json`.
- The marker JSON object is written with these fields:
  - `artifact`
  - `type`
  - `version`
  - `build`
- `write_server_install_marker` receives artifact, installed type, installed
  version, and optional build value.
- When no build value is passed, the marker still contains `"build": ""`.
- The current marker temporary file name is `tmp="${marker}.tmp.$$"`.
- The current write flow uses `jq -n` with `--arg` values, redirects JSON to
  the temporary file, then runs `mv -f "$tmp" "$marker"`.
- The final `mv -f` provides the existing replacement behavior once the
  temporary marker file has been written.
- There is currently no explicit cleanup branch for a failed `jq`, redirection,
  or `mv`.

`assert_server_install_matches` currently behaves as follows:

- If the expected artifact exists but the marker file is missing, it logs a
  warning and leaves the artifact in place.
- If the marker exists, it reads `.type`, `.version`, and `.artifact` with
  `jq -r '.field // empty'`.
- If any of those values differ from the requested artifact, type, or version,
  it fails fast rather than replacing the existing server artifact
  automatically.
- Invalid or corrupt marker JSON is not handled specially here; `jq` errors are
  not suppressed in this path.

`resolve_type_auto` currently behaves as follows:

- It only runs when `TYPE` is `auto` or `AUTO`.
- If the marker exists, it reads `.type` and `.artifact` with `jq`, suppressing
  parse errors and using `|| true`.
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
- If the marker type is supported and the marker artifact exists under
  `${DATA_DIR}`, `TYPE` is set to the marker type.
- If the marker artifact is missing, the marker type is empty, or the marker
  type is unsupported, it logs a warning and falls back to artifact detection.
- With no usable marker, artifact detection checks `velocity.jar`,
  `fabric-server-launch.jar`, Forge/NeoForge `run.sh`, and `server.jar`, then
  falls back to `vanilla`.
- Invalid or corrupt marker JSON currently flows through the suppressed `jq`
  reads, produces empty marker values, logs the empty-type fallback warning, and
  continues to artifact detection.

Current Spigot marker behavior is intentionally not decided by this note:

- `is_supported_runtime_type` includes `spigot`.
- `uses_server_properties` includes `spigot`.
- `install_spigot_server_artifact` requires an existing `${DATA_DIR}/server.jar`
  and does not provide a managed Spigot installer.
- The Spigot install path validates an existing `server.jar` with
  `assert_server_install_matches "server.jar" "spigot" "${VERSION}"`.
- The managed install path does not currently write a Spigot marker.
- `resolve_type_auto` does not include `spigot` in its marker-supported type
  list, and artifact fallback has no Spigot-specific detection branch.

## Implementation boundary

A future marker temporary-file implementation PR may:

- Replace `tmp="${marker}.tmp.$$"` with `mktemp` in the same directory as the
  marker.
- Preserve the current write-then-`mv -f` replacement behavior.
- Clean up the temporary marker file after successful replacement.
- Clean up the temporary marker file on failed `jq`, redirection, or `mv` where
  practical.
- Keep marker directory and path semantics unchanged.
- Preserve marker JSON field names.
- Preserve marker field values passed by existing installers, including type,
  version, artifact, and build/loader values.
- Keep the change scoped to `write_server_install_marker` unless a small local
  helper is needed only for marker temp-file cleanup.

A future marker temporary-file implementation PR must not:

- Change marker JSON shape.
- Change marker matching rules.
- Change `assert_server_install_matches` behavior.
- Change `resolve_type_auto` behavior.
- Change invalid or corrupt marker JSON behavior.
- Change Spigot marker support behavior.
- Change `TYPE` resolution behavior.
- Change install dispatch behavior.
- Change runtime launch behavior.
- Change server artifact installation behavior.
- Combine with S3, world install/reset, Velocity, MinIO, or Spigot BuildTools
  cleanup.

## Behavior-changing follow-ups

These are separate behavior decisions and should not be included in the marker
temporary-file cleanup implementation:

- Invalid or corrupt marker JSON handling in `assert_server_install_matches`
  and `resolve_type_auto`.
- Spigot marker support and `resolve_type_auto` support decisions.
- Marker schema changes, if ever needed.

## Staged plan

1. Docs-only marker cleanup boundary.
   This PR.

2. Behavior-preserving `write_server_install_marker` temp-file cleanup only.
   Use `mktemp` in the marker directory, preserve marker JSON shape and
   write-then-`mv -f` replacement behavior, and add offline smoke tests.

3. Separate invalid or corrupt marker JSON behavior PR, only if desired.

4. Separate Spigot marker support behavior PR, only if desired.

## Smoke guidance

Future implementation smoke tests should:

- Source `scripts/lib/runtime.sh` under `set -euo pipefail`.
- Use a temporary `DATA_DIR`.
- Exercise `write_server_install_marker` without network calls.
- Verify marker JSON fields are unchanged.
- Verify field values are unchanged for representative artifact, type, version,
  and build values.
- Verify the temporary marker file is cleaned up on success.
- Mock a failure path where practical without changing production behavior.
- Avoid Minecraft server boot.
- Avoid install artifact downloads.
- Avoid S3 credentials, MinIO, or network-backed services.
