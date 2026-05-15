# MinIO mc remediation boundary

This note defines the boundary for future MinIO `mc` dependency remediation,
vulnerability remediation, and build reliability hardening.

This note records the remediation boundary for MinIO `mc` build and dependency
work.

Implementation status: build reliability hardening completed for bounded
`git clone` retries. Vulnerability remediation, acquisition strategy changes,
and optional client replacement remain separate.

## Current Behavior To Preserve

MinIO/S3 support is a first-class project assumption. The image currently uses
the MinIO `mc` client for S3-compatible operations used by mods, plugins,
configs, datapacks, resourcepacks, optimization helpers, and world archives.

Current build behavior:

- `Dockerfile` has an `mc-builder` stage.
- `MC_RELEASE` defaults to `RELEASE.2025-08-13T08-35-41Z`.
- `GO_VERSION` defaults to `1.25.9`.
- The builder installs `git` and `ca-certificates`.
- The builder fetches source with a bounded retry loop around:
  - `git clone --depth 1 --branch ${MC_RELEASE} https://github.com/minio/mc.git .`
- The builder applies current dependency updates with `go get`, runs
  `go mod tidy`, and builds a static binary with:
  - `CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/mc .`
- Runtime images copy `/out/mc` to `/usr/local/bin/mc`.
- The GPU runtime stage also runs `mc --version` during build.

Current S3 helper behavior:

- `MC_CONFIG_DIR` defaults to `/tmp/mc-config` and is exported.
- S3 environment variable names are:
  - `S3_ENDPOINT`
  - `S3_ACCESS_KEY`
  - `S3_SECRET_KEY`
- `configure_mc_alias` requires those variables, creates `MC_CONFIG_DIR`, and
  runs:
  - `mc alias set s3 "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}"`
- The MinIO alias name is `s3`.
- `ensure_s3_source_nonempty_for_remove` uses:
  - `mc find "$src" --print "{}"`
- Other S3-backed flows use existing `mc cp`, `mc find`, and `mc mirror`
  command semantics.
- `*_REMOVE_EXTRA=true` flows rely on the existing preflight check before
  `mc mirror --remove`.

Future remediation must preserve:

- MinIO/S3 support.
- Existing S3 environment variable names.
- The alias name `s3`.
- Existing bucket, key, and prefix semantics.
- Existing `mc` command behavior expected by callers.
- Existing remove-extra safety behavior.
- World install/reset behavior.
- Server artifact installation behavior.
- Runtime launch behavior.
- Compatibility for users who already configure the image with S3-backed
  assets.

## Current Risks

- Docker builds currently depend on a build-time external GitHub clone of
  `github.com/minio/mc.git`; transient network, GitHub, or repository access
  failures can break otherwise unrelated builds.
- Upstream repository state, release tags, or archive availability may affect
  future maintenance.
- Pinned `mc` versions can retain dependency vulnerabilities.
- Updating `mc`, Go, or transitive build inputs can affect reproducibility and
  should be recorded deliberately.
- Tracking latest blindly can reduce reproducibility and make CI failures hard
  to diagnose.
- Switching away from `mc` can alter S3-compatible behavior, alias/config
  behavior, mirror/remove semantics, and edge-case compatibility.
- Vulnerability remediation should not be mixed with unrelated refactors,
  world path-safety work, runtime launch changes, or server artifact changes.

## Staged Remediation Plan

### A. Docs-only remediation boundary

This PR. It records the behavior and build boundaries before implementation.

### B. Build reliability hardening

A future PR may:

- Reduce fragility of fetching `mc` during Docker build.
- Consider pinned release artifacts, checksum verification, source archive
  downloads, or another more reliable acquisition path.
- Preserve reproducibility by pinning versions and checksums.
- Keep `/usr/local/bin/mc` available in all runtime targets.
- Preserve runtime S3 semantics.

This PR should not change `mc` command behavior or S3 helper behavior.

Status: completed for bounded retry around the existing pinned source clone.

### C. Vulnerability remediation

A separate PR may:

- Update `MC_RELEASE`, `GO_VERSION`, or selected Go module overrides.
- Record the version, reason, and vulnerability remediation rationale.
- Keep command behavior compatible.
- Keep or add smoke coverage for build-time availability and library behavior.

### D. Acquisition strategy decision

A separate design or implementation PR may compare:

- Building `mc` from source.
- Downloading a pinned release artifact.
- Using a pinned binary with checksum verification.
- Mirroring artifacts through a controlled supply-chain path.

This is a build policy decision. Include supply-chain, checksum,
reproducibility, architecture, and maintenance tradeoffs.

### E. Optional client replacement

Replacing `mc` with another client must be a separate design and behavior PR.
Do not remove `mc` casually. Require a compatibility matrix and migration plan
covering alias/config setup, copy, find, mirror, remove-extra, retry behavior,
exit codes, and S3-compatible endpoint support.

## Guardrails

Future implementation must not casually:

- Remove MinIO support.
- Rename S3 environment variables.
- Rename the alias `s3`.
- Change `mc` command semantics.
- Change bucket, key, or prefix semantics.
- Change remove-extra safety behavior.
- Change world install/reset behavior.
- Change server artifact installation.
- Change runtime launch behavior.
- Combine `mc` remediation with world path-safety cleanup.
- Combine `mc` remediation with entrypoint refactors.
- Switch to latest without a reproducibility discussion.
- Switch clients without compatibility tests.

## Smoke Guidance

Future implementation smoke tests should:

- Build at least one runtime image and verify `/usr/local/bin/mc` exists.
- Run `mc --version` in the built image.
- Keep library smoke tests mocked where network is not needed.
- Mock `mc alias set` for `configure_mc_alias` when testing without S3.
- Keep mocked coverage for `ensure_s3_source_nonempty_for_remove`.
- Avoid real S3 credentials unless using a dedicated disposable endpoint.
- Avoid production MinIO/S3 endpoints.
- Avoid destructive world reset tests.
- Avoid coupling `mc` remediation tests to unrelated server artifact downloads.
