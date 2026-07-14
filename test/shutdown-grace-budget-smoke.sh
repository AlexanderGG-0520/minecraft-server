#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${repo}"
source ./scripts/lib/logging.sh
source ./scripts/lib/numeric_validation.sh
source ./scripts/lib/shutdown_budget.sh

STOP_SERVER_ANNOUNCE_DELAY=0
SHUTDOWN_SAVE_WAIT_SECONDS=3
RCON_RETRIES=5
RCON_RETRY_DELAY=1
RCON_TIMEOUT=5
SHUTDOWN_WAIT_TIMEOUT=90
SHUTDOWN_TERM_WAIT=10
RCON_STOP_LOCK_WAIT_TIMEOUT=30
READY_DELAY=5
export STOP_SERVER_ANNOUNCE_DELAY SHUTDOWN_SAVE_WAIT_SECONDS RCON_RETRIES RCON_RETRY_DELAY
export RCON_TIMEOUT SHUTDOWN_WAIT_TIMEOUT SHUTDOWN_TERM_WAIT RCON_STOP_LOCK_WAIT_TIMEOUT READY_DELAY

test "$(shutdown_rcon_command_budget_seconds)" -eq 29
test "$(shutdown_rcon_first_attempt_success_seconds)" -eq 18
test "$(shutdown_rcon_flush_fallback_success_seconds)" -eq 23
test "$(shutdown_rcon_all_attempts_fail_seconds)" -eq 116
test "$(shutdown_rcon_stop_budget_seconds)" -eq 119
test "$(shutdown_graceful_budget_seconds)" -eq 219
test "$(shutdown_recommended_grace_seconds)" -eq 240

RCON_RETRIES=3
RCON_TIMEOUT=2
RCON_RETRY_DELAY=4
test "$(shutdown_rcon_command_budget_seconds)" -eq 14

RCON_RETRIES=5
RCON_TIMEOUT=5
RCON_RETRY_DELAY=1
STOP_SERVER_ANNOUNCE_DELAY=7
test "$(shutdown_rcon_stop_budget_seconds)" -eq 184
STOP_SERVER_ANNOUNCE_DELAY=0

for manifest in \
  examples/kubernetes/fabric-basic.yaml \
  examples/kubernetes/fabric-hardcore-smp.yaml \
  examples/kubernetes/fabric-hardcore-smp-gpu-c2me.yaml \
  examples/kubernetes/paper-pvc/deployment.yaml \
  examples/kubernetes/paper-minio-assets/deployment.yaml; do
  grep -F 'terminationGracePeriodSeconds: 240' "${manifest}" >/dev/null
  ! grep -Eq 'preStop:|rcon-stop' "${manifest}"
  grep -F 'TERM' "${manifest}" >/dev/null
done

grep -F 'modeled bounded default shutdown path is 219 seconds' README.md >/dev/null
grep -F 'terminationGracePeriodSeconds: 240' README.md >/dev/null
grep -F 'trap '\''graceful_shutdown'\'' TERM INT QUIT' entrypoint.sh >/dev/null
grep -F 'ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]' Dockerfile >/dev/null
grep -F 'stop_grace_period: 240s' examples/docker/fabric/compose.yml >/dev/null
grep -F 'stop_grace_period: 240s' examples/docker/fabric-c2me-gpu-accelerated/compose.yml >/dev/null
grep -F 'stop_grace_period: 240s' examples/docker/forge/compose.yml >/dev/null
