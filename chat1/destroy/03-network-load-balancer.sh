#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

if [[ -z "${LOAD_BALANCER_ARN:-}" ]]; then
  echo "No NLB state found."
  exit 0
fi

echo "Deleting Network Load Balancer..."
awsr elbv2 delete-load-balancer --load-balancer-arn "${LOAD_BALANCER_ARN}" 2>/dev/null || true

echo "Waiting for NLB deletion..."
awsr elbv2 wait load-balancers-deleted --load-balancer-arns "${LOAD_BALANCER_ARN}" 2>/dev/null || true
