#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib.sh"

if [[ -z "${TARGET_GROUP_ARN:-}" ]]; then
  echo "No target group state found."
  exit 0
fi

echo "Deleting target group..."
awsr elbv2 delete-target-group --target-group-arn "${TARGET_GROUP_ARN}" 2>/dev/null || true
