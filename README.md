# Minecraft Server (Performance-first)

![Docker Build](https://img.shields.io/github/actions/workflow/status/AlexanderGG-0520/minecraft-server/publish.yml?branch=main)
[![Docker Pulls](https://img.shields.io/docker/pulls/alecjp02/minecraft-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-server/)
[![Docker Stars](https://img.shields.io/docker/stars/alecjp02/minecraft-server.svg?logo=docker)](https://hub.docker.com/r/alecjp02/minecraft-server/)
[![GitHub Issues](https://img.shields.io/github/issues-raw/alexandergg-0520/minecraft-server.svg)](https://github.com/alexandergg-0520/minecraft-server/issues)
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

## Documentation (Wiki)

This project has **extensive documentation** in the GitHub Wiki.

The Wiki explains not only *how* to run the server, but *why* it is designed this way —  
including lifecycle separation, persistent storage strategy, and world safety guarantees.

### Start here

[Wiki Home](https://github.com/AlexanderGG-0520/minecraft-server/wiki)

### Recommended reading order

1. **Getting Started / Quick Start**  
   Fastest way to run the server safely

2. **Lifecycle Design (Install Phase / Runtime Phase)**  
   Core design philosophy and safety guarantees

3. **Environment Variables**  
   How configuration is classified and applied

4. **World Reset Mechanism**  
   How destructive changes are made explicit and safe

5. **Storage & Persistence**  
   PVC, volume strategy, and migration

6. **FAQ**  
   Differences vs itzg/minecraft-server and common pitfalls

> ⚠️ If you skip the lifecycle documentation,  
> you may misunderstand why some environment variables are intentionally ignored.

---

## Credits

This project is inspired by existing Minecraft server images and the broader container ecosystem.

It exists to provide **another option** — not to replace anything.
