# entrypoint.sh cleanup and hardening backlog

This backlog captures non-mechanical cleanup and hardening items observed while
splitting `entrypoint.sh` responsibilities into `scripts/lib/*.sh`.

These items were intentionally not fixed during the mechanical boundary
extraction PRs. Each item may change behavior, error handling, logging, or
failure timing. Handle them in dedicated PRs with focused smoke tests, and do
not mix them into future mechanical moves.

Preserve existing runtime behavior unless a PR explicitly chooses and documents
a behavior change.

## Current remaining cleanup categories

- Low-risk / mechanical:
  - Very little remains after the recent focused cleanup PRs. Treat any new
    low-risk item as a separate, explicit boundary before implementation.
- Behavior-changing / needs design:
  - Spigot marker support / `resolve_type_auto` behavior. Design boundary:
    [`docs/runtime-spigot-marker-boundary.md`](runtime-spigot-marker-boundary.md).
  - Velocity config ownership and double-call behavior.
  - Velocity install/config coupling.
- High-risk / destructive-path-adjacent:
  - `world_reset.sh` duplicated reset flag removal.
  - `world_reset.sh` backup/temp/atomic failure handling.
- Feature work, not cleanup:
  - Spigot BuildTools / self-build support.
  - Optional MinIO `mc` client replacement.
  - MinIO `mc` acquisition strategy changes.

## Prioritized backlog

### 1. Low-risk shell hygiene

- `logging.sh` - review `die` argument handling.
  - Status: completed. `die` now forwards all arguments through `log` while
    preserving the existing log format.
  - Risk: low.
  - Suggested PR boundary: `scripts/lib/logging.sh`.
  - Do not change log format semantics or error text shape unless the PR is
    explicitly about that behavior.
  - Suggested checks: `bash -n`, ShellCheck, source smoke for the logging
    helper.

- `server_properties.sh` - review `TYPE` access under `set -u`.
  - Status: completed. `server_properties.sh` now localizes `TYPE` with an
    unset-safe default before bootstrap decisions.
  - Risk: low.
  - Suggested PR boundary: `scripts/lib/server_properties.sh`.
  - Do not change bootstrap behavior or log semantics.
  - Suggested checks: `bash -n`, source smoke for server property bootstrap.

- `server_install.sh` - localize preserved variables where safe and review
  wording around missing `run.sh` / artifact-selection failures.
  - Status: local-variable hygiene pass completed for obvious function-local
    installer temporaries only.
  - Risk: low.
  - Suggested PR boundary: `scripts/lib/server_install.sh`.
  - Do not change download URLs, marker semantics, or install order.
  - Suggested checks: `bash -n`, install-focused smoke with mocked downloads.

- `runtime_launch.sh` - review launch error wording and keep launch commands
  unchanged.
  - Status: completed. Forge/NeoForge missing `run.sh` launch errors are
    covered to use the current `TYPE` in the message.
  - Risk: low.
  - Suggested PR boundary: `scripts/lib/runtime_launch.sh`.
  - Do not change `run_server`, `runtime`, `JVM_ARGS_FILE`, `cd`,
    or runtime-specific launch commands.
  - Suggested checks: `bash -n`, source smoke, mocked launch-command smoke.

### 2. Temp-file and atomic-write hardening

- `s3_client.sh` - harden temporary-file cleanup in
  `ensure_s3_source_nonempty_for_remove`.
  - Status: completed for the focused temp cleanup pass. See
    `docs/s3-client-cleanup-boundary.md` for the behavior-preserving boundary.
  - Risk: medium.
  - Suggested PR boundary: `scripts/lib/s3_client.sh`.
  - Do not change S3 environment variable names, alias name `s3`, or remove
    MinIO support.
  - Suggested checks: `bash -n`, source smoke, mocked `mc`/temp-file smoke.

- `runtime.sh` - consider safer marker temp-file handling in
  `write_server_install_marker`.
  - Status: completed for the focused marker temp-file cleanup pass. See
    [`docs/runtime-marker-cleanup-boundary.md`](runtime-marker-cleanup-boundary.md)
    for the behavior-preserving marker temp-file cleanup boundary.
  - Risk: medium.
  - Suggested PR boundary: `scripts/lib/runtime.sh`.
  - Do not change marker path layout or JSON shape in the same PR.
  - Suggested checks: `bash -n`, source smoke, marker write/read smoke.

