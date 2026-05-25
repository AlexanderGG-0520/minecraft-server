# Server install reinstall policy

This image records managed server artifact installs in
`${DATA_DIR}/.server-install.json`, normally `/data/.server-install.json`.
The marker is written by `write_server_install_marker` after a managed server
artifact is installed.

The current marker schema is:

- `artifact`
- `type`
- `version`
- `build`

`build` may be an empty string for server types that do not use a build or
loader value. The marker schema is not changed by this policy.

## Default behavior

If no managed server artifact exists, the installer installs normally.

If a server artifact exists without `.server-install.json`, the entrypoint keeps
the legacy/manual-artifact behavior: it logs a warning and leaves the artifact in
place. This avoids deleting bring-your-own or older volume contents without an
explicit operator decision.

If both the artifact and marker exist, the marker is validated first. Invalid
JSON, missing fields, null fields, non-string fields, unsupported marker types,
and unsupported marker artifacts fail fast before any reinstall decision is made.

When the marker is valid, the installer compares the marker with the requested
effective install configuration:

- `artifact` must match the expected managed artifact name.
- `type` must match the requested server type.
- `version` must match the requested Minecraft/server version.
- `build` must match the requested effective build, loader, or installer version
  when that server type records one.

If those values match, the existing artifact is reused.

If any value differs, startup fails by default. The error includes the marker
path, the differing fields, the marker values, the requested values, and an
instruction to set `FORCE_REINSTALL=true` only when the operator intentionally
wants to reinstall the server artifact.

## FORCE_REINSTALL=true

Only the literal value `FORCE_REINSTALL=true` enables forced reinstall behavior.
Unset, empty, `false`, `1`, `yes`, or any other value is treated as disabled.

When `FORCE_REINSTALL=true` and a valid marker does not match the requested
effective install configuration, the entrypoint logs a warning, removes only the
managed server install state, and then continues through the normal installer for
the requested configuration.

Removed:

- The managed server artifact recorded by the install marker.
- The requested managed server artifact if it differs from the marker artifact.
- `/data/.server-install.json`.
- Forge/NeoForge legacy install marker files when the marker identifies a
  Forge/NeoForge install.

Not removed:

- World data.
- Mods.
- Plugins.
- Config files.
- Datapacks.
- Resourcepacks.
- `server.properties`, `eula.txt`, `ops.json`, or `whitelist.json`.
- Modpack install state.

`FORCE_REINSTALL=true` is not a repair path for corrupt marker JSON. Invalid
markers still fail fast because the runtime cannot safely decide what managed
install state belongs to the existing artifact.

## Examples

### VERSION changed after install

If `/data/server.jar` was installed as Paper `VERSION=1.21.8` and the pod is
redeployed with `VERSION=1.21.9`, the marker comparison fails by default. Set
`FORCE_REINSTALL=true` only if replacing the managed server artifact is the
intended operation.

### PAPER_BUILD or PURPUR_BUILD changed after install

Paper and Purpur write the selected build to the marker. If `PAPER_BUILD` or
`PURPUR_BUILD` changes from the marker value, startup fails by default instead
of silently replacing `server.jar`.

When `PAPER_BUILD=latest` or `PURPUR_BUILD=latest`, the installer resolves the
effective latest build before comparing against the marker. If that resolved
build differs from the installed marker, the drift is surfaced explicitly.

### TYPE changed after install

If a volume contains a marker for `TYPE=paper` but the pod is redeployed with
`TYPE=vanilla`, startup fails by default. This prevents one runtime flavor from
silently overwriting another runtime flavor's server artifact.

### server.jar exists without marker

If `/data/server.jar` exists but `/data/.server-install.json` does not, the
entrypoint preserves the existing legacy/manual-artifact behavior. It logs a
warning and leaves the artifact in place.

## Kubernetes and GitOps rationale

This policy makes install configuration drift visible. A pod restart should not
silently mutate a persistent volume because `TYPE`, `VERSION`, or a build
setting changed in Git. Default fail-fast behavior gives operators a clear
review point, while `FORCE_REINSTALL=true` provides an explicit one-deploy
escape hatch when replacing only the managed server artifact is intentional.
