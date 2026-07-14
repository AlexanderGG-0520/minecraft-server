# Contributing

Thanks for improving this project. Keep changes focused and easy to review.

## Pull requests

* Use small, focused pull requests.
* Do not push directly to `main`.
* Preserve existing environment variable semantics unless the PR intentionally changes them.
* Include tests or smoke coverage for behavior changes.
* Update documentation when user-facing behavior changes.
* Start large design changes as issues or design notes before implementation.

This repository intentionally favors explicit behavior, predictable failure modes, safe persistent
volume handling, and clear lifecycle boundaries. Changes should preserve those design constraints unless
the PR clearly explains why they need to change.

## Local checks

Run the relevant checks before opening a PR:

```bash
bash -n entrypoint.sh
shopt -s nullglob
lib_scripts=(scripts/lib/*.sh)
if [ "${#lib_scripts[@]}" -eq 0 ]; then
  echo "No scripts found under scripts/lib/" >&2
  exit 1
fi

for script in "${lib_scripts[@]}"; do
  bash -n "$script"
done

shellcheck -x -s bash entrypoint.sh "${lib_scripts[@]}"
```

For behavior changes, also run the relevant smoke tests under `test/`. Prefer small temp-directory smoke
coverage when possible instead of requiring a real Minecraft server boot.

## Smoke-test inventory

Run the complete mandatory suite locally with:

```fish
scripts/ci/run-test-manifest.sh
```

Run one test directly with its listed runner, for example:

```fish
bash test/filesystem-safety-smoke.sh
```

Every new `test/*-smoke.sh` or `test/*-smoke.py` must be added exactly once to
`test/ci-test-manifest.tsv`; the inventory checker makes an unclassified test fail CI. Use `mandatory`
for deterministic tests that use only repository fixtures and disposable state, have no production
credentials, and are safe on untrusted pull requests. Use `external` only for a concrete environmental
need such as a disposable Docker service, GPU execution, or an upstream integration; it requires a
specific reason. Select a timeout that comfortably covers normal local execution. Tests must clean up
their temporary state and must not use production credentials or persistent developer data.

## Documentation

Documentation changes should be accurate about what the image does today. Avoid promising automatic
repair, broad compatibility, or beginner-focused behavior unless the implementation actually provides
it.