- `world_install.sh` - improve `unzip` error handling and review the fixed
  `/tmp/world.zip` temp path.
  - Status: fixed temp archive cleanup, unzip error-message cleanup, and
    deterministic extracted-world detection completed. See
    [`docs/world-install-cleanup-boundary.md`](world-install-cleanup-boundary.md)
    for separate temp archive and extraction cleanup boundaries.
  - Risk: medium.
  - Suggested PR boundary: `scripts/lib/world_install.sh`.
  - Do not change world install order or extracted contents in the same PR.
  - Suggested checks: `bash -n`, temp-directory install smoke, unzip failure
    smoke.

### 3. Path-safety hardening

- `world_install.sh` - harden `DATA_DIR` / `WORLD_DIR` path safety before
  `rm -rf`.
  - Status: completed. See
    [`docs/world-install-path-safety.md`](world-install-path-safety.md).
  - Risk: high.
  - Suggested PR boundary: `scripts/lib/world_install.sh`.
  - Do not change the install/reset order or mix in world-reset behavior.
  - Suggested checks: `bash -n`, temp-directory smoke, guard-path smoke.

- `world_reset.sh` - localize variables and harden path checks around
  destructive reset behavior.
  - Status: path-safety completed; obvious function-local variable
    localization completed separately. Remaining reset cleanup is
    behavior-sensitive and destructive-path-adjacent. See
    [`docs/world-reset-path-safety.md`](world-reset-path-safety.md).
  - Risk: high.
  - Suggested PR boundary: `scripts/lib/world_reset.sh`.
  - Do not change reset timing, backup behavior, or other reset semantics in
    the same PR.
  - Suggested checks: `bash -n`, temp-directory reset smoke only.

### 4. Marker and config behavior decisions

- `runtime.sh` - reconcile `spigot` marker support and improve handling of
  corrupt marker JSON.
  - Status: corrupt and incomplete marker fail-fast handling completed. See
    [`docs/runtime-marker-corrupt-json-boundary.md`](runtime-marker-corrupt-json-boundary.md).
    Spigot marker support remains separate.
  - Status: Spigot marker support / `resolve_type_auto` behavior is
    design-ready, not implemented. See
    [`docs/runtime-spigot-marker-boundary.md`](runtime-spigot-marker-boundary.md).
  - Risk: behavior-changing.
  - Suggested PR boundary: `scripts/lib/runtime.sh`.
  - Do not change marker path/JSON format casually.
  - Suggested checks: golden/key-line marker smoke plus invalid-JSON smoke.

- `velocity_config.sh` - review `trim_ws` / `normalize_toml_key` ownership and
  decide whether the double `generate_velocity_toml` call should remain.
  - Risk: behavior-changing.
  - Suggested PR boundary: `scripts/lib/velocity_config.sh`.
  - Do not change generated `velocity.toml` content without a dedicated
    config-behavior PR and focused smoke tests.
  - Suggested checks: temp-directory config generation smoke with exact or
    key-line content checks.

- `server_install.sh` / `velocity_config.sh` - review the coupling between
  Velocity artifact installation and Velocity config generation only in a
  dedicated behavior PR.
  - Risk: behavior-changing.
  - Suggested PR boundary: `scripts/lib/server_install.sh` and
    `scripts/lib/velocity_config.sh`.
  - Do not move the install/config handoff casually.
  - Suggested checks: install smoke plus Velocity config smoke.

### 5. Dependency and remediation work

