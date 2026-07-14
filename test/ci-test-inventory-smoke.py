#!/usr/bin/env python3
"""Verify the authoritative classification of every standalone smoke test."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(os.environ.get("CI_TEST_INVENTORY_ROOT", Path(__file__).resolve().parents[1])).resolve()
MANIFEST = Path(os.environ.get("CI_TEST_INVENTORY_MANIFEST", ROOT / "test/ci-test-manifest.tsv")).resolve()
SUPPORTED = {"bash": ".sh", "python3": ".py"}


def fail(message: str) -> None:
    raise SystemExit(f"ci test inventory failed: {message}")


def load_manifest(path: Path) -> dict[str, tuple[str, str, int, str]]:
    entries: dict[str, tuple[str, str, int, str]] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not raw or raw.startswith("#"):
            continue
        fields = raw.split("\t")
        if len(fields) != 5:
            fail(f"{path}:{number}: expected five tab-separated fields")
        test_path, runner, tier, timeout_text, reason = fields
        if not test_path.startswith("test/") or ".." in Path(test_path).parts or Path(test_path).is_absolute():
            fail(f"{path}:{number}: unsafe test path {test_path!r}")
        if test_path in entries:
            fail(f"duplicate manifest entry: {test_path}")
        if runner not in SUPPORTED or not test_path.endswith(SUPPORTED[runner]):
            fail(f"{test_path}: unsupported or mismatched runner {runner!r}")
        if tier not in {"mandatory", "external"}:
            fail(f"{test_path}: unsupported tier {tier!r}")
        try:
            timeout = int(timeout_text)
        except ValueError:
            fail(f"{test_path}: timeout is not an integer")
        if timeout <= 0:
            fail(f"{test_path}: timeout must be positive")
        if tier == "external" and not reason.strip():
            fail(f"{test_path}: external tests require a concrete reason")
        if tier == "mandatory" and reason:
            fail(f"{test_path}: mandatory tests must not carry an exemption reason")
        target = ROOT / test_path
        if not target.is_file():
            fail(f"manifest path does not exist: {test_path}")
        entries[test_path] = (runner, tier, timeout, reason)
    return entries


def main() -> None:
    if not MANIFEST.is_file():
        fail("test/ci-test-manifest.tsv is missing")
    entries = load_manifest(MANIFEST)
    discovered = {
        path.relative_to(ROOT).as_posix()
        for pattern in ("*-smoke.sh", "*-smoke.py")
        for path in (ROOT / "test").glob(pattern)
    }
    missing = sorted(discovered - entries.keys())
    extra = sorted(entries.keys() - discovered)
    if missing:
        fail(f"unclassified standalone tests: {', '.join(missing)}")
    if extra:
        fail(f"manifest tests are not standalone smoke tests: {', '.join(extra)}")
    for required in ("test/ci-test-inventory-smoke.py", "test/ci-test-runner-smoke.sh"):
        if required not in entries:
            fail(f"required policy test omitted: {required}")
    print(f"ci test inventory passed: {len(entries)} tests ({sum(t[1] == 'mandatory' for t in entries.values())} mandatory)")


def run_fixture_checks() -> None:
    """Exercise failures without changing the repository manifest."""
    with tempfile.TemporaryDirectory() as temporary:
        fixture_root = Path(temporary)
        fixture_test = fixture_root / "test"
        fixture_test.mkdir()
        for name in ("ci-test-inventory-smoke.py", "ci-test-runner-smoke.sh", "sample-smoke.sh"):
            (fixture_test / name).write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")

        valid = "\n".join(
            (
                "test/ci-test-inventory-smoke.py\tpython3\tmandatory\t60\t",
                "test/ci-test-runner-smoke.sh\tbash\tmandatory\t60\t",
                "test/sample-smoke.sh\tbash\tmandatory\t60\t",
            )
        ) + "\n"

        def check(name: str, contents: str, expected: int) -> None:
            manifest = fixture_test / f"{name}.tsv"
            manifest.write_text(contents, encoding="utf-8")
            environment = os.environ | {
                "CI_TEST_INVENTORY_ROOT": str(fixture_root),
                "CI_TEST_INVENTORY_MANIFEST": str(manifest),
                "CI_TEST_INVENTORY_SKIP_FIXTURES": "1",
            }
            completed = subprocess.run([sys.executable, __file__], env=environment, capture_output=True, text=True, check=False)
            if (completed.returncode == 0) != (expected == 0):
                fail(f"fixture {name} returned {completed.returncode}: {completed.stderr}")

        check("valid", valid, 0)
        check("unlisted", valid.replace("test/sample-smoke.sh\tbash\tmandatory\t60\t\n", ""), 1)
        check("missing", valid.replace("test/sample-smoke.sh", "test/missing-smoke.sh"), 1)
        check("duplicate", valid + "test/sample-smoke.sh\tbash\tmandatory\t60\t\n", 1)
        check("external-no-reason", valid.replace("test/sample-smoke.sh\tbash\tmandatory\t60\t", "test/sample-smoke.sh\tbash\texternal\t60\t"), 1)


if __name__ == "__main__":
    main()
    if not os.environ.get("CI_TEST_INVENTORY_SKIP_FIXTURES"):
        run_fixture_checks()
