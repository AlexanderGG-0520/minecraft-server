# Minecraft Server (Performance-first)

![Docker Build](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-server/publish.yml?branch=main)
[![Docker Pulls](https://img.shields.io/docker/pulls/alecjp02/minecraft-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-server/)
[![Docker Stars](https://img.shields.io/docker/stars/alecjp02/minecraft-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-server/)
[![GitHub Issues](https://img.shields.io/github/issues-raw/alecjp02/docker-minecraft-server.svg)](https://github.com/alexandergg-0520/minecraft-server/issues)
![GHCR](https://img.shields.io/badge/GHCR-ghcr.io%2Falexandergg--0520%2Fminecraft--server-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Java](https://img.shields.io/badge/java-8%20%7C%2011%20%7C%2017%20%7C%2021%20%7C%2025%20%7C%2025--gpu-orange)
![Kubernetes](https://img.shields.io/badge/kubernetes-ready-blue)

A **minimal, explicit, and predictable** Minecraft server Docker image.

This project is for people who already know *why* feature-rich images sometimes feel slow.

---

## What this is

This repository provides a **performance-first Minecraft server runtime** designed with the following assumptions:

* You understand Docker and Minecraft server internals
* You prefer **explicit configuration over abstraction**
* You value **predictability and speed** over convenience
* You are fine with the server **failing fast** instead of auto-fixing silently

It is especially well-suited for:

* Kubernetes / GitOps environments
* Long-running or frequently recreated servers
* Performance-sensitive world generation
* Advanced modded setups

---

## What this is NOT

This project is intentionally **not**:

* Beginner-friendly
* Feature-heavy
* Auto-healing or self-repairing
* A drop-in replacement for general-purpose Minecraft images

If you want a server that "just works" with minimal understanding, this is probably not for you.

---

## Design philosophy

* **Explicit configuration over abstraction**
  Every behavior is controlled by clear environment variables. Nothing happens implicitly.

* **Minimal startup logic**
  Startup paths are kept short. If something is already correct, it is not re-validated.

* **Fail fast, never hide errors**
  Misconfiguration should crash early, not be silently corrected.

* **One entrypoint, predictable lifecycle**
  No magic phases, no hidden state transitions.

* **Performance is a feature**
  Especially for world generation and large modpacks.

---

## Java runtime

* Uses **Eclipse Temurin** exclusively
* Java versions are selected **explicitly via image tags**
* No runtime JVM switching

This avoids ambiguity and ensures reproducible behavior.

---

## Mod / Config synchronization

* Mods, configs, datapacks, and resource packs can be synchronized from **S3-compatible storage** (e.g. MinIO)
* Sync rules are **explicit and predictable**
* Removed files can be pruned intentionally

This model works well with immutable containers and externalized state.

---

## GPU acceleration (Experimental)

Experimental support for **C2ME GPU acceleration** is available, but:

* Disabled by default
* Requires explicit opt-in flags
* Cannot be enabled accidentally

Experimental features must always be *obviously experimental*.

---

## Who should use this

You might like this project if:

* You have used feature-rich Minecraft images and felt they were "doing too much"
* You care about startup time and world generation performance
* You run servers as cattle, not pets
* You prefer Linux-style tooling and philosophy

---

## Who should NOT use this

* First-time server operators
* Users unfamiliar with Docker or JVM tuning
* Anyone expecting automatic recovery from mistakes

---

## Quick start

```bash
# Example: Java 21 runtime

docker run \
  -e EULA=true \
  -e TYPE=FABRIC \
  -e VERSION=1.21.1 \
  -v ./data:/data \
  ghcr.io/alexandergg-0520/minecraft-server:runtime-jre21
```

You are expected to read the configuration options before running this in production.

---

## Credits

This project is inspired by existing Minecraft server images and the broader container ecosystem.

It exists to provide **another option** — not to replace anything.