- `s3_client.sh` / packaging - plan MinIO `mc` dependency or vulnerability
  remediation as a dedicated cleanup PR.
  - Status: build reliability hardening completed for bounded source clone
    retries; focused MinIO `mc` vulnerability remediation is implemented for
    the documented Docker Hub Layer 40 findings. Build verification passed, and
    Docker Scout / Docker Hub evidence confirms the documented
    `runtime-jre25-gpu` finding set is resolved. See
    [`docs/minio-mc-remediation-boundary.md`](minio-mc-remediation-boundary.md)
    for build reliability and vulnerability remediation boundaries, and
    [`docs/minio-mc-remediation-verification.md`](minio-mc-remediation-verification.md)
    for the post-remediation verification pass.
  - Risk: behavior-changing / remediation.
  - Suggested PR boundary: `scripts/lib/s3_client.sh` and packaging/docs if
    needed.
  - Do not remove MinIO support.
  - Do not change alias names or endpoint behavior casually.
  - Suggested checks: source smoke plus S3-free or mocked client smoke.
  - Remaining optional acquisition strategy changes or client replacement are
    feature/build-policy work, not mechanical cleanup.

### 6. Feature work, not cleanup

- Spigot BuildTools / self-build support is feature work, not backlog cleanup.
  - Risk: behavior-changing.
  - Suggested PR boundary: separate design/behavior PR, not this cleanup
    backlog.
  - Do not combine with unrelated refactors or hardening.

## Optional future boundaries, not cleanup backlog

- `entrypoint.sh` still owns process-global initialization for `SERVER_PID` and
  `RCON_STOP_*` state. A future boundary can decide whether any of that should
  move, but it is not cleanup work by default.
- Signal trap registration should remain in `entrypoint.sh` unless a dedicated
  shutdown boundary changes it.
- Command-mode selection should remain in `entrypoint.sh` unless a dedicated
  CLI boundary changes it.
- Keep Velocity shutdown's RCON-skip behavior unchanged unless a dedicated
  shutdown behavior PR intentionally revisits it.

## logging.sh

- Review `die` argument handling.
- Consider whether `die` should support multiple arguments safely, for example
  `die "$@"` or explicit message handling.
- Preserve current log format semantics unless intentionally changed.

## s3_client.sh

- Harden temporary-file cleanup in `ensure_s3_source_nonempty_for_remove`.
- Prefer safer temp handling and/or `trap` where appropriate.
- Keep S3 environment variable names unchanged.
- Keep the MinIO alias name `s3` unchanged.
- Preserve existing behavior unless intentionally changed in a dedicated
  hardening PR.
- Design boundary: `docs/s3-client-cleanup-boundary.md`.
- MinIO `mc` remediation boundary:
  [`docs/minio-mc-remediation-boundary.md`](minio-mc-remediation-boundary.md).
- Build reliability hardening is completed for bounded source clone retries.
- Vulnerability remediation investigation plan:
  [`docs/minio-mc-vulnerability-remediation-plan.md`](minio-mc-vulnerability-remediation-plan.md).
- Vulnerability findings pass:
  [`docs/minio-mc-vulnerability-findings.md`](minio-mc-vulnerability-findings.md).
- Focused MinIO `mc` vulnerability remediation is implemented for the
  documented Docker Hub Layer 40 findings. Build verification passed, and
  Docker Scout / Docker Hub evidence confirms the documented
  `runtime-jre25-gpu` finding set is resolved. Post-remediation verification:
  [`docs/minio-mc-remediation-verification.md`](minio-mc-remediation-verification.md).
- Keep future vulnerability remediation, acquisition strategy changes, and
  optional client replacement as separate work.

## world_install.sh

- Design boundary: [`docs/world-install-cleanup-boundary.md`](world-install-cleanup-boundary.md).
- Keep temp archive cleanup, unzip error handling, extracted-world detection,
  and path-safety hardening in separate PRs.
- Unzip error-message cleanup is completed with an explicit extract failure.
- Fixed archive temp path cleanup is completed for `/tmp/world.zip`.
- Extracted-world detection behavior is completed with deterministic temporary
  extraction, supported direct/single-root/flat layouts, and rejection for
  ambiguous or missing `level.dat` layouts.
- Harden `DATA_DIR` / `WORLD_DIR` path safety before `rm -rf`.
  - Status: completed for `world_install.sh`. See
    [`docs/world-install-path-safety.md`](world-install-path-safety.md).
- Extracted world directory detection no longer uses broad matching such as
  `find "${DATA_DIR}" -maxdepth 1 -type d -name "*world*" | head -n1`.
  - Status: completed. See
    [`docs/world-install-extraction-detection.md`](world-install-extraction-detection.md).
