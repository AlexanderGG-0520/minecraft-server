#!/usr/bin/env bash
set -u
set -o pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
manifest="${1:-${root}/test/ci-test-manifest.tsv}"
cd -- "${root}"
export LC_ALL=C
export LANG=C
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_ACCESS_KEY S3_SECRET_KEY

[[ -f "${manifest}" ]] || { echo "Manifest not found: ${manifest}" >&2; exit 2; }

validate_manifest() {
  local raw path runner tier timeout_seconds reason extra line=0
  while IFS= read -r raw; do
    line=$((line + 1))
    [[ -z "${raw}" || "${raw}" == \#* ]] && continue
    IFS=$'\t' read -r path runner tier timeout_seconds reason extra <<< "${raw}"
    [[ -z "${extra}" ]] || { printf 'Invalid manifest line %s: expected five tab-separated fields\n' "${line}" >&2; return 2; }
    [[ -n "${runner}" && -n "${tier}" && -n "${timeout_seconds}" ]] || {
      printf 'Invalid manifest line %s: expected path, runner, tier, and timeout\n' "${line}" >&2
      return 2
    }
    case "${runner}" in bash|python3) ;; *) printf 'Unsupported runner on line %s: %s\n' "${line}" "${runner}" >&2; return 2 ;; esac
    case "${tier}" in mandatory|external) ;; *) printf 'Unsupported tier on line %s: %s\n' "${line}" "${tier}" >&2; return 2 ;; esac
    [[ "${timeout_seconds}" =~ ^[1-9][0-9]*$ ]] || {
      printf 'Invalid timeout on line %s: %s\n' "${line}" "${timeout_seconds}" >&2
      return 2
    }
    [[ -f "${path}" ]] || { printf 'Manifest test not found on line %s: %s\n' "${line}" "${path}" >&2; return 2; }
  done < "${manifest}"
}

validate_manifest || exit $?

passed=0 failed=0 timed_out=0 total=0
while IFS= read -r raw; do
  [[ -z "${raw}" || "${raw}" == \#* ]] && continue
  IFS=$'\t' read -r path runner tier timeout_seconds reason <<< "${raw}"
  [[ "${tier}" == mandatory ]] || continue
  total=$((total + 1))
  start="$(date +%s)"
  timeout --kill-after=5s "${timeout_seconds}s" "${runner}" "${path}"
  status=$?
  duration=$(( $(date +%s) - start ))
  if [[ "${status}" -eq 124 || "${status}" -eq 137 ]]; then
    printf 'TIMEOUT %s  %ss  limit=%ss\n' "${path}" "${duration}" "${timeout_seconds}"
    timed_out=$((timed_out + 1))
  elif [[ "${status}" -eq 0 ]]; then
    printf 'PASS %s  %ss\n' "${path}" "${duration}"
    passed=$((passed + 1))
  else
    printf 'FAIL %s  %ss  exit=%s\n' "${path}" "${duration}" "${status}"
    failed=$((failed + 1))
  fi
done < "${manifest}"

printf '\nMandatory tests: %s\nPassed: %s\nFailed: %s\nTimed out: %s\n' "${total}" "${passed}" "${failed}" "${timed_out}"
[[ "${failed}" -eq 0 && "${timed_out}" -eq 0 ]]
