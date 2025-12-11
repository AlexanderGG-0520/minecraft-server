# Base Configuration Layer

This directory contains configuration files that apply to *all* server types
(Fabric, Paper, NeoForge, Forge, Vanilla, Proxy types, etc).

These configs are copied into /data **before** TYPE-specific configuration
is applied.

## Files

- `base.env`  
  Default environment variables.

- `jvm-common.args`  
  Shared JVM performance flags.

- `mc-common.args`  
  Shared Minecraft launch parameters.

- `server.properties`  
  Default server configuration.

- `whitelist.json`, `ops.json`  
  Empty placeholders, useful for Kubernetes PVC bootstrap.

## Override Order

1. base/ files  
2. TYPE-specific config  
3. User-provided files in /data (highest priority)
