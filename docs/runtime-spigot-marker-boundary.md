# runtime.sh Spigot marker auto-resolution boundary

This note defines a docs-only boundary for whether and how `TYPE=auto` should
resolve valid server install markers whose `type` is `spigot`.

Status: implemented for marker auto-resolution. `TYPE=auto` resolves a valid
Spigot install marker when the marker artifact exists under `${DATA_DIR}`.
Marker write format, marker temporary-file handling, corrupt and incomplete
marker fail-fast behavior, missing marker fallback behavior, `install_server`
dispatch, server artifact download behavior, explicit `TYPE=spigot`
bring-your-own behavior, and Spigot BuildTools/self-build behavior are
unchanged. Spigot BuildTools/self-build remains separate feature work.

## Current Behavior

`scripts/lib/runtime.sh` owns runtime type predicates, server install marker
helpers, and `TYPE=auto` resolution.

- `is_supported_runtime_type` includes `spigot`.
- `uses_server_properties` includes `spigot`.
- `resolve_type_auto` validates existing markers through
  `read_server_install_marker_field`.
- `resolve_type_auto` reads the marker `artifact`, `type`, `version`, and
  `build` fields before considering marker resolution.
- `resolve_type_auto` marker-supported types are:
  - `fabric`
  - `forge`
  - `mohist`
  - `neoforge`
  - `paper`
  - `purpur`
  - `quilt`
  - `spigot`
  - `taiyitist`
  - `vanilla`
  - `velocity`
  - `youer`
- `resolve_type_auto` includes `spigot` in the marker-supported type case.
- If `TYPE=auto` sees a valid marker with `type=spigot` and the marker
  artifact exists under `${DATA_DIR}`, it resolves `TYPE` to `spigot` and
  logs `TYPE auto-resolved to 'spigot' from install marker`.
- Artifact detection does not have a Spigot-specific branch. A present
  `${DATA_DIR}/server.jar` resolves to `vanilla` when no supported marker
  resolves first.

`scripts/lib/server_install.sh` owns the current explicit Spigot artifact
handling.

- `install_spigot_server_artifact` requires `VERSION`.
- If `${DATA_DIR}/server.jar` exists, it validates that artifact with
  `assert_server_install_matches "server.jar" "spigot" "${VERSION}"`, logs that
  it is using the existing Spigot artifact, and returns.
- If `${DATA_DIR}/server.jar` is missing, it fails with
  `TYPE=spigot requires an existing /data/server.jar; managed Spigot installer is not provided`.
- Current Spigot mode is bring-your-own artifact only.
- Managed Spigot BuildTools/self-build is not implemented and remains feature
  work, not marker cleanup.

Existing smoke coverage includes:

- Runtime smoke for explicit `TYPE=spigot` failing when no artifact exists.
- Runtime smoke for explicit `TYPE=spigot` using an existing `server.jar`.
- Runtime smoke for `TYPE=auto` resolving a valid `paper` marker.
- Runtime marker smoke for `TYPE=auto` resolving a valid `velocity` marker.
- Runtime marker smoke for `TYPE=auto` resolving a valid `spigot` marker.
- Runtime marker smoke for corrupt and incomplete marker fail-fast behavior.

The previous mismatch between explicit `TYPE=spigot` support and marker-based
`TYPE=auto` behavior is resolved for valid existing install markers.

## Behavior Policy

Implemented policy: add Spigot to marker-supported `TYPE=auto` types.

With `spigot` in the `resolve_type_auto` marker-supported type case, a valid
marker whose `type` is `spigot` and whose artifact exists under `${DATA_DIR}`,
`TYPE=auto` resolves to `spigot`.

Rationale: if a valid marker says the installed artifact is Spigot and the
runtime supports explicit `TYPE=spigot`, marker-based `TYPE=auto` should honor
that existing installed state.

Risk: users may read marker auto-resolution support as broader managed Spigot
install support.

Guardrail: keep this limited to marker resolution for existing installed
artifacts. Do not add BuildTools/self-build, download behavior, or install
dispatch changes.

Rejected alternative: keep Spigot excluded.

Leave `spigot` out of the `resolve_type_auto` marker-supported type case.

Rationale: avoids implying official managed Spigot install support.

Risk: valid installed Spigot artifacts cannot resolve through marker-based
`TYPE=auto` even though explicit `TYPE=spigot` is supported elsewhere.
Marker auto-resolution may fall through to artifact detection and classify the
same `server.jar` as `vanilla`.

Rejected alternative: add Spigot after BuildTools/self-build.

Keep Spigot marker auto-resolution excluded until a future managed Spigot
BuildTools/self-build feature exists.

Rationale: marker auto support would align with full managed install support.

Risk: delays support for bring-your-own Spigot artifact marker resolution and
keeps the current supported-runtime versus marker-auto mismatch in place.

This policy treats marker auto-resolution as a read of existing install
state, not as a claim that the image can build or download Spigot.

## Implementation Boundary

The implementation:

- Keeps `spigot` in the marker-supported `TYPE=auto` case in
  `scripts/lib/runtime.sh`.
- Adds smoke coverage for valid Spigot marker resolution.
- Preserve explicit `TYPE=spigot` behavior.
- Preserve corrupt and incomplete marker fail-fast behavior.
- Preserve missing marker fallback behavior.
- Preserve Spigot bring-your-own artifact behavior.
- Keep BuildTools/self-build out of scope.

The implementation does not:

- Implement Spigot BuildTools/self-build.
- Change server artifact download behavior.
- Change `install_server` dispatch.
- Change marker write format.
- Change marker temporary-file handling.
- Change corrupt marker handling.
- Change S3/MinIO behavior.
- Combine with Velocity config ownership.
- Combine with unrelated cleanup.

## Smoke Guidance

Smoke tests should cover:

- `TYPE=auto` with valid marker `type=spigot` resolves to `spigot`.
- `TYPE=auto` with valid marker `type=paper` still resolves as before.
- `TYPE=auto` with an unsupported marker type still behaves as currently
  expected, unless that behavior is explicitly scoped.
- `TYPE=auto` with corrupt marker still fails with
  `Invalid/corrupt server install marker JSON`.
- `TYPE=auto` with incomplete marker still fails with
  `Incomplete server install marker`.
- Explicit `TYPE=spigot` behavior remains covered.
- No BuildTools/self-build.
- No server boot.
- No artifact downloads.
- No S3/MinIO.
