# Repository Guidelines

## Project Structure & Module Organization
`entrypoint.sh` is the orchestration layer for container startup. Shared shell logic lives in `scripts/lib/` and is split by responsibility: `logging.sh`, `runtime.sh`, `s3_client.sh`, `world_install.sh`, and `server_properties.sh`. Documentation and refactor notes live in `docs/`. Example Kubernetes and Docker manifests live in `examples/`. Smoke-test manifests live in `test/k8s/`.

## Build, Test, and Development Commands
- `docker build --target runtime-jre21 -t minecraft-server:test-jre21 .` builds the runtime image used by smoke tests.
- `docker run --rm --entrypoint bash minecraft-server:test-jre21 -n /entrypoint.sh` checks shell syntax inside the image.
- `bash -n entrypoint.sh scripts/lib/*.sh` validates shell syntax locally.
- `shellcheck -x -s bash entrypoint.sh scripts/lib/*.sh` runs static analysis when ShellCheck is installed.

## Coding Style & Naming Conventions
Use Bash-compatible syntax with `set -Eeuo pipefail` in mind. Keep files ASCII-only unless the file already uses Unicode. Prefer short, direct function names in `lower_snake_case`, and keep environment variable names uppercase. Preserve existing log messages and shell helper boundaries when changing code.

## Testing Guidelines
This repo relies on smoke tests rather than a large unit-test suite. Keep changes covered by `bash -n`, ShellCheck, and the GitHub Actions workflows in `.github/workflows/`. When adding shell helpers, make sure they can be sourced cleanly and that any new behavior can be exercised with a small temp-directory smoke test instead of a real Minecraft server boot.

## Commit & Pull Request Guidelines
Recent history uses concise, imperative commit subjects such as `refactor: move runtime auto resolution helper` and `fix: validate UUID cache before player list generation`. Keep commits scoped to one boundary. PRs should explain what moved, what stayed in `entrypoint.sh`, and which checks were run. Link related issues or follow-on refactor steps when relevant.

## Agent Instructions
Prefer mechanical refactors over broad rewrites. Do not change install order, marker formats, runtime dispatch, or world-reset behavior unless the task explicitly calls for it.