- Keep `world_reset.sh` cleanup separate from `world_install.sh` cleanup.
  - Path-safety design boundary:
    [`docs/world-reset-path-safety.md`](world-reset-path-safety.md).

## server_properties.sh

- Review `TYPE` access under `set -u`.
- Make `TYPE` handling consistently safe where practical.
- Preserve bootstrap behavior and log semantics unless intentionally changed.
- Status: completed for the focused `TYPE`/`set -u` safety pass.

## runtime.sh

- Marker temp-file cleanup design boundary:
  [`docs/runtime-marker-cleanup-boundary.md`](runtime-marker-cleanup-boundary.md).
- Marker temp-file cleanup is completed for `write_server_install_marker`.
- Corrupt marker JSON handling design boundary:
  [`docs/runtime-marker-corrupt-json-boundary.md`](runtime-marker-corrupt-json-boundary.md).
  Status: completed for corrupt and incomplete marker fail-fast handling.
- Spigot marker auto-resolution design boundary:
  [`docs/runtime-spigot-marker-boundary.md`](runtime-spigot-marker-boundary.md).
  Status: design-ready, not implemented.
- Review the inconsistency where `is_supported_runtime_type` includes `spigot`,
  while the `resolve_type_auto` marker-supported type list did not include
  `spigot` in the original moved code.
- Decide in a dedicated behavior PR whether Spigot marker resolution should be
  supported.
- Invalid or corrupt marker JSON handling is completed for:
  - `assert_server_install_matches`
  - `resolve_type_auto`
- Preserve marker path and JSON format unless intentionally changed.

## world_reset.sh

- Path-safety design boundary:
  [`docs/world-reset-path-safety.md`](world-reset-path-safety.md).
- Status: path-safety and obvious function-local variable localization
  completed. Keep other reset cleanup separate from reset timing changes and
  unrelated reset behavior changes.
- Localize variables in `reset_world` / `handle_reset_world_flag`, including:
  - Status: completed for obvious function-local reset variables.
  - `FLAG_FILE`
  - `WORLD_DIR`
  - `MODS_DIR`
  - `MAX_AGE`
  - `FLAG`
  - `NOW`
  - `MTIME`
  - `TS`
  - `BACKUP_DIR`
  - `BACKUP_ARCHIVE`
- Harden `DATA_DIR` / `WORLD_DIR` safety checks.
  - Status: completed for reset path-safety.
- Guard against empty or unset `DATA_DIR`.
  - Status: completed for reset path-safety.
- Add path sanity checks before `rm -rf`.
  - Status: completed for reset path-safety.
- Duplicated successful-path reset flag removal remains unresolved and should
  stay in a dedicated behavior PR because it can affect fresh reset failure
  behavior.
- Backup/temp/atomic handling remains unresolved and should stay in a dedicated
  destructive-path-adjacent PR.
- Preserve existing reset behavior until a dedicated non-mechanical improvement
  PR.

## Recommended next PR candidates

Prefer docs-only boundaries before implementation for any remaining
behavior-sensitive item:

1. Spigot marker support / `resolve_type_auto` behavior boundary.
2. `world_reset.sh` duplicated reset flag removal boundary.
3. Stop cleanup and move to feature work only after an explicit maintainer
   choice.

## Guardrails

- These items were intentionally deferred during mechanical boundary extraction.
- Each item may change behavior or error handling.
- One cleanup topic per PR.
- Handle each cleanup area in a dedicated PR with focused smoke tests.
- Do not mix these fixes into future mechanical moves.
- Do not combine vulnerability remediation with unrelated refactors.
- Do not change generated config output without golden/key-line smoke.
- Do not change shutdown semantics without mocked shutdown tests.
- Do not change S3/MinIO behavior without S3-free smoke or mocked tests.
- Do not change `rm -rf` paths without strict safety checks.
- Keep marker paths, marker JSON format, S3 environment variable names, MinIO
  alias names, install order, and world-reset behavior unchanged unless the PR
  explicitly targets that behavior.
