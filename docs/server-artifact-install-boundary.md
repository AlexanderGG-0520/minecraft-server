# Server artifact install boundary

This document defines the next proposed `entrypoint.sh` responsibility boundary:
server artifact installation.

It is a design plan only. Do not move functions, change install order, change
marker behavior, or change runtime launch behavior as part of this document.

## Proposed boundary

Suggested future file: `scripts/lib/server_install.sh`

Status: started. `scripts/lib/server_install.sh` now owns only the pure atomic
server artifact download helpers. Runtime-specific server artifact installation
still remains in `entrypoint.sh`.

The future library should answer:

- How do we install or validate the server artifact for the selected runtime
  type?
- How do we download, build, or prepare runtime-specific server artifacts?
- How do we record installed artifacts by calling the existing runtime marker
  helpers?

`entrypoint.sh` should continue to answer:

- When does server artifact installation happen in the boot sequence?
- When do preflight, world reset, world install, `server.properties`, and server
  launch happen?
- When does install-only mode exit?

The extraction should be mechanical. Preserve the current public contract:
environment variables, downloaded filenames, marker files, marker JSON format,
log messages, and first-boot versus restart behavior.

## Current inventory

The runtime-specific server artifact installation implementation is still in
`entrypoint.sh`. Pure server artifact download helpers now live in
`scripts/lib/server_install.sh`.

Likely server artifact install responsibilities currently found:

- `download_file_atomic`
  - Shared atomic download helper used by server artifact installers.
  - Implemented in `scripts/lib/server_install.sh`.
  - Current server-artifact call sites: Quilt, Paper, Purpur, Mohist,
    Taiyitist, and Youer.
- `download_vanilla_server_atomic`
  - Vanilla-specific atomic download helper with SHA-1 verification.
  - Implemented in `scripts/lib/server_install.sh`.
- `install_server`
  - Runtime-specific server artifact dispatcher.
  - Validates existing artifacts with `assert_server_install_matches`.
  - Writes `.server-install.json` with `write_server_install_marker`.

Runtime-specific behavior currently found in `install_server`:

- Vanilla
  - Requires `VERSION`.
  - Resolves Mojang launcher metadata.
  - Downloads `${DATA_DIR}/server.jar`.
  - Verifies the Mojang SHA-1.
  - Writes the server install marker for `server.jar`.
- Fabric
  - Requires `VERSION`.
  - Resolves Fabric loader and installer versions.
  - Downloads `/tmp/fabric-installer.jar`.
  - Runs the Fabric installer into `${DATA_DIR}`.
  - Produces `fabric-server-launch.jar`.
  - Writes the server install marker with the loader version as build metadata.
- Quilt
  - Requires `VERSION`.
  - Downloads the Quilt server jar to `${DATA_DIR}/server.jar`.
  - Writes the server install marker.
- Forge
  - Requires `VERSION`.
  - Resolves `FORGE_VERSION`, defaulting to latest.
  - Downloads the Forge installer to `/tmp`.
  - Runs the installer into `${DATA_DIR}`.
  - Requires `${DATA_DIR}/run.sh`.
  - Uses the legacy `.installed-forge-${VERSION}-${FORGE_VER}` marker.
  - Writes the server install marker for `run.sh`.
- NeoForge
  - Requires `VERSION`.
  - Resolves `NEOFORGE_VERSION`, defaulting to latest.
  - Downloads the NeoForge installer to `/tmp`.
  - Runs the installer into `${DATA_DIR}`.
  - Requires `${DATA_DIR}/run.sh`.
  - Uses the legacy `.installed-neoforge-${VERSION}-${NEO_VER}` marker.
  - Writes the server install marker for `run.sh`.
- Paper
  - Requires `VERSION`.
  - Resolves `PAPER_BUILD`, defaulting to latest.
  - Downloads `paper-${VERSION}-${BUILD}.jar` to `${DATA_DIR}/server.jar`.
  - Writes the server install marker with the selected build.
- Purpur
  - Requires `VERSION`.
  - Resolves `PURPUR_BUILD`, defaulting to latest.
  - Downloads the Purpur jar to `${DATA_DIR}/server.jar`.
  - Writes the server install marker with the selected build.
- Mohist
  - Requires `VERSION`.
  - Downloads the latest Mohist build for the selected Minecraft version to
    `${DATA_DIR}/server.jar`.
  - Writes the server install marker.
- Taiyitist
  - Requires `VERSION`.
  - Resolves the GitHub release asset for `${VERSION}-release`.
  - Downloads the Taiyitist server jar to `${DATA_DIR}/server.jar`.
  - Writes the server install marker.
- Youer
  - Requires `VERSION`.
  - Downloads the latest Youer build for the selected Minecraft version to
    `${DATA_DIR}/server.jar`.
  - Writes the server install marker.
- Spigot
  - Requires `VERSION`.
  - Supports an existing `${DATA_DIR}/server.jar`.
  - Validates that existing artifact with `assert_server_install_matches`.
  - Does not currently provide managed Spigot BuildTools/self-build behavior.
  - Fails fast if `TYPE=spigot` is selected without an existing artifact.
- Velocity
  - Requires `VERSION`.
  - Calls `generate_velocity_toml` from inside `install_server` today.
  - Resolves Velocity builds through PaperMC Fill v3.
  - Honors `VELOCITY_CHANNEL`, `VELOCITY_UA`, and `FORCE_REDOWNLOAD`.
  - Downloads `${DATA_DIR}/velocity.jar` through a Velocity-specific temp file.
  - Writes the server install marker with the selected build id.

Related functions and call sites:

