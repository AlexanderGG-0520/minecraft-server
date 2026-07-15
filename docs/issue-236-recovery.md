# Recovering a partial Minecraft 26.2 world

Images affected by Issue #236 could stop the first Fabric startup after creating
`level.dat` but before writing a valid
`data/minecraft/world_gen_settings.dat`. The resulting world cannot be repaired by
restarting the container.

Before regenerating a world:

1. Stop the Compose service: `docker compose stop <service>`.
2. Find the configured `LEVEL_NAME` (the default is `world`) and inspect only that
   directory in the mounted data volume.
3. Back it up, for example:
   `cp -a /path/to/data/world /path/to/backups/world-issue-236`.
4. Confirm the affected test world contains `level.dat` and does not contain a
   valid `data/minecraft/world_gen_settings.dat`.
5. If that world may be regenerated, remove only the confirmed partial world
   directory. Do not delete `/data` or unrelated worlds, configuration, mods, or
   backups.
6. Pull or build an image containing the Issue #236 fix, then run
   `docker compose up -d <service>`.

If the partial world contains anything that must be preserved, keep the backup and
do not regenerate it in place. Restore or repair it with appropriate world tooling
before starting the server.

## Readiness follow-up

The `.ready` marker currently means only that the JVM survived `READY_DELAY`; it
does not prove that Minecraft completed initialization. Issue #236 exposed that
limitation because Minecraft can catch a startup error and remain alive briefly or
exit successfully. Readiness is intentionally not changed in the bootstrap fix: a
separate change should derive readiness from Minecraft's `Done` log message or an
equivalent active probe, with coverage for log rotation and non-vanilla launchers
(tracked in [Issue #240](https://github.com/AlexanderGG-0520/minecartainer/issues/240)).
