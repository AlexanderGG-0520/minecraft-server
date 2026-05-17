# MinIO mc remediation verification

This document records the post-remediation verification pass for the focused
MinIO `mc` vulnerability remediation merged in PR #111.

This pass is documentation-only. It does not change runtime behavior, build
behavior, `MC_RELEASE`, `GO_VERSION`, Go module overrides, `mc` acquisition
strategy, S3/MinIO behavior, S3 environment variable names, or alias `s3`.

## Remediation Implemented

PR #111 implemented only the focused `mc-builder` input changes needed for the
documented Docker Hub Layer 40 findings:

- `GO_VERSION`: `1.25.9` -> `1.25.10`.
- Added targeted override: `golang.org/x/net@v0.53.0`.
- Added targeted override: `github.com/prometheus/prometheus@v0.311.3`.
- `MC_RELEASE` remained `RELEASE.2025-08-13T08-35-41Z`.
- Existing `mc` source clone acquisition strategy remained unchanged.
- S3/MinIO runtime behavior remained unchanged.

## Evidence Sources Inspected

- Local `main` after `git fetch origin` and `git pull --ff-only`.
- Local merge commit: `bd82f6aa06da476cc1b41d65ce6eea82533fb52e`
  (`Remediate MinIO mc vulnerability inputs (#111)`).
- `gh pr view 111 --json ...`.
- `gh run list --branch main --limit 12 --json ...`.
- `gh run list --branch fix/minio-mc-vulnerability-remediation --limit 12 --json ...`.
- `gh run view 25953580019 --json ...`.
- `gh run view 25953580020 --json ...` and targeted runtime smoke job log
  search for run `25953580020`, job `76295838638`.
- `gh run view 25953580034 --json ...` and targeted publish job log searches
  for run `25953580034`, jobs `76295838593` and `76295838594`.
- `docker buildx imagetools inspect alecjp02/minecraft-server:runtime-jre25-gpu`.
- `docker buildx imagetools inspect alecjp02/minecraft-server:runtime-jre25`.

No post-remediation Docker Hub vulnerability scanner output was available in
this pass. The pre-remediation Docker Hub scanner evidence remains recorded in
[`docs/minio-mc-vulnerability-findings.md`](minio-mc-vulnerability-findings.md).

## Verification Status

| Area | Status | Evidence |
| --- | --- | --- |
| Local sync | Passed | `main` fast-forwarded to merge commit `bd82f6aa06da476cc1b41d65ce6eea82533fb52e`, confirming PR #111 is included locally. |
| PR checks | Passed | PR #111 status rollup showed successful `Bash syntax and ShellCheck` and `Runtime behavior regression` checks before merge. |
| Main static checks | Passed | Main push run `25953580019`, job `76295838637`, completed successfully for `Lint and Static Smoke`, including Bash syntax, ShellCheck, source library smoke, S3 client temp cleanup smoke, and related helper smokes. |
| Main CI build | Passed | Main push run `25953580020` completed successfully for `Runtime Smoke CI`; the `Build runtime image` step built `runtime-jre21` and produced `minecraft-server:test-jre21`. |
| Runtime smoke | Passed | Main push run `25953580020`, job `76295838638`, completed successfully with runtime behavior regression smoke steps, including entrypoint syntax, sourced libraries, Modrinth local install, install-only vanilla, RCON rejection, TYPE auto marker resolution, Spigot BYO artifact, marker mismatch rejection, and corrupted UUID cache rejection. |
| Publish | Passed | Main push run `25953580034` completed successfully for all publish matrix targets, including `runtime-jre25-gpu`. |
| `mc --version` | Passed for GPU build log visibility | Publish job `76295838593` ran `chmod +x /usr/local/bin/mc && mc --version` and logged `mc version DEVELOPMENT.GOGET (commit-id=DEVELOPMENT.GOGET)`. |
| Docker Hub published image | Available | `docker.io/alecjp02/minecraft-server:runtime-jre25-gpu` resolves to index digest `sha256:42350a90b444f66566dbd6334b68c403793dbe63e87c64f2d65dbc8fa2c6f8b1`; linux/amd64 manifest digest `sha256:f480be3b121b198ce15849989087cda6fd8bdd53c32f792017b76760ca0b9703`. |
| Related non-GPU published image | Available | `docker.io/alecjp02/minecraft-server:runtime-jre25` resolves to index digest `sha256:998c2e5defaa3388e855c165d0b4fb747c99539ffce8e1576fde4ddc682f0ec3`; linux/amd64 manifest digest `sha256:e3d81b91cc4aceae4aaafef55cd874054919700ac4be697e8ed892ef181a4581`. |
| Docker Hub scanner re-evaluation | Pending / unavailable | No post-remediation Docker Hub scanner evidence was available in this pass. Do not mark the documented Layer 40 findings resolved until scanner output is provided or inspected. |

Build verification passed; scanner re-evaluation pending.

## Remaining Unknowns

- Whether Docker Hub has rescanned
  `alecjp02/minecraft-server:runtime-jre25-gpu@sha256:42350a90b444f66566dbd6334b68c403793dbe63e87c64f2d65dbc8fa2c6f8b1`.
- Whether Docker Hub scanner re-evaluation confirms the documented Layer 40
  findings are resolved.
- Whether any scanner findings remain for the same CVE/package/path/current
  version/fixed version set after the post-PR #111 image publish.

## Remaining Action

If scanner re-evaluation is pending, wait for Docker Hub to rescan the updated
image or provide updated Docker Hub scanner screenshot/output for the published
post-remediation digest.

If the scanner still reports findings, collect the exact CVE, package/component,
path or layer, current version, fixed version, severity, image tag, image digest,
and scanner evaluation time before starting any further remediation.
