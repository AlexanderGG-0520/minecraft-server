# s3_client.sh temporary-file cleanup boundary

This note defines the boundary for the completed behavior-preserving cleanup of
temporary-file handling in `scripts/lib/s3_client.sh`, especially
`ensure_s3_source_nonempty_for_remove`.

This note was added before the implementation PR and documents the behavior
boundary for that cleanup.

Implementation status: completed for the focused
`ensure_s3_source_nonempty_for_remove` temporary-file cleanup pass.

## Current behavior to preserve

`s3_client.sh` currently owns the shared MinIO client helpers used by S3-backed
sync flows.

- `MC_CONFIG_DIR` defaults to `/tmp/mc-config` and is exported.
- `require_s3_env` fails fast unless these variables are set:
  - `S3_ENDPOINT`
  - `S3_ACCESS_KEY`
  - `S3_SECRET_KEY`
- `configure_mc_alias` creates `MC_CONFIG_DIR` and runs:
  - `mc alias set s3 "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}"`
- The MinIO alias name is `s3`.
- `ensure_s3_source_nonempty_for_remove` receives a source path and feature
  name, writes `mc find "$src" --print "{}"` output to a temporary file, and
  fails before `mc mirror --remove` if listing fails or the source is empty.
- The helper currently removes its temporary file on the explicit success and
  failure branches.

Future cleanup must preserve:

- S3/MinIO support as a first-class project assumption.
- Existing S3 environment variable names.
- Existing MinIO alias name: `s3`.
- Existing `mc` command semantics and source path shape.
- Existing fail-fast behavior before remove sync.
- Existing log and error message meaning unless a dedicated PR intentionally
  changes that behavior.
- Existing callers from mods, configs, datapacks, resourcepacks, and any future
  S3-backed helpers.
- CI smoke tests should not contact real S3 or MinIO unless a dedicated test
  environment explicitly provides mocked or disposable endpoints.

## Implementation boundary

A future implementation PR may:

- Keep the cleanup scoped to `scripts/lib/s3_client.sh`.
- Use `mktemp` for temporary file creation.
- Add a local cleanup trap or a carefully scoped cleanup helper.
- Ensure temporary files are removed on success, listing failure, empty-source
  failure, and unexpected function exit.
- Avoid leaking temporary files if `mc`, shell redirection, or validation
  commands fail.
- Keep cleanup local to `ensure_s3_source_nonempty_for_remove` where possible.

A future implementation PR must not:

- Rename S3 environment variables.
- Rename the MinIO alias from `s3`.
- Replace `mc` with another tool.
- Remove MinIO support.
- Change bucket, prefix, or key semantics.
- Change remove-extra safety behavior.
- Change world install/reset behavior.
- Change install, runtime launch, shutdown, RCON, or server artifact behavior.
- Combine with MinIO or `mc` dependency/vulnerability remediation.
- Combine with world path-safety or `rm -rf` cleanup.

## Staged plan

1. Docs-only temp cleanup boundary.
   This PR.

2. Behavior-preserving temp-file cleanup in `s3_client.sh` only.
   Use `mktemp`, scoped cleanup, unchanged command semantics, and mocked smoke
   coverage where practical.

3. Separate MinIO or `mc` dependency/vulnerability remediation PR.
   Keep MinIO support and avoid unrelated refactors.

4. Separate world install/reset path-safety PRs.
   Do not mix destructive path hardening with S3 temp cleanup.

## Smoke guidance

Future implementation smoke tests should:

- Source `scripts/lib/s3_client.sh` under `set -euo pipefail`.
- Mock `mc` in `PATH` to avoid real S3 or MinIO network calls.
- Use temporary directories for mock state and temp-file assertions.
- Verify temp files are cleaned up after successful listing.
- Verify temp files are cleaned up after `mc find` failure.
- Verify temp files are cleaned up after an empty-source failure.
- Verify the alias name `s3` and existing S3 env var names remain in use.
- Avoid real S3 credentials.
- Avoid contacting real MinIO or S3 endpoints.
- Avoid destructive world reset or world install paths.
