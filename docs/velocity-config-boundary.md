# Velocity config generation boundary

This document defines the responsibility boundary for Velocity proxy
configuration generation and the implemented user-managed config ownership
policy.

The original boundary was a design plan. The current implementation preserves
call timing, generated fallback `velocity.toml` content, server artifact
installation, and runtime launch behavior while treating existing user-managed
Velocity config files as authoritative.

## Implemented boundary

Recommended file: `scripts/lib/velocity_config.sh`

Status: completed for the mechanical function move and the user-managed config
ownership behavior.
`generate_velocity_toml` now lives in `scripts/lib/velocity_config.sh`. The
existing call from `install_velocity_server_artifact` and the later call from
`install()` remain in place with unchanged timing.

Use `scripts/lib/velocity_config.sh` while Velocity TOML is the only
proxy-specific configuration generator in the project. The narrower name makes
the current ownership explicit and avoids implying a broader proxy framework
before one exists.

Use `scripts/lib/proxy_config.sh` only if the project is expected to add
multiple proxy configuration generators soon. That broader name should own
shared proxy configuration policy, not just the current Velocity implementation
renamed in advance.

The future library should answer:

- How is `velocity.toml` generated for `TYPE=velocity`?
- Which Velocity config defaults are applied?
- How are Velocity bind, forwarding, secret, server list, try list, and forced
  host settings written?
- What Velocity-specific config validation exists before writing the file?

`entrypoint.sh` should continue to answer:

- When configuration generation runs in the boot sequence.
- When server artifact installation, world reset, world install,
  `server.properties`, and runtime launch happen.
- When install-only mode exits.

## Current state

`generate_velocity_toml` is currently implemented in
`scripts/lib/velocity_config.sh`.

Current call sites:

- `scripts/lib/server_install.sh`
  - `install_velocity_server_artifact` verifies that `generate_velocity_toml`
    exists and calls it before resolving or downloading `velocity.jar`.
  - This means Velocity config generation currently happens during Velocity
    artifact installation.
- `entrypoint.sh`
  - The main `install()` sequence calls `generate_velocity_toml` again after
    `configure_paper_configs` and before `ensure_server_properties`.
  - This means Velocity config generation also happens later in the install
    sequence.

Do not clean up this double call casually. The current timing may affect
first-boot behavior, restart behavior, and config generation semantics. The
current behavior is idempotent for user-managed configs because existing
`velocity.toml` is left unchanged. This call timing is intentionally preserved
and is not an active post-split cleanup backlog item.

## Config ownership policy

User-managed Velocity config files are authoritative.

- If `${DATA_DIR}/velocity.toml` already exists, the entrypoint does not
  rewrite, patch, chmod, or chown it.
- If `${DATA_DIR}/forwarding.secret` already exists, the Velocity config flow
  does not rewrite, chmod, or chown it. The current fallback generator does not
  create or require this file; generated fallback TOML keeps the existing
  inline `forwarding-secret` setting.
- Existing read-only `velocity.toml` and `forwarding.secret` files are accepted
  as user-managed files.
- If `velocity.toml` is missing for `TYPE=velocity`, the entrypoint generates
  the fallback file only when `${DATA_DIR}` is writable.
- Ownership and permission changes are limited to fallback files created by the
  entrypoint flow.
- If the fallback file cannot be generated, startup fails fast with a clear
  `Failed to generate velocity.toml fallback` error.

## What should move

`scripts/lib/velocity_config.sh` owns:

- `generate_velocity_toml`.
- Velocity TOML generation.
- Velocity config defaults.
- Velocity bind, forwarding, secret, and config file generation behavior.
- Velocity-specific config validation if added later.

## What should not move

`scripts/lib/velocity_config.sh` should not own:

- Velocity jar download.
- Server artifact installation.
- `install_server` dispatch.
- `run_server`.
- Runtime launch dispatch.
- `TYPE=auto` resolution.
- Runtime marker helpers.
- World install or world reset.
- `server.properties` bootstrap.
- S3/MinIO setup.
- Plugin, mod, config, datapack, or resourcepack installation.
- RCON, shutdown, or lifecycle handling.

## Current coupling

Velocity config generation is currently adjacent to Velocity artifact
installation. The Velocity artifact helper calls `generate_velocity_toml`
mechanically because that call was part of the original Velocity branch before
artifact installation moved into `scripts/lib/server_install.sh`.

The later install-sequence call remains in place. This preserves the current
startup timing while the user-managed ownership policy prevents existing
ConfigMap/Secret-style files from being rewritten or chmod/chowned.

Any future call-timing redesign should be treated as behavior work. In
particular, it must:

- Preserve the call from `install_velocity_server_artifact` if it still exists
  during the mechanical move.
- Preserve the later call from `install()` during the mechanical move.
- Preserve generated `velocity.toml` content and log messages.
- Do not combine config ownership cleanup with artifact download, runtime
  launch, world, S3, or `server.properties` behavior changes.

## Staged migration order

Recommended implementation PRs:

1. Add this docs-only boundary plan.
   - Status: completed.
2. Mechanically move Velocity config generation.
   - Create `scripts/lib/velocity_config.sh`.
   - Move `generate_velocity_toml` mechanically.
   - Source it before `scripts/lib/server_install.sh` if
     `server_install.sh` still calls `generate_velocity_toml`.
   - Preserve all current call sites and call timing.
   - Preserve generated `velocity.toml` content.
   - Status: completed for the mechanical function move.
3. Implement user-managed config ownership.
   - Existing `velocity.toml` and `forwarding.secret` files are authoritative.
   - Ownership and permission changes are limited to fallback files created by
     the entrypoint flow.
   - Preserve existing call timing and generated fallback content.
   - Status: completed.
4. Optionally redesign call timing later.
   - This is future behavior work, not active cleanup backlog.
   - Add focused smoke tests before changing behavior.
5. Only after the Velocity config boundary is stable, consider runtime launch
   dispatch or `run_server` boundaries.

## Risk notes

Specific risks to avoid during extraction:

- Changing config regeneration timing.
- Changing first-boot behavior.
- Changing restart behavior.
- Changing generated `velocity.toml` content.
- Changing Velocity forwarding secret behavior.
- Accidentally mixing artifact installation with config generation.
- Accidentally moving runtime launch behavior.

## Test and smoke guidance

For future implementation PRs that create or populate
`scripts/lib/velocity_config.sh`, use focused checks:

- Run `bash -n entrypoint.sh scripts/lib/*.sh`.
- Run `shellcheck -x -s bash entrypoint.sh scripts/lib/*.sh` when ShellCheck is
  installed.
- Add or run a source smoke test for `scripts/lib/velocity_config.sh`.
- Prefer a temp-directory smoke test for generated `velocity.toml` if practical.
- Check exact generated content or key lines such as bind address, forwarding
  mode, forwarding secret, server entries, try list, and forced hosts.
- Do not require a real server boot.
- Do not make network calls.
- Do not require S3 credentials.
- Do not trigger destructive world reset behavior.
- Preserve existing config generation output unless a dedicated behavior PR
  changes it.

## Guardrails

- Keep the first implementation PR mechanical.
- Do not change `generate_velocity_toml` behavior while moving it.
- Do not change `generate_velocity_toml` call timing while moving it.
- Do not change Velocity artifact installation while moving config generation.
- Do not move `run_server` or runtime dispatch in the same PR.
