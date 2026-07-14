#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp}"' EXIT
mkdir -p "${tmp}/space dir"
printf '#!/usr/bin/env bash\nprintf pass\n' > "${tmp}/space dir/pass-smoke.sh"
printf '#!/usr/bin/env bash\nprintf fail\nexit 7\n' > "${tmp}/fail-smoke.sh"
printf '#!/usr/bin/env bash\nsleep 2\n' > "${tmp}/timeout-smoke.sh"
printf '#!/usr/bin/env bash\nprintf after\n' > "${tmp}/after-smoke.sh"
chmod 0755 "${tmp}"/*.sh "${tmp}/space dir/pass-smoke.sh"
manifest="${tmp}/manifest.tsv"
printf '%s\n' \
  "${tmp}/space dir/pass-smoke.sh	bash	mandatory	5	" \
  "${tmp}/fail-smoke.sh	bash	mandatory	5	" \
  "${tmp}/timeout-smoke.sh	bash	mandatory	1	" \
  "${tmp}/after-smoke.sh	bash	mandatory	5	" > "${manifest}"

set +e
output="$("${root}/scripts/ci/run-test-manifest.sh" "${manifest}" 2>&1)"
status=$?
set -e
test "${status}" -ne 0
printf '%s\n' "${output}" | grep -F 'PASS ' >/dev/null
printf '%s\n' "${output}" | grep -F 'FAIL ' >/dev/null
printf '%s\n' "${output}" | grep -F 'TIMEOUT ' >/dev/null
printf '%s\n' "${output}" | grep -F 'after' >/dev/null
printf '%s\n' "${output}" | grep -F 'Mandatory tests: 4' >/dev/null
printf '%s\n' "${output}" | grep -F 'Passed: 2' >/dev/null
printf '%s\n' "${output}" | grep -F 'Failed: 1' >/dev/null
printf '%s\n' "${output}" | grep -F 'Timed out: 1' >/dev/null
if pgrep -f "${tmp}/timeout-smoke.sh" >/dev/null; then
  printf 'timed-out test process is still running\n' >&2
  exit 1
fi

bad_manifest="${tmp}/bad-manifest.tsv"
printf '%s\t%s\t%s\t%s\t\n' "${tmp}/after-smoke.sh" not-a-runner mandatory 5 > "${bad_manifest}"
set +e
bad_output="$("${root}/scripts/ci/run-test-manifest.sh" "${bad_manifest}" 2>&1)"
bad_status=$?
set -e
test "${bad_status}" -eq 2
printf '%s\n' "${bad_output}" | grep -F 'Unsupported runner' >/dev/null
