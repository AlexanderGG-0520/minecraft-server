#!/usr/bin/env python3
"""Static safety checks for the maintained Compose quick starts."""

from pathlib import Path
import sys

try:
    import yaml
except ImportError as error:
    raise SystemExit(f"PyYAML is required for this smoke test: {error}")


ROOT = Path(__file__).resolve().parents[1]
IMAGE = "ghcr.io/alexandergg-0520/minecraft-server"
EXPECTED = {
    "paper": {"type": "paper", "image": f"{IMAGE}:runtime-jre21", "version": "1.21.8", "asset": "plugins"},
    "fabric": {"type": "fabric", "image": f"{IMAGE}:runtime-jre25", "version": "26.2", "asset": "mods"},
}


def fail(message: str) -> None:
    raise SystemExit(f"docker compose quickstart smoke test failed: {message}")


for name, expected in EXPECTED.items():
    directory = ROOT / "examples" / "docker" / name
    compose_path = directory / "compose.yml"
    readme_path = directory / "README.md"
    if not compose_path.is_file() or not readme_path.is_file():
        fail(f"{name} Compose and README must exist")

    compose = yaml.load(compose_path.read_text(encoding="utf-8"), Loader=yaml.BaseLoader)
    services = compose.get("services", {})
    if set(services) != {"minecraft"}:
        fail(f"{name} must define exactly the minecraft service")
    service = services["minecraft"]
    if service.get("image") != expected["image"] or ":latest" in service.get("image", ""):
        fail(f"{name} image must be the intended non-latest repository image")
    environment = service.get("environment", {})
    for key, value in {
        "EULA": "true",
        "TYPE": expected["type"],
        "VERSION": expected["version"],
        "ENABLE_RCON": "true",
        "RCON_PASSWORD": "local-only-change-me",
    }.items():
        if environment.get(key) != value:
            fail(f"{name} environment {key} must be {value!r}")
    if not environment.get("JVM_XMS") or not environment.get("JVM_XMX"):
        fail(f"{name} must set JVM_XMS and JVM_XMX")
    if service.get("restart") != "unless-stopped" or service.get("stop_grace_period") != "240s":
        fail(f"{name} must use the documented restart and shutdown policy")
    if service.get("privileged") == "true" or service.get("pid") == "host" or service.get("network_mode") == "host":
        fail(f"{name} uses an unsafe host-level container option")
    volumes = service.get("volumes", [])
    if not any(str(item).endswith(":/data") and not str(item).startswith("/") for item in volumes):
        fail(f"{name} must mount a named persistent volume at /data")
    if any("docker.sock" in str(item) for item in volumes):
        fail(f"{name} must not mount the Docker socket")
    ports = service.get("ports", [])
    if not any("25565:25565" in str(item) for item in ports):
        fail(f"{name} must intentionally publish Minecraft port 25565")
    if "minecraft_data" not in compose.get("volumes", {}):
        fail(f"{name} must declare minecraft_data")

    readme = readme_path.read_text(encoding="utf-8")
    for required in ("docker compose up -d", "docker compose stop", "docker compose restart", "docker compose pull", f"/data/{expected['asset']}"):
        if required not in readme:
            fail(f"{name} README is missing {required!r}")
    if "docker compose down -v" not in readme or "permanently deletes" not in readme:
        fail(f"{name} README must explicitly warn about destructive volume deletion")
    if "<<" in readme or "\nchmod -R 777" in readme:
        fail(f"{name} README contains a prohibited command pattern")

root_readme = (ROOT / "README.md").read_text(encoding="utf-8")
for required in ("examples/docker/paper/", "examples/docker/fabric/"):
    if required not in root_readme:
        fail(f"root README must link to {required}")

print("docker compose quickstart smoke test passed")
