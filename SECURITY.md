# Security Policy

## Supported versions

Security fixes are handled for the current `main` branch and for the currently published images built
from that branch.

Older image tags may continue to exist for reproducibility, but they are not treated as long-term
supported releases unless a support window is explicitly documented in the future.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability.

Report security-sensitive findings through GitHub's private vulnerability reporting for this repository,
if available. If private reporting is not available, contact the repository owner through a private
channel and include enough detail to reproduce or assess the issue.

Useful details include:

* Affected image tag or commit.
* Deployment context, such as Kubernetes, Docker Compose, or local Docker.
* Relevant environment variables with secrets redacted.
* Expected behavior and observed behavior.
* Minimal reproduction steps, manifests, or logs when safe to share.

## Security-sensitive areas

The following areas are considered security-sensitive for this project:

* Unsafe deletion or mutation of persistent world data.
* Credential leakage from S3/MinIO configuration or client state.
* RCON password handling, validation, logging, and shutdown behavior.
* Container privilege, filesystem ownership, and mounted volume permission issues.
* Unsafe lifecycle hook behavior, especially hooks that run before install or runtime launch.
* Unsafe downloaded artifact handling, including server jars, modpacks, archives, and extracted files.

## Scope

This image orchestrates Minecraft server installation, asset sync, lifecycle handling, and runtime
startup. Minecraft server software, mods, plugins, modpacks, Java runtimes, base images, and external
services may have their own vulnerabilities outside this image's direct maintenance scope.

Reports are still useful when a third-party vulnerability interacts with this image's install, sync,
lifecycle, filesystem, or runtime behavior.
