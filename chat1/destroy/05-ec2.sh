#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

if [[ -z "${INSTANCE_ID:-}" ]]; then
  echo "No EC2 state found."
  exit 0
fi

echo "Terminating EC2 ${INSTANCE_ID}..."
awsr ec2 terminate-instances --instance-ids "${INSTANCE_ID}" >/dev/null 2>&1 || true
awsr ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}" 2>/dev/null || true
