#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# itzg/minecraft-server compatibility layer
# ============================================================

# --- JVM / Memory ---
if [[ -n "${MEMORY:-}" ]]; then
  INIT_MEMORY="${INIT_MEMORY:-$MEMORY}"
  MAX_MEMORY="${MAX_MEMORY:-$MEMORY}"
fi

# --- Server core ---
SERVER_PORT="${SERVER_PORT:-${PORT:-25565}}"

# --- Gameplay ---
MAX_PLAYERS="${MAX_PLAYERS:-${MAX_PLAYERS:-20}}"
MOTD="${MOTD:-A Minecraft Server}"
ONLINE_MODE="${ONLINE_MODE:-true}"
DIFFICULTY="${DIFFICULTY:-easy}"
MODE="${MODE:-survival}"
PVP="${PVP:-true}"
ALLOW_FLIGHT="${ALLOW_FLIGHT:-false}"
VIEW_DISTANCE="${VIEW_DISTANCE:-10}"
SIMULATION_DISTANCE="${SIMULATION_DISTANCE:-10}"
LEVEL="${LEVEL:-world}"

export \
  INIT_MEMORY MAX_MEMORY SERVER_PORT \
  MAX_PLAYERS MOTD ONLINE_MODE DIFFICULTY MODE \
  PVP ALLOW_FLIGHT VIEW_DISTANCE SIMULATION_DISTANCE LEVEL
