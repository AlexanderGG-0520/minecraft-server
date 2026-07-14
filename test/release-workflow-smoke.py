#!/usr/bin/env python3
"""Static invariants for the exact-SHA release workflow."""

from pathlib import Path
import re
import sys

try:
    import yaml
except ImportError as error:
    raise SystemExit(f"PyYAML is required for this smoke test: {error}")


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/publish.yml"
TARGETS = {
    "runtime-jre8",
    "runtime-jre11",
    "runtime-jre17",
    "runtime-jre21",
    "runtime-jre25",
    "runtime-jre25-gpu",
}


def fail(message: str) -> None:
    raise SystemExit(f"release workflow smoke test failed: {message}")


def text(step: dict) -> str:
    return "\n".join(str(value) for value in step.values())


workflow_text = WORKFLOW.read_text(encoding="utf-8")
workflow = yaml.load(workflow_text, Loader=yaml.BaseLoader)
jobs = workflow.get("jobs", {})
required_jobs = {"resolve-source", "validate-shell", "validate-target", "publish-immutable", "promote-aliases"}
if set(jobs) != required_jobs:
    fail(f"unexpected release job set: {sorted(jobs)}")

targets_match = re.search(r"targets='(\[[^']+\])'", workflow_text)
if not targets_match:
    fail("authoritative target JSON is missing")
targets = set(yaml.load(targets_match.group(1), Loader=yaml.BaseLoader))
if targets != TARGETS:
    fail(f"authoritative target set is {sorted(targets)}, expected {sorted(TARGETS)}")

for job_name in ("validate-target", "publish-immutable", "promote-aliases"):
    matrix = jobs[job_name].get("strategy", {}).get("matrix", {}).get("target", "")
    if "needs.resolve-source.outputs.targets" not in matrix:
        fail(f"{job_name} does not consume the authoritative target matrix")

for job_name in ("validate-shell", "validate-target", "publish-immutable"):
    steps = jobs[job_name].get("steps", [])
    checkout = next((step for step in steps if step.get("name") == "Checkout resolved source"), None)
    if not checkout or "needs.resolve-source.outputs.source_sha" not in checkout.get("with", {}).get("ref", ""):
        fail(f"{job_name} does not check out the resolved SHA")
    assertion = next((step for step in steps if step.get("name") == "Assert resolved source"), None)
    if not assertion or "git rev-parse HEAD" not in assertion.get("run", ""):
        fail(f"{job_name} does not assert the checked out SHA")

publish_needs = set(jobs["publish-immutable"].get("needs", []))
if not {"resolve-source", "validate-shell", "validate-target"}.issubset(publish_needs):
    fail("production immutable publishing is not downstream of the complete validation gate")
promote_needs = set(jobs["promote-aliases"].get("needs", []))
if not {"resolve-source", "publish-immutable"}.issubset(promote_needs):
    fail("alias promotion is not downstream of immutable publishing")

for job_name in ("validate-shell", "validate-target"):
    if "push: true" in workflow_text[workflow_text.find(f"    {job_name}:"):workflow_text.find("\n    ", workflow_text.find(f"    {job_name}:") + 5)]:
        fail(f"validation job {job_name} has a production push")

validate_build = next(step for step in jobs["validate-target"]["steps"] if step.get("name") == "Build validation image without publishing")
if validate_build.get("with", {}).get("push") != "false":
    fail("target validation build must use push: false")

resolver = ROOT / "scripts/release/resolve-source.sh"
resolver_text = resolver.read_text(encoding="utf-8")
if "refs/tags/${release_tag}:refs/tags/${release_tag}" not in resolver_text or "refs/tags/${release_tag}^{commit}" not in resolver_text:
    fail("manual tag resolution must fetch refs/tags and peel to a commit")
if "release_tag_is_valid" not in resolver_text or re.search(r"\beval\b", resolver_text):
    fail("manual tag validation is missing or unsafe")

if "CHANNEL}" == "main" not in workflow_text:
    fail("main-only mutable runtime alias policy is missing")
if "${RELEASE_TAG}-${TARGET}" not in workflow_text:
    fail("versioned release alias promotion is missing")
if "-sha-${{ needs.resolve-source.outputs.source_sha }}" not in workflow_text:
    fail("immutable SHA image tag is missing")
if "org.opencontainers.image.revision=${{ needs.resolve-source.outputs.source_sha }}" not in workflow_text:
    fail("OCI revision label must use resolved source SHA")
if "cancel-in-progress: false" not in workflow_text:
    fail("release concurrency must not cancel an in-progress publication")
if workflow_text.count("docker buildx imagetools inspect") != 2 or "test \"${ghcr_digest}\" = \"${DIGEST}\"" not in workflow_text:
    fail("immutable publication must record and compare both registry digests")

for job_name in ("resolve-source", "validate-shell", "validate-target"):
    permissions = jobs[job_name].get("permissions", {})
    if permissions and permissions.get("packages") == "write":
        fail(f"validation job {job_name} has package write permission")

lint_workflow = ROOT / ".github/workflows/lint-and-smoke.yml"
lint_text = lint_workflow.read_text(encoding="utf-8")
for workflow_name, workflow_text in (("lint", lint_text), ("release validation", workflow_text)):
    if "python3 test/ci-test-inventory-smoke.py" not in workflow_text:
        fail(f"{workflow_name} does not run the smoke-test inventory checker")
    if "scripts/ci/run-test-manifest.sh" not in workflow_text:
        fail(f"{workflow_name} does not run the authoritative smoke-test manifest")

if "for test_file in test/*.sh" in workflow_text:
    fail("release validation retains an independent shell-test list")
if "test/filesystem-safety-smoke.sh" in lint_text:
    fail("lint workflow retains individually maintained standalone smoke-test steps")

print("release workflow smoke test passed")
