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
- User-provided Docker Scout / Docker Hub post-remediation evidence for last
  pushed tag `runtime-jre25-gpu`.

Post-remediation Docker Scout / Docker Hub evidence is now available for the
last pushed `runtime-jre25-gpu` tag. The pre-remediation Docker Hub scanner
evidence remains recorded in
[`docs/minio-mc-vulnerability-findings.md`](minio-mc-vulnerability-findings.md)
for history.

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
| Docker Hub scanner re-evaluation | Resolved / confirmed | User-provided Docker Scout / Docker Hub evidence for last pushed tag `runtime-jre25-gpu` showed health score `A`, no high-profile vulnerabilities, no fixable critical or high vulnerabilities, no unapproved base images, supply chain attestations present, no outdated base images, no AGPL v3 licenses, and default non-root user. |

Build verification passed. Docker Hub scanner re-evaluation confirms the
documented Layer 40 findings are resolved for the post-remediation
`runtime-jre25-gpu` image.

## Docker Scout Evidence

User-provided Docker Scout / Docker Hub post-remediation evidence for last
pushed tag `runtime-jre25-gpu` recorded:

- Health score: `A`
- No high-profile vulnerabilities
- No fixable critical or high vulnerabilities
- No unapproved base images
- Supply chain attestations present
- No outdated base images
- No AGPL v3 licenses
- Default non-root user

## Scanner Resolution

The user-provided Docker Scout / Docker Hub evidence resolves the documented
Docker Hub Layer 40 high vulnerability finding set for `runtime-jre25-gpu`.
The evidence applies to the post-remediation last pushed
`runtime-jre25-gpu` tag and does not make any claim about future scanner
results, future base images, future Go vulnerabilities, or unrelated images.

## Future Action

If a future scanner run reports findings, collect the exact CVE,
package/component, path or layer, current version, fixed version, severity,
image tag, image digest, and scanner evaluation time before starting any
further remediation.
