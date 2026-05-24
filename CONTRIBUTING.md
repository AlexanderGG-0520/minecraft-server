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

## Documentation

Documentation changes should be accurate about what the image does today. Avoid promising automatic
repair, broad compatibility, or beginner-focused behavior unless the implementation actually provides
it.
