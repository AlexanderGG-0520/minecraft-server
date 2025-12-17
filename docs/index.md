# Minecraft Server Runtime (Kubernetes-native)

This repository provides a **Kubernetes-first Minecraft server image**,
designed for long-term operation, reproducibility, and transparency.

It is not a “plug-and-play” image.
It is a runtime intended for people who want to understand
*what is happening* and *why it behaves that way*.

---

## Project goals

- Kubernetes-native design (PVC-first, restart-safe)
- Clear separation between initialization and runtime
- Explicit handling of world generation conditions
- Optional GPU acceleration (experimental)
- Debuggable behavior over convenience

---

## Current status

- Multi-runtime support (Fabric / Forge / NeoForge / Paper / Vanilla)
- GPU-capable builds using NVIDIA CUDA images
- Tested on real Kubernetes clusters with persistent volumes
- World generation stability fixes applied (v0.2.0)

---

## Philosophy

Minecraft world generation is fragile.
Kubernetes restarts are normal.

This project treats those facts seriously.

World generation is performed **once**, under fixed conditions.
Runtime restarts never silently change worldgen rules.

If you are looking for a black-box image that “just works”,
this project may not be for you.

If you want a runtime you can reason about,
inspect, and trust over time, you are in the right place.

---

## Links

- [https://github.com/AlexanderGG-0520/minecraft-server](Github Repository)
- [https://github.com/AlexanderGG-0520/minecraft-server/releases](Releases)
