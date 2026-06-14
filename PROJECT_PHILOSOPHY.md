# Project Philosophy

This repository provides a Minecraft server Docker image designed primarily for reliable self-hosted and Kubernetes-based operation.

## Core principles

- Kubernetes-first, but not Kubernetes-only.
- Prefer declarative, GitOps-friendly configuration.
- Preserve existing Docker image behavior unless a breaking change is explicitly justified.
- Prefer small, reviewable changes over large rewrites.
- Prefer fail-fast behavior over silent partial failure.
- Avoid unsafe file operations, especially around worlds, volumes, and mounted data.
- Never introduce logic that can accidentally delete or overwrite Minecraft worlds.
- Treat `/data` and mounted volumes as user-owned persistent state.
- Shutdown must remain graceful and Minecraft-aware.
- Prefer RCON/server stop flows over hard process killing when possible.
- Do not assume Bash-only user workflows. The maintainer uses fish shell.
- Avoid heredoc-based instructions in user-facing command examples.
- Avoid AGPL dependencies unless explicitly isolated and justified.
- Prefer AWS CLI compatible S3 behavior for object storage operations.
- Keep MinIO Client out unless there is a strong reason to reintroduce it.
- Do not optimize for Docker Compose at the cost of Kubernetes reliability.
- Documentation should describe real operational behavior, not idealized behavior.

## Minecraft-specific expectations

- Server startup, shutdown, world install, backup, restore, and S3 sync are high-risk areas.
- Changes touching world data, resource packs, server.properties, EULA handling, RCON, or S3 sync require extra caution.
- Any change that affects existing environment variables must preserve compatibility or clearly document migration steps.
- Do not introduce hidden behavior that surprises server operators.
- Prefer explicit environment variables and clear logs.

## Nightly AI triage policy

The AI may:
- read files;
- inspect docs, scripts, Dockerfiles, workflows, and recent git history;
- identify bug risks, missing tests, missing docs, and design inconsistencies;
- produce Markdown research memos;
- draft GitHub Issue candidates.

The AI must not:
- edit source code;
- commit;
- push;
- create GitHub issues;
- create pull requests;
- run deploy commands;
- run destructive commands;
- run Docker image publishing;
- run Kubernetes commands;
- modify persistent data.

The maintainer makes all final decisions.