- `clear_fabric_cache`
  - Runs immediately after `install_server` in the install sequence.
  - Applies to Fabric, Taiyitist, and Quilt.
  - Treat as adjacent cleanup, not part of the first artifact install move unless
    the PR explicitly preserves the same call order and behavior.
- `generate_velocity_toml`
  - Currently called both inside the Velocity branch of `install_server` and
    later in the install sequence.
  - Treat this as configuration generation, not artifact installation. Do not
    mix a Velocity config boundary with the artifact install move unless the
    call must remain temporarily for a mechanical extraction.
- `assert_server_install_matches`, `write_server_install_marker`, and
  `server_install_marker`
  - Implemented in `scripts/lib/runtime.sh`.
  - Server artifact installation should call these helpers but should not take
    ownership of their implementation.

Categories requested but not currently found:

- Managed Spigot BuildTools/self-build installation is not currently found.
- A separate `server_install.sh` library is not currently present.

## What should move

Future `scripts/lib/server_install.sh` may own:

- Runtime-specific artifact installation functions.
- Installer, download, and build functions for server artifacts.
- Artifact existence checks for server artifacts.
- Calls to `assert_server_install_matches` at install-skip boundaries.
- Calls to `write_server_install_marker` after successful artifact installation.
- Installer-specific temp files when they are only about server artifacts.
- Server-artifact download helpers that are not used by mods, plugins, configs,
  datapacks, resourcepacks, world install, or S3 handling.

## What should not move

Future `scripts/lib/server_install.sh` should not own:

- `run_server`.
- Runtime launch dispatch.
- `TYPE=auto` resolution.
- Runtime marker helper implementation.
- World install or world reset.
- `server.properties` bootstrap or property application.
- S3/MinIO client setup.
- Plugin, mod, config, datapack, or resourcepack installation.
- Lifecycle hook execution.
- RCON, shutdown, and signal handling.
- Velocity TOML generation as a broader config-generation concern.

## Staged migration order

Recommended implementation PRs:

1. Add `scripts/lib/server_install.sh` and move pure server-artifact download
   helpers.
   - Start with `download_file_atomic` and `download_vanilla_server_atomic` if
     they remain used only by server artifact installation.
   - Source the new library from `entrypoint.sh`.
   - Do not change `install_server` behavior yet.
   - Status: completed for the two download helpers only.
2. Move vanilla, Paper, and Purpur artifact installation.
   - These all produce `${DATA_DIR}/server.jar`.
   - Preserve `VERSION`, `PAPER_BUILD`, `PURPUR_BUILD`, filename, and marker
     semantics.
3. Move Fabric and Quilt artifact installation.
   - Preserve Fabric loader/installer version resolution and Quilt download
     behavior.
   - Keep `clear_fabric_cache` call timing unchanged.
4. Move Forge and NeoForge artifact installation.
   - Preserve `/tmp` installer filenames, `${DATA_DIR}/run.sh` checks, legacy
     `.installed-forge-*` and `.installed-neoforge-*` markers, and JSON server
     marker writes.
5. Move Velocity artifact installation.
   - Preserve Fill v3 build selection, channel fallback, User-Agent behavior,
     `FORCE_REDOWNLOAD`, temp filename behavior, size check, and marker build
     value.
   - Do not use this PR to redesign `generate_velocity_toml` ownership.
6. Move special jar runtimes: Mohist, Taiyitist, and Youer.
   - Preserve each download source and marker write behavior.
7. Move Spigot existing-artifact validation.
   - Preserve the current behavior that no managed Spigot installer is provided.
   - If managed BuildTools/self-build support is ever added, handle it in a
     dedicated behavior PR with extra smoke coverage.
8. Only after `server_install.sh` stabilizes, consider a separate runtime
   dispatch or `run_server` boundary.

## Risk notes

Specific risks to avoid during extraction:

- Changing server artifact detection order.
- Changing marker write timing.
- Changing marker assert timing.
- Changing `.server-install.json` shape or path.
- Changing Forge/NeoForge legacy marker behavior.
- Changing `VERSION`, `BUILD`, `PAPER_BUILD`, `PURPUR_BUILD`,
  `FABRIC_INSTALLER_VERSION`, `FORGE_VERSION`, `NEOFORGE_VERSION`,
  `VELOCITY_CHANNEL`, `VELOCITY_UA`, or `FORCE_REDOWNLOAD` behavior.
- Changing downloaded filenames or final artifact paths.
- Changing installer temp file locations or cleanup behavior.
- Changing first-boot versus restart behavior when an artifact already exists.
- Accidentally adding Spigot BuildTools/self-build behavior during a mechanical
  move.
- Accidentally mixing runtime launch behavior with install behavior.
- Accidentally mixing Velocity config generation with artifact download logic.

## Test and smoke guidance

For implementation PRs that create or populate `server_install.sh`, use focused
checks:

- Run `bash -n entrypoint.sh scripts/lib/*.sh`.
- Run `shellcheck -x -s bash entrypoint.sh scripts/lib/*.sh` when ShellCheck is
  installed.
- Add or run a source smoke test for the new `scripts/lib/server_install.sh`.
- Prefer install-only smoke tests per runtime where existing tests support it.
- Add marker assertion tests around skip/restart paths when practical.
- Use temporary directories for any filesystem smoke tests.
- Do not require real S3 credentials.
- Do not trigger destructive world reset behavior.
- Avoid full server boot unless an existing smoke test already does so safely.

## Guardrails

- Keep future implementation PRs small and mechanical.
- Do not combine cleanup backlog items with server artifact moves.
- Do not move `run_server` or runtime dispatch in the same PR as server artifact
  installation.
- Do not change install marker formats, install order, or world behavior unless a
  dedicated PR explicitly targets that behavior.
